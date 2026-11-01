"""SNS（events / alerts）のメッセージを Discord に送る（LC9、monitoring-design.md）。

- メッセージの形（独自 JSON、CloudWatch アラーム、AWS Budgets のテキスト）を判定して文面を作る。
  判別できない形は warn として送る（落とさない）。
- AWS のアラームと予算の通知は、生の本文を転送せず必要な項目だけで文面を作る（アカウント ID などを含むため）。
- 送信前に識別子（ARN、12 桁の数字、IPv4、インスタンス ID）を検査し、見つかれば送信を中止して失敗にする。
- Discord への POST は 5 秒のタイムアウトで、最大 2 回まで再試行する。429 は retry_after に従う。
"""

import json
import os
import random
import re
import time
import urllib.error
import urllib.request

SEVERITIES = ('info', 'warn', 'error')
# アラーム名は "<prefix>-<種類>"。prefix は非公開なので、種類だけを文面に使う。
ALARM_SEVERITY = {'backup-failed': 'error', 'disk-high': 'warn', 'backup-bucket-large': 'warn'}
IDENTIFIER_PATTERNS = {
  'arn': re.compile(r'arn:aws[a-z-]*:'),
  'account-id': re.compile(r'(?<![0-9])[0-9]{12}(?![0-9])'),
  'ipv4': re.compile(r'(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])'),
  'instance-id': re.compile(r'\bi-[0-9a-f]{8,17}\b'),
}
MAX_ATTEMPTS = 3
TIMEOUT_SECONDS = 5
MAX_LENGTH = 1900

_webhook_cache = {}


class UnsafeMessage(Exception):
  """本文に識別子が含まれていたため送らなかった。"""


def classify(message):
  """SNS の本文から (severity, 文面) を作る。"""
  try:
    data = json.loads(message)
  except (TypeError, ValueError):
    data = None
  if isinstance(data, dict) and 'AlarmName' in data:
    name = str(data['AlarmName'])
    state = str(data.get('NewStateValue', 'UNKNOWN'))
    alarm = next((kind for kind in ALARM_SEVERITY if name.endswith('-' + kind)), 'unknown')
    if state == 'OK':
      severity = 'info'
    else:
      severity = ALARM_SEVERITY.get(alarm, 'warn')
    return severity, f'アラーム {alarm}: {state}'
  if isinstance(data, dict) and data.get('source') in ('host', 'workflow', 'watchdog'):
    severity = data.get('severity') if data.get('severity') in SEVERITIES else 'warn'
    event = str(data.get('event', 'event'))
    return severity, f'{event}: {data.get("message", "")}'
  if isinstance(message, str) and 'AWS Budget' in message:
    percents = [float(value) for value in re.findall(r'([0-9]+(?:\.[0-9]+)?)%', message)]
    kind = '予測' if 'FORECASTED' in message.upper() else '実績'
    if percents and max(percents) >= 100:
      return 'error', f'予算アラート: 月の予算に対する{kind}が 100% に達しました。'
    return 'warn', f'予算アラート: 月の予算に対する{kind}が 80% に達しました。'
  return 'warn', f'判別できない通知: {message}'


def check_safe(text):
  found = sorted(name for name, pattern in IDENTIFIER_PATTERNS.items() if pattern.search(text))
  if found:
    # 検出した値そのものはログにも出さない。
    raise UnsafeMessage('Message contains identifiers: ' + ', '.join(found))


def format_message(severity, text):
  label = {'info': 'ℹ️ info', 'warn': '⚠️ warn', 'error': '🚨 error'}[severity]
  content = f'[{label}] {text}'
  return content if len(content) <= MAX_LENGTH else content[:MAX_LENGTH - 1] + '…'


def webhook_url():
  name = os.environ['WEBHOOK_PARAMETER']
  if name not in _webhook_cache:
    import boto3  # Lambda の実行環境に含まれる。テストでは差し替える。
    reply = boto3.client('ssm').get_parameter(Name=name, WithDecryption=True)
    _webhook_cache[name] = reply['Parameter']['Value']
  return _webhook_cache[name]


def retry_delay(attempt, error):
  if isinstance(error, urllib.error.HTTPError) and error.code == 429:
    try:
      return float(json.loads(error.read().decode())['retry_after'])
    except (ValueError, KeyError, TypeError):
      pass
  # 指数バックオフ＋ジッター
  return (2 ** attempt) * 0.5 + random.uniform(0, 0.5)


def post(content, opener=urllib.request.urlopen, sleep=time.sleep):
  body = json.dumps({'content': content, 'allowed_mentions': {'parse': []}}).encode()
  last_error = None
  for attempt in range(MAX_ATTEMPTS):
    request = urllib.request.Request(webhook_url(), data=body, method='POST',
                                     headers={'Content-Type': 'application/json', 'User-Agent': 'minecraft-notifier'})
    try:
      with opener(request, timeout=TIMEOUT_SECONDS) as response:
        if 200 <= response.status < 300:
          return
        last_error = RuntimeError(f'Unexpected status {response.status}')
    except urllib.error.HTTPError as error:
      last_error = error
      if error.code < 500 and error.code != 429:
        break
    except (urllib.error.URLError, TimeoutError) as error:
      last_error = error
    if attempt < MAX_ATTEMPTS - 1:
      sleep(retry_delay(attempt, last_error))
  raise RuntimeError(f'Discord delivery failed: {type(last_error).__name__}')


def handler(event, _context=None, opener=urllib.request.urlopen, sleep=time.sleep):
  sent = 0
  for record in event.get('Records', []):
    severity, text = classify(record['Sns']['Message'])
    check_safe(text)
    post(format_message(severity, text), opener=opener, sleep=sleep)
    sent += 1
  return {'sent': sent}
