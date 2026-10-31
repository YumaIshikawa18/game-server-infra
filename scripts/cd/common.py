"""AWS 応答を公開ログへ出さない、デプロイと運用の共通処理。"""

import contextlib
import json
import os
import pathlib
import re
import subprocess
import tempfile
import time
import uuid

from scripts.ci.plan import ROOT, required, strings


class AwsError(RuntimeError):
  def __init__(self, code):
    super().__init__('AWS operation failed')
    self.code = code


def aws(*args):
  env = {key: value for key, value in os.environ.items()
       if key not in ('GH_TOKEN', 'TF_INPUTS_JSON', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN')}
  result = subprocess.run(['aws', *args, '--output', 'json', '--no-cli-pager'],
              env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
              timeout=120, check=False)
  if result.returncode:
    match = re.search(rb'\(([A-Za-z0-9]+)\)', result.stderr)
    raise AwsError(match.group(1).decode() if match else 'Unknown')
  return json.loads(result.stdout) if result.stdout.strip() else {}


def mask():
  values = [required('AWS_ROLE_ARN'), required('MC_LOCK_BUCKET'), required('MC_LOCK_KEY')]
  for key in ('MC_INSTANCE_ID', 'MC_EVENTS_TOPIC_ARN', 'TF_STATE_BUCKET', 'TF_STATE_KEY'):
    if os.environ.get(key):
      values.append(os.environ[key])
  if os.environ.get('TF_INPUTS_JSON'):
    # 1 文字の真偽値・件数等は識別子ではない。生の入力値はそもそも出力しない。
    values.extend(value for value in strings(json.loads(os.environ['TF_INPUTS_JSON'])) if len(value) >= 3)
  values.append(required('AWS_ROLE_ARN').rsplit('/', 1)[-1])
  values.extend(re.findall(r'(?<!\d)\d{12}(?!\d)', required('AWS_ROLE_ARN')))
  for value in values:
    if value:
      escaped = value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
      print('::add-mask::' + escaped)


def require_master():
  if required('GITHUB_REF') != 'refs/heads/master':
    raise ValueError('Only master may operate production')
  expected = required('GITHUB_SHA')
  if not re.fullmatch(r'[0-9a-f]{40}', expected):
    raise ValueError('Invalid revision')
  result = subprocess.run(['git', 'ls-remote', '--exit-code', 'origin', 'refs/heads/master'],
              cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
              timeout=30, check=True)
  if result.stdout.decode().split()[0] != expected:
    raise ValueError('Outdated master revision; run again and approve the new plan')


def instance_id():
  value = os.environ.get('MC_INSTANCE_ID', '')
  if not value:
    result = aws('ec2', 'describe-instances', '--filters', json.dumps([
      {'Name': 'tag:mc:managed', 'Values': ['true']},
      {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'stopping', 'stopped']},
    ]))
    values = [item['InstanceId'] for group in result.get('Reservations', []) for item in group['Instances']]
    if len(values) != 1:
      raise ValueError('Exactly one active managed instance is required')
    value = values[0]
  if not re.fullmatch(r'i-[0-9a-f]{8}(?:[0-9a-f]{9})?', value):
    raise ValueError('Invalid instance identifier')
  return value


def instance():
  result = aws('ec2', 'describe-instances', '--instance-ids', instance_id())
  values = [item for group in result.get('Reservations', []) for item in group['Instances']]
  if len(values) != 1 or {tag['Key']: tag['Value'] for tag in values[0].get('Tags', [])}.get('mc:managed') != 'true':
    raise ValueError('Exactly one managed Minecraft instance is required')
  return values[0]


def wait_state(target, timeout=600):
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    if instance()['State']['Name'] == target:
      return
    time.sleep(15)
  raise TimeoutError('Instance state wait timed out')


def wait_ssm(timeout=180):
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    response = aws('ssm', 'describe-instance-information', '--filters',
             json.dumps([{'Key': 'InstanceIds', 'Values': [instance_id()]}]))
    if any(item.get('PingStatus') == 'Online' for item in response.get('InstanceInformationList', [])):
      return
    time.sleep(15)
  raise TimeoutError('SSM did not become available')


def send(document, parameters=None):
  allowed = {'mc-stop', 'mc-health-check', 'mc-restore-apply'}
  if document not in allowed:
    raise ValueError('Unexpected SSM document')
  result = aws('ssm', 'send-command', '--instance-ids', instance_id(),
         '--document-name', document, '--timeout-seconds', '600',
         '--parameters', json.dumps(parameters or {}))
  return result['Command']['CommandId']


def wait_command(command_id, timeout=600):
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    try:
      value = aws('ssm', 'get-command-invocation', '--command-id', command_id,
            '--instance-id', instance_id())
    except AwsError as error:
      if error.code != 'InvocationDoesNotExist':
        raise
      time.sleep(3)
      continue
    if value['Status'] == 'Success':
      return
    if value['Status'] not in ('Pending', 'InProgress', 'Delayed'):
      raise RuntimeError('SSM command failed; see private AWS diagnostics')
    time.sleep(3)
  raise TimeoutError('SSM command wait timed out')


def health(timeout=600):
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    remaining = max(1, int(deadline - time.monotonic()))
    try:
      wait_command(send('mc-health-check'), timeout=min(30, remaining))
      return
    except AwsError:
      raise
    except RuntimeError:
      pass
    # 実行中のコマンドが時間切れなら重複送信せず、呼び出し元の復旧処理へ返す。
    time.sleep(min(15, max(0, deadline - time.monotonic())))
  raise TimeoutError('Minecraft health check timed out')


def stop(reason):
  state = instance()['State']['Name']
  if state == 'stopped':
    return
  if state == 'stopping':
    wait_state('stopped')
    return
  try:
    wait_ssm()
    send('mc-stop', {'reason': [reason]})
    # mc-stop は自インスタンスを停止するので、SSM の応答完了ではなく EC2 を待つ。
    wait_state('stopped')
  except (AwsError, RuntimeError, TimeoutError):
    aws('ec2', 'stop-instances', '--instance-ids', instance_id())
    wait_state('stopped')
    notify('backup-unavailable', 'warn')


def notify(event, severity='error'):
  if event not in ('deployment-failed', 'start-failed', 'stop-failed', 'restore-failed', 'backup-unavailable'):
    raise ValueError('Unexpected notification event')
  aws('sns', 'publish', '--topic-arn', required('MC_EVENTS_TOPIC_ARN'),
    '--message', json.dumps({'event': event, 'severity': severity,
                 'message': 'Minecraft operation requires attention.'}),
    '--message-attributes', json.dumps({key: {'DataType': 'String', 'StringValue': value}
                       for key, value in {'event': event, 'severity': severity}.items()}))


def summary(message):
  with open(required('GITHUB_STEP_SUMMARY'), 'a', encoding='utf-8') as target:
    target.write(message + '\n')


class Lock:
  """期限だけで奪わず、ETag と一意な所有者で解放する。"""

  def __init__(self, timeout=300):
    self.timeout = timeout
    self.etag = None
    self.keep = False

  def __enter__(self):
    bucket, key = required('MC_LOCK_BUCKET'), required('MC_LOCK_KEY')
    if not key.startswith('control/') or key.endswith('.tflock'):
      raise ValueError('Operational lock must use a dedicated control key')
    os.umask(0o077)
    private = ROOT / '.ci-private'
    private.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=private) as directory:
      body = pathlib.Path(directory) / 'owner.json'
      body.write_text(json.dumps({'owner': str(uuid.uuid4()),
                    'run_id': required('GITHUB_RUN_ID'),
                    'attempt': required('GITHUB_RUN_ATTEMPT')}))
      deadline = time.monotonic() + self.timeout
      while True:
        try:
          response = aws('s3api', 'put-object', '--bucket', bucket, '--key', key,
                   '--body', str(body), '--server-side-encryption', 'AES256',
                   '--if-none-match', '*')
          self.etag = response['ETag']
          return self
        except AwsError as error:
          if error.code not in ('PreconditionFailed', 'ConditionalRequestConflict'):
            raise
          if time.monotonic() >= deadline:
            raise TimeoutError('Another operation holds the lock; check and retry') from None
          time.sleep(10)

  def __exit__(self, kind, value, traceback):
    if self.etag and not self.keep:
      aws('s3api', 'delete-object', '--bucket', required('MC_LOCK_BUCKET'),
        '--key', required('MC_LOCK_KEY'), '--if-match', self.etag)
    elif self.keep:
      summary('安全確認のため運用ロックを保持しました。runbook の確認・解除手順を実行してください。')


@contextlib.contextmanager
def private_work():
  os.umask(0o077)
  private = ROOT / '.ci-private'
  private.mkdir(exist_ok=True)
  with tempfile.TemporaryDirectory(dir=private) as directory:
    yield pathlib.Path(directory)
