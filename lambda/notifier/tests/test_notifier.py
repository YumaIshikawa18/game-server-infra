import io
import json
import pathlib
import sys
import urllib.error

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import notifier  # noqa: E402


@pytest.fixture(autouse=True)
def webhook(monkeypatch):
  monkeypatch.setenv('WEBHOOK_PARAMETER', '/example/minecraft/discord-webhook')
  monkeypatch.setattr(notifier, '_webhook_cache', {'/example/minecraft/discord-webhook': 'https://discord.example/api/webhooks/test'})


class Response:
  def __init__(self, status=204):
    self.status = status

  def __enter__(self):
    return self

  def __exit__(self, *args):
    return False


def http_error(code, body=b'{}'):
  return urllib.error.HTTPError('https://discord.example', code, 'error', {}, io.BytesIO(body))


def record(message):
  return {'Records': [{'Sns': {'Message': message}}]}


def test_host_event_keeps_severity_and_posts():
  posted = []

  def opener(request, timeout):
    posted.append((json.loads(request.data), timeout))
    return Response()

  message = json.dumps({'source': 'host', 'event': 'server_stopping', 'severity': 'info', 'message': '停止します'})
  assert notifier.handler(record(message), opener=opener, sleep=lambda _: None) == {'sent': 1}
  assert posted[0][0]['content'].startswith('[ℹ️ info] server_stopping')
  assert posted[0][0]['allowed_mentions'] == {'parse': []}
  assert posted[0][1] == 5


@pytest.mark.parametrize('name,state,severity', [
  ('mc-example-backup-failed', 'ALARM', 'error'),
  ('mc-example-disk-high', 'ALARM', 'warn'),
  ('mc-example-backup-failed', 'OK', 'info'),
  ('mc-example-other', 'ALARM', 'warn'),
])
def test_alarm_severity_from_name(name, state, severity):
  message = json.dumps({'AlarmName': name, 'NewStateValue': state, 'AWSAccountId': '123456789012',
                        'AlarmArn': 'arn:aws:cloudwatch:ap-northeast-1:123456789012:alarm:x'})
  result, text = notifier.classify(message)
  assert result == severity
  # 生の本文（アカウント ID や ARN）は文面に入れない。
  notifier.check_safe(text)
  assert 'example' not in text


@pytest.mark.parametrize('percent,severity', [('80.0', 'warn'), ('100.0', 'error')])
def test_budget_threshold(percent, severity):
  message = f'AWS Budget Notification\nAWS Account 123456789012\nAlert Threshold: > {percent}%\nACTUAL'
  result, text = notifier.classify(message)
  assert result == severity
  notifier.check_safe(text)


def test_unknown_format_is_sent_as_warn():
  assert notifier.classify('plain text')[0] == 'warn'


@pytest.mark.parametrize('text', [
  'id i-0123456789abcdef0', 'account 123456789012', 'ip 203.0.113.10', 'arn:aws:sns:ap-northeast-1:x:y',
])
def test_identifiers_are_refused(text):
  with pytest.raises(notifier.UnsafeMessage):
    notifier.check_safe(text)


def test_unsafe_message_is_not_posted():
  calls = []
  message = json.dumps({'source': 'host', 'event': 'x', 'severity': 'error', 'message': 'i-0123456789abcdef0'})
  with pytest.raises(notifier.UnsafeMessage):
    notifier.handler(record(message), opener=lambda *a, **k: calls.append(a), sleep=lambda _: None)
  assert calls == []


def test_retry_after_on_429_then_success():
  replies = [http_error(429, b'{"retry_after": 1.5}'), Response()]
  delays = []

  def opener(request, timeout):
    reply = replies.pop(0)
    if isinstance(reply, Exception):
      raise reply
    return reply

  notifier.post('hello', opener=opener, sleep=delays.append)
  assert delays == [1.5]


def test_gives_up_after_three_attempts():
  attempts = []

  def opener(request, timeout):
    attempts.append(1)
    raise urllib.error.URLError('timeout')

  with pytest.raises(RuntimeError):
    notifier.post('hello', opener=opener, sleep=lambda _: None)
  assert len(attempts) == 3


def test_client_error_is_not_retried():
  attempts = []

  def opener(request, timeout):
    attempts.append(1)
    raise http_error(404)

  with pytest.raises(RuntimeError):
    notifier.post('hello', opener=opener, sleep=lambda _: None)
  assert len(attempts) == 1


def test_long_message_is_truncated():
  assert len(notifier.format_message('info', 'x' * 5000)) == notifier.MAX_LENGTH
