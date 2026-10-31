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
  if target.exists():
    values = json.loads(target.read_text())
    if values['github_repository'] != repository:
      raise ValueError('Existing generated inputs belong to another repository')
  else:
    prefix = 'mc-' + secrets.token_hex(4)
    providers = command(['aws', '--profile', 'personal', 'iam',
                         'list-open-id-connect-providers', '--output', 'json'])
    values = {
      'prefix': prefix, 'region': 'ap-northeast-1',
      'state_bucket_name': prefix + '-state-' + secrets.token_hex(4),
      'backup_bucket_name': prefix + '-backup-' + secrets.token_hex(4),
      'state_key': 'prod/terraform.tfstate', 'lock_key': 'control/operation.lock',
      'github_repository': repository,
      'use_existing_github_oidc': any(provider['Arn'].endswith(
        'oidc-provider/token.actions.githubusercontent.com') for provider in providers['OpenIDConnectProviderList']),
    }
    private_json(target, values)
  print('非公開の bootstrap 入力を準備しました。既存の allowed_account_ids は保持しています。')


if __name__ == '__main__':
  try:
    main()
  except Exception as error:
    print('非公開設定の準備に失敗しました（' + type(error).__name__ + '）。値は出力していません。', file=sys.stderr)
    if isinstance(error, RuntimeError):
      print(str(error), file=sys.stderr)
    sys.exit(1)
