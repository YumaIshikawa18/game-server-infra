"""GitHub の Secrets と Variables を、値を画面に出さずに登録する（本人が手元で実行する）。

値は .ci-private/github-secrets.json（prepare.py が作る、gitignore 済み）から gh の標準入力で渡す。
Environments（prod / ops）と Branch protection は README の手順で本人が設定する。
"""

import json
import subprocess
import sys

from scripts.local.prepare import ROOT

SECRETS = ('AWS_PLAN_ROLE_ARN', 'AWS_APPLY_ROLE_ARN', 'AWS_OPS_ROLE_ARN', 'TF_STATE_BUCKET', 'TF_STATE_KEY',
           'TF_INPUTS_JSON', 'MC_LOCK_BUCKET', 'MC_LOCK_KEY', 'MC_EVENTS_TOPIC_ARN')


def gh(args, value=None):
  # 値はコマンドライン引数に置かず、標準入力で渡す。gh の出力も表示しない。
  result = subprocess.run(['gh', *args], cwd=ROOT, input=value, text=True, capture_output=True, check=False)
  if result.returncode:
    raise RuntimeError('gh failed: ' + ' '.join(args[:3]))


def main():
  values = json.loads((ROOT / '.ci-private/github-secrets.json').read_text())
  missing = [name for name in SECRETS if not values.get(name)]
  if missing:
    raise ValueError('Prepared values are missing: ' + ', '.join(missing))
  login = subprocess.run(['gh', 'api', 'user', '--jq', '.login'], capture_output=True, text=True, check=True).stdout.strip()
  for name in SECRETS:
    gh(['secret', 'set', name], values[name])
  gh(['variable', 'set', 'AWS_REGION', '--body', 'ap-northeast-1'])
  gh(['variable', 'set', 'OPERATOR_LOGIN', '--body', login])
  print(f'Secrets {len(SECRETS)} 件と Variables 2 件を登録しました（値は表示していません）。')


if __name__ == '__main__':
  try:
    main()
  except Exception as error:
    print('GitHub の設定に失敗しました（' + type(error).__name__ + '）。値は出力していません。', file=sys.stderr)
    if isinstance(error, (RuntimeError, ValueError)):
      print(str(error), file=sys.stderr)
    sys.exit(1)
