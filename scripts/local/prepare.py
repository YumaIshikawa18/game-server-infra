"""非公開の Terraform 入力を準備する。値は端末へ表示しない。AWS の変更は行わない。"""

import json
import os
import pathlib
import re
import secrets
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def command(args):
  if args[0] == 'aws':
    args = ['aws', '--region', 'ap-northeast-1', *args[1:]]
  environment = {key: value for key, value in os.environ.items() if key not in (
    'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN',
    'AWS_PROFILE', 'AWS_ROLE_ARN', 'AWS_WEB_IDENTITY_TOKEN_FILE',
  )}
  result = subprocess.run(args, cwd=ROOT, env=environment, capture_output=True,
                          text=True, timeout=60, check=False)
  if result.returncode:
    raise RuntimeError('Read-only configuration discovery failed: ' + args[0])
  return json.loads(result.stdout)


def private_json(path, value):
  if subprocess.run(['git', 'check-ignore', '-q', str(path.relative_to(ROOT))],
                    cwd=ROOT, capture_output=True).returncode:
    raise ValueError('Private destination is not ignored by git')
  path.parent.mkdir(parents=True, exist_ok=True)
  temporary = path.with_suffix(path.suffix + '.new')
  descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
  try:
    with os.fdopen(descriptor, 'w', encoding='utf-8') as target:
      json.dump(value, target, indent=2)
      target.write('\n')
    os.replace(temporary, path)
    path.chmod(0o600)
  finally:
    temporary.unlink(missing_ok=True)


def main():
  identity = command(['aws', '--profile', 'personal', 'sts', 'get-caller-identity', '--output', 'json'])
  for path in (ROOT / 'bootstrap/local.auto.tfvars', ROOT / 'envs/prod/local.auto.tfvars'):
    allowed = re.findall(r'"(\d{12})"', path.read_text())
    if identity['Account'] not in allowed:
      raise ValueError('Active identity does not match the allowed account')
  repository = command(['gh', 'repo', 'view', '--json', 'nameWithOwner'])['nameWithOwner']
  target = ROOT / 'bootstrap/generated.auto.tfvars.json'
  # immutable subject が有効なら、sub は ID 付きの接頭辞になる。API の値をそのまま使う。
  oidc = command(['gh', 'api', f'repos/{repository}/actions/oidc/customization/sub'])
  subject_prefix = oidc.get('sub_claim_prefix') or f'repo:{repository}'
  if target.exists():
    values = json.loads(target.read_text())
    if values['github_repository'] != repository:
      raise ValueError('Existing generated inputs belong to another repository')
    if 'log_bucket_name' not in values:
      # 後から追加した入力だけを補い、既存の値は変えない。
      values['log_bucket_name'] = values['prefix'] + '-logs-' + secrets.token_hex(4)
      private_json(target, values)
    if values.get('github_oidc_subject_prefix') != subject_prefix:
      values['github_oidc_subject_prefix'] = subject_prefix
      private_json(target, values)
  else:
    prefix = 'mc-' + secrets.token_hex(4)
    providers = command(['aws', '--profile', 'personal', 'iam',
                         'list-open-id-connect-providers', '--output', 'json'])
    values = {
      'prefix': prefix, 'region': 'ap-northeast-1',
      'state_bucket_name': prefix + '-state-' + secrets.token_hex(4),
      'backup_bucket_name': prefix + '-backup-' + secrets.token_hex(4),
      'log_bucket_name': prefix + '-logs-' + secrets.token_hex(4),
      'state_key': 'prod/terraform.tfstate', 'lock_key': 'control/operation.lock',
      'github_repository': repository, 'github_oidc_subject_prefix': subject_prefix,
      'use_existing_github_oidc': any(provider['Arn'].endswith(
        'oidc-provider/token.actions.githubusercontent.com') for provider in providers['OpenIDConnectProviderList']),
    }
    private_json(target, values)
  print('非公開の bootstrap 入力を準備しました。既存の allowed_account_ids は保持しています。')
  prepare_prod(values, identity['Account'])


# 本人が書く値。メールアドレスと EULA への同意は本人だけが決められるので、生成しない。
PERSONAL_KEYS = {'notification_email': str, 'accept_minecraft_eula': bool, 'monthly_budget_usd': (int, float)}


def prepare_prod(values, account):
  """envs/prod の入力と backend 設定を作り、GitHub Secrets 用の値を非公開ファイルにまとめる。"""
  private_json(ROOT / 'envs/prod/generated.auto.tfvars.json', {
    key: values[key] for key in ('prefix', 'region', 'backup_bucket_name', 'log_bucket_name')})
  backend = ROOT / 'envs/prod/backend.hcl'
  if subprocess.run(['git', 'check-ignore', '-q', str(backend.relative_to(ROOT))],
                    cwd=ROOT, capture_output=True).returncode:
    raise ValueError('Private destination is not ignored by git')
  descriptor = os.open(backend, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
  with os.fdopen(descriptor, 'w', encoding='utf-8') as target:
    target.write(f'bucket = {json.dumps(values["state_bucket_name"])}\nkey = {json.dumps(values["state_key"])}\n'
                 f'region = {json.dumps(values["region"])}\n')
  personal_path = ROOT / 'envs/prod/private.auto.tfvars.json'
  if not personal_path.exists():
    print('envs/prod/private.auto.tfvars.json がまだありません。本人の値を書いてから、もう一度実行してください。')
    return
  personal = json.loads(personal_path.read_text())
  missing = [key for key, kind in PERSONAL_KEYS.items() if not isinstance(personal.get(key), kind)]
  if missing:
    raise ValueError('Personal inputs are missing or invalid: ' + ', '.join(missing))
  outputs = json.loads((ROOT / '.ci-private/bootstrap-outputs.json').read_text())
  roles = outputs['ci_role_arns']['value']
  # GitHub Secrets に本人が登録する値（cd-config.md の表）。ファイルは gitignore 済みで、内容は表示しない。
  private_json(ROOT / '.ci-private/github-secrets.json', {
    'AWS_PLAN_ROLE_ARN': roles['plan'], 'AWS_APPLY_ROLE_ARN': roles['apply'], 'AWS_OPS_ROLE_ARN': roles['ops'],
    'TF_STATE_BUCKET': values['state_bucket_name'], 'TF_STATE_KEY': values['state_key'],
    'MC_LOCK_BUCKET': values['state_bucket_name'], 'MC_LOCK_KEY': values['lock_key'],
    # notifier モジュールのトピック名（<prefix>-events）から決まるため、apply の前に用意できる。
    'MC_EVENTS_TOPIC_ARN': f'arn:aws:sns:{values["region"]}:{account}:{values["prefix"]}-events',
    'TF_INPUTS_JSON': json.dumps({
      'allowed_account_ids': [account], 'prefix': values['prefix'], 'region': values['region'],
      'backup_bucket_name': values['backup_bucket_name'], 'log_bucket_name': values['log_bucket_name'],
      **{key: personal[key] for key in PERSONAL_KEYS},
    }, separators=(',', ':')),
  })
  print('envs/prod の非公開入力、backend.hcl、GitHub Secrets 用の値（.ci-private/github-secrets.json）を準備しました。')


if __name__ == '__main__':
  try:
    main()
  except Exception as error:
    print('非公開設定の準備に失敗しました（' + type(error).__name__ + '）。値は出力していません。', file=sys.stderr)
    if isinstance(error, RuntimeError):
      print(str(error), file=sys.stderr)
    sys.exit(1)
