"""ホストの外からの強制停止（LC8、reliability-design.md §5）。5 分ごとに EventBridge Scheduler から起動する。

running の管理対象インスタンスについて、次のどれかに当たれば停止して events トピックに通知する。
  (a) 起動から 60 分以上たち、直近 60 分の ServerUp の最大値が 1 未満または欠測
  (b) StatusCheckFailed が直近 15 分すべて 1（5 分間隔で 3 点）
  (c) 起動から 12 時間以上
タグ mc:stopping=true のインスタンス（ホスト側が停止処理中）には触らない。
"""

import datetime
import json
import os

UNRESPONSIVE = datetime.timedelta(minutes=60)
STATUS_WINDOW = datetime.timedelta(minutes=15)
STATUS_POINTS = 3
MAX_RUNTIME = datetime.timedelta(hours=12)


def clients():
  import boto3  # Lambda の実行環境に含まれる。テストでは差し替える。
  return boto3.client('ec2'), boto3.client('cloudwatch'), boto3.client('sns')


def managed_instances(ec2):
  pages = ec2.get_paginator('describe_instances').paginate(Filters=[
    {'Name': 'tag:mc:managed', 'Values': ['true']},
    {'Name': 'tag:Project', 'Values': [os.environ['PROJECT_TAG']]},
    {'Name': 'instance-state-name', 'Values': ['running']},
  ])
  for page in pages:
    for reservation in page['Reservations']:
      yield from reservation['Instances']


def metric_values(cloudwatch, now, namespace, name, dimensions, window, period, stat):
  reply = cloudwatch.get_metric_data(
    StartTime=now - window, EndTime=now, ScanBy='TimestampDescending',
    MetricDataQueries=[{'Id': 'm', 'ReturnData': True, 'MetricStat': {
      'Metric': {'Namespace': namespace, 'MetricName': name, 'Dimensions': dimensions},
      'Period': period, 'Stat': stat}}])
  return reply['MetricDataResults'][0]['Values']


def stop_reason(instance, now, cloudwatch):
  """停止すべき理由を返す。不要なら None。"""
  tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
  if tags.get('mc:stopping') == 'true':
    return None
  uptime = now - instance['LaunchTime']
  if uptime >= MAX_RUNTIME:
    return 'max-runtime'
  if uptime >= UNRESPONSIVE:
    up = metric_values(cloudwatch, now, 'Minecraft', 'ServerUp', [], UNRESPONSIVE, 300, 'Maximum')
    if not up or max(up) < 1:
      return 'unresponsive'
  status = metric_values(cloudwatch, now, 'AWS/EC2', 'StatusCheckFailed',
                         [{'Name': 'InstanceId', 'Value': instance['InstanceId']}], STATUS_WINDOW, 300, 'Minimum')
  if len(status) >= STATUS_POINTS and all(value >= 1 for value in status[:STATUS_POINTS]):
    return 'status-check-failed'
  return None


def notify(sns, reason):
  message = {'source': 'watchdog', 'event': 'watchdog_stop', 'severity': 'error',
             'message': f'外部の監視がサーバーを強制停止しました（理由: {reason}、バックアップなし）。'}
  sns.publish(TopicArn=os.environ['EVENTS_TOPIC_ARN'], Message=json.dumps(message, ensure_ascii=False),
              MessageAttributes={'event': {'DataType': 'String', 'StringValue': 'watchdog_stop'},
                                 'severity': {'DataType': 'String', 'StringValue': 'error'}})


def handler(_event=None, _context=None, now=None, aws=None):
  ec2, cloudwatch, sns = aws or clients()
  now = now or datetime.datetime.now(datetime.timezone.utc)
  stopped = []
  for instance in managed_instances(ec2):
    reason = stop_reason(instance, now, cloudwatch)
    if reason:
      ec2.stop_instances(InstanceIds=[instance['InstanceId']])
      notify(sns, reason)
      stopped.append(reason)
  # インスタンス ID はログに出さない。
  print(json.dumps({'event': 'watchdog_checked', 'stopped': stopped}))
  return {'stopped': stopped}
