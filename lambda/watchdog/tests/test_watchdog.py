import datetime
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import watchdog  # noqa: E402

NOW = datetime.datetime(2026, 11, 1, 12, 0, tzinfo=datetime.timezone.utc)


@pytest.fixture(autouse=True)
def environment(monkeypatch):
  monkeypatch.setenv('PROJECT_TAG', 'example')
  monkeypatch.setenv('EVENTS_TOPIC_ARN', 'arn:aws:sns:ap-northeast-1:123456789012:example-events')


class Metrics:
  def __init__(self, server_up=(1.0,), status=(0.0, 0.0, 0.0)):
    self.values = {'ServerUp': list(server_up), 'StatusCheckFailed': list(status)}
    self.queries = []

  def get_metric_data(self, **kwargs):
    name = kwargs['MetricDataQueries'][0]['MetricStat']['Metric']['MetricName']
    self.queries.append(name)
    return {'MetricDataResults': [{'Values': self.values[name]}]}


class Ec2:
  def __init__(self, instances):
    self.instances = instances
    self.stopped = []
    self.filters = None

  def get_paginator(self, _name):
    ec2 = self

    class Paginator:
      def paginate(self, Filters):
        ec2.filters = Filters
        return [{'Reservations': [{'Instances': ec2.instances}]}]
    return Paginator()

  def stop_instances(self, InstanceIds):
    self.stopped.extend(InstanceIds)


class Sns:
  def __init__(self):
    self.messages = []

  def publish(self, **kwargs):
    self.messages.append(kwargs)


def instance(minutes, tags=()):
  return {'InstanceId': 'i-0123456789abcdef0', 'LaunchTime': NOW - datetime.timedelta(minutes=minutes),
          'Tags': [{'Key': key, 'Value': value} for key, value in tags]}


@pytest.mark.parametrize('minutes,expected', [(59, None), (60, 'unresponsive')])
def test_unresponsive_boundary(minutes, expected):
  assert watchdog.stop_reason(instance(minutes), NOW, Metrics(server_up=())) == expected


def test_server_up_zero_counts_as_unresponsive():
  assert watchdog.stop_reason(instance(90), NOW, Metrics(server_up=(0.0, 0.0))) == 'unresponsive'


def test_healthy_server_is_left_running():
  assert watchdog.stop_reason(instance(90), NOW, Metrics()) is None


@pytest.mark.parametrize('status,expected', [
  ((1.0, 1.0), None),  # 14 分相当（2 点）
  ((1.0, 1.0, 1.0), 'status-check-failed'),  # 15 分
  ((1.0, 0.0, 1.0), None),
])
def test_status_check_boundary(status, expected):
  assert watchdog.stop_reason(instance(30), NOW, Metrics(status=status)) == expected


@pytest.mark.parametrize('minutes,expected', [(11 * 60 + 59, None), (12 * 60, 'max-runtime')])
def test_max_runtime_boundary(minutes, expected):
  assert watchdog.stop_reason(instance(minutes), NOW, Metrics()) == expected


def test_host_stopping_is_not_touched():
  metrics = Metrics(server_up=())
  assert watchdog.stop_reason(instance(13 * 60, tags=[('mc:stopping', 'true')]), NOW, metrics) is None
  assert metrics.queries == []


def test_handler_stops_and_notifies_only_running_managed_instances():
  ec2 = Ec2([instance(12 * 60)])
  sns = Sns()
  assert watchdog.handler(now=NOW, aws=(ec2, Metrics(), sns)) == {'stopped': ['max-runtime']}
  assert ec2.stopped == ['i-0123456789abcdef0']
  assert sns.messages[0]['MessageAttributes']['severity']['StringValue'] == 'error'
  assert 'i-0' not in sns.messages[0]['Message']
  filters = {item['Name']: item['Values'] for item in ec2.filters}
  assert filters['instance-state-name'] == ['running'] and filters['tag:mc:managed'] == ['true']


def test_handler_does_nothing_without_instances():
  ec2 = Ec2([])
  sns = Sns()
  assert watchdog.handler(now=NOW, aws=(ec2, Metrics(), sns)) == {'stopped': []}
  assert ec2.stopped == [] and sns.messages == []
