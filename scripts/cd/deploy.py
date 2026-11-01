"""承認前 plan と承認後 apply。plan の値は公開しない。"""

import contextlib
import hashlib
import json
import os
import re
import sys

from scripts.cd import common
from scripts.ci import plan as ci


@contextlib.contextmanager
def step(name):
  """生の例外本文を表示せずに、失敗した処理だけを追えるようにする。"""
  try:
    yield
  except Exception as error:
    if not hasattr(error, '_deployment_step'):
      error._deployment_step = name
    raise


def diagnostics(error):
  allowed_steps = {'terraform-init', 'terraform-plan', 'terraform-show', 'operational-lock',
           'approval-comparison', 'replacement-protection', 'terraform-apply', 'smoke-test'}
  result = []
  seen = set()
  while error is not None and id(error) not in seen and len(result) < 4:
    seen.add(id(error))
    name = getattr(error, '_deployment_step', 'unknown')
    item = {'step': name if name in allowed_steps else 'unknown',
        'kind': 'aws' if isinstance(error, common.AwsError) else
            'timeout' if isinstance(error, TimeoutError) else
            'validation' if isinstance(error, ValueError) else 'runtime'}
    if isinstance(error, common.AwsError):
      code = error.code
      item['aws_code'] = code if re.fullmatch(r'[A-Za-z][A-Za-z0-9]{0,63}', code) else 'Unknown'
    result.append(item)
    error = error.__cause__ or error.__context__
  return result


def digest(plan):
  # フォーマットと未完了状態を共通の検査でも確認する。
  ci.summarize(plan)
  changes = sorted(plan.get('resource_changes', []), key=lambda item: item['address'])
  comparison = {
    'terraform_version': plan.get('terraform_version'),
    'changes': changes,
    'outputs': plan.get('output_changes', {}),
    'drift': sorted(plan.get('resource_drift', []), key=lambda item: item['address']),
    'variables': plan.get('variables', {}),
    'configuration': plan.get('configuration', {}),
    'planned_values': plan.get('planned_values', {}),
    # 参照元の一覧は同じ plan でも列挙順が変わる。属性パス内の順序と参照内容は維持する。
    'relevant_attributes': sorted(plan.get('relevant_attributes', []),
                   key=lambda item: json.dumps(item, sort_keys=True, separators=(',', ':'))),
  }
  raw = json.dumps(comparison, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
  return hashlib.sha256(raw.encode()).hexdigest()


def make_plan(work):
  directory = ci.ROOT / 'envs/prod'
  if not list(directory.glob('*.tf')) or not (directory / '.terraform.lock.hcl').is_file():
    raise ValueError('Production Terraform and lockfile are required')
  backend = work / 'backend.hcl'
  backend.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in {
    'bucket': ci.required('TF_STATE_BUCKET'), 'key': ci.required('TF_STATE_KEY'),
    'region': ci.required('AWS_REGION'), 'encrypt': True, 'use_lockfile': True,
  }.items()))
  with step('terraform-init'):
    ci.terraform(['init', '-input=false', '-lockfile=readonly', f'-backend-config={backend}'])
  path = work / 'plan.bin'
  with step('terraform-plan'):
    ci.terraform(['plan', '-input=false', '-no-color', '-lock-timeout=5m', f'-out={path}'])
  with step('terraform-show'):
    plan = json.loads(ci.terraform(['show', '-json', str(path)]))
  return path, plan


def report(plan):
  values = [*ci.strings(ci.inputs()), ci.required('TF_STATE_BUCKET'), ci.required('TF_STATE_KEY')]
  common.summary(ci.summarize(plan, values))
  common.summary('Commit: `' + ci.required('GITHUB_SHA') + '`')


def replacement_ids(plan):
  ids = []
  for change in plan.get('resource_changes', []):
    if change.get('type') == 'aws_instance' and 'delete' in change['change']['actions']:
      before = change['change'].get('before') or {}
      identity = before.get('id', '')
      if not re.fullmatch(r'i-[0-9a-f]{8}(?:[0-9a-f]{9})?', identity):
        raise ValueError('Replacement instance ID is unavailable')
      ids.append(identity)
  return ids


def replacement_stop(plan):
  for identity in replacement_ids(plan):
    # アドレスが module 配下でも検出し、無関係な EC2 は処理しない。
    if identity != common.instance_id():
      raise ValueError('Plan replaces an unexpected instance; inspect before applying')
    state = common.instance()['State']['Name']
    if state == 'running':
      common.wait_ssm()
      command = common.send('mc-stop', {'reason': ['replace'], 'require_backup': ['true']})
      common.wait_command(command, timeout=common.STOP_COMMAND_TIMEOUT)
      common.wait_state('stopped', timeout=300)
    elif state != 'stopped':
      raise ValueError('Replacement requires a running or stopped instance')


def smoke():
  # 置き換えで ID が変わるため、apply 後は outputs から取得する。
  values = json.loads(ci.terraform(['output', '-json']))
  os.environ['MC_INSTANCE_ID'] = values['instance_id']['value']
  if common.instance()['State']['Name'] == 'running':
    common.wait_ssm()
    common.health()
    common.summary('適用後の Minecraft ヘルスチェックが成功しました。')
  elif common.instance()['State']['Name'] == 'stopped':
    common.summary('インスタンス停止中のためヘルスチェックを省略しました。稼働確認の成功を意味しません。')
  else:
    raise ValueError('Unexpected post-apply instance state')


def prepare():
  common.require_master()
  with common.private_work() as work:
    _, plan = make_plan(work)
    report(plan)
    # ジョブ出力は秘匿値を含まない digest のみ。
    with open(ci.required('GITHUB_OUTPUT'), 'a', encoding='utf-8') as target:
      # 部分文字列の Secrets マスクに偶然一致しないよう区切って転送する。
      target.write('plan_digest=' + ':'.join(digest(plan)) + '\n')


def apply():
  expected = ci.required('EXPECTED_PLAN_DIGEST').replace(':', '')
  if not re.fullmatch(r'[0-9a-f]{64}', expected):
    raise ValueError('Approved plan digest is missing')
  common.require_master()
  with step('operational-lock'), common.Lock() as lock, common.private_work() as work:
    common.require_master()
    path, plan = make_plan(work)
    with step('approval-comparison'):
      if digest(plan) != expected:
        raise ValueError('Plan changed after approval; rerun and approve again')
    common.require_master()
    # 変更開始後に失敗したら、途中の状態を確認するまでロックを残す。
    lock.keep = True
    with step('replacement-protection'):
      replacement_stop(plan)
    with step('terraform-apply'):
      ci.terraform(['apply', '-input=false', '-no-color', str(path)])
    with step('smoke-test'):
      smoke()
    lock.keep = False


def main():
  try:
    action = sys.argv[1]
    if action == 'mask':
      common.mask()
    elif action == 'prepare':
      prepare()
    elif action == 'apply':
      apply()
    elif action == 'notify-failure':
      common.notify('deployment-failed')
    else:
      raise ValueError('Unknown deployment operation')
  except Exception as error:
    print('::error::Deployment step failed. Inspect the safe summary and rollback runbook; raw AWS output is withheld.')
    print('deployment_errors=' + json.dumps(diagnostics(error), sort_keys=True))
    return 1
  return 0


if __name__ == '__main__':
  sys.exit(main())
