"""本人が master から実行する start / stop / restore。"""

import os
import re
import sys
import time

from scripts.cd import common


# modules/minecraft_server/ssm.tf の mc-restore-apply（timeoutSeconds = 1800）より長くする。
RESTORE_TIMEOUT = 1800 + 120

def backup_key(value):
  if len(value) > 512 or not re.fullmatch(r'(?:stop|hourly)/[A-Za-z0-9_./-]+\.tar\.zst', value):
    raise ValueError('Select a backup archive under stop/ or hourly/')
  if any(segment in ('', '.', '..') for segment in value.split('/')):
    raise ValueError('Invalid backup key segment')
  return value


def start(lock):
  before = common.instance()
  tags = {item['Key']: item['Value'] for item in before.get('Tags', [])}
  if 'mc:mode' in tags:
    raise ValueError('Restore mode must be resolved before starting')
  state = before['State']['Name']
  if state == 'stopping' or tags.get('mc:stopping') == 'true':
    common.wait_state('stopped')
    state = 'stopped'
  if state not in ('stopped', 'running'):
    raise ValueError('Unexpected starting state')
  began = time.monotonic()
  lock.keep = True
  try:
    if state == 'stopped':
      common.aws('ec2', 'start-instances', '--instance-ids', common.instance_id())
      common.wait_state('running')
    common.wait_ssm()
    common.health()
    common.summary(f'起動・Minecraft 接続確認が成功しました（{int(time.monotonic() - began)} 秒）。')
    lock.keep = False
  except Exception:
    common.stop('start-failed')
    lock.keep = False
    raise


def stop(lock):
  lock.keep = True
  common.stop('manual')
  lock.keep = False
  common.summary('インスタンスの停止を確認しました。')


def restore(lock):
  key = backup_key(common.required('RESTORE_KEY'))
  if common.instance()['State']['Name'] != 'stopped':
    raise ValueError('Stop the instance before restoring')
  lock.keep = True
  try:
    common.aws('ec2', 'create-tags', '--resources', common.instance_id(),
           '--tags', 'Key=mc:mode,Value=restore')
    common.aws('ec2', 'start-instances', '--instance-ids', common.instance_id())
    common.wait_state('running')
    common.wait_ssm()
    # SSM 文書の実行上限（1800 秒）より長く待ち、復元の実行中にインスタンスを止めない。
    common.wait_command(common.send('mc-restore-apply', {'key': [key]}), timeout=RESTORE_TIMEOUT)
  finally:
    # 成否によらず、ホストの停止を確認してから restore タグを解除する。
    common.aws('ec2', 'stop-instances', '--instance-ids', common.instance_id())
    common.wait_state('stopped')
    common.aws('ec2', 'delete-tags', '--resources', common.instance_id(),
           '--tags', 'Key=mc:mode')
    lock.keep = False
  common.summary('バックアップを復元して停止しました。start workflow で起動してください。')


def main():
  action = sys.argv[1] if len(sys.argv) > 1 else ''
  try:
    if action == 'mask':
      common.mask()
      return 0
    if action not in ('start', 'stop', 'restore'):
      raise ValueError('Unknown operation')
    if common.required('GITHUB_ACTOR') != common.required('OPERATOR_LOGIN'):
      raise ValueError('Only the configured operator may execute operations')
    common.require_master()
    with common.Lock() as lock:
      common.require_master()
      {'start': start, 'stop': stop, 'restore': restore}[action](lock)
  except Exception:
    print('::error::Operation failed. Check the safe summary and recovery runbook; raw AWS output is withheld.')
    if action in ('start', 'stop', 'restore'):
      try:
        common.notify(action + '-failed')
      except Exception:
        print('::error::Failure notification could not be delivered; inspect GitHub Actions and AWS privately.')
    return 1
  return 0


if __name__ == '__main__':
  sys.exit(main())
