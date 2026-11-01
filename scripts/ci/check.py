"""AWS 認証を渡さない CI チェック。欠落する成果物は失敗にする。"""

import ipaddress
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
VERSIONS = dict(line.split() for line in (ROOT / '.tool-versions').read_text().splitlines())


def run(args, cwd=ROOT):
  subprocess.run(args, cwd=cwd, check=True)


def image(tool, args, directory=ROOT, offline=False, entrypoint=None):
  extra = ['--entrypoint', entrypoint] if entrypoint else []
  if tool == 'tflint':
    (ROOT / '.ci-private/tflint').mkdir(parents=True, exist_ok=True)
    extra += ['-e', 'TFLINT_PLUGIN_DIR=/workspace/.ci-private/tflint']
  images = {
    'terraform': f'hashicorp/terraform:{VERSIONS["terraform"]}',
    'tflint': f'ghcr.io/terraform-linters/tflint:v{VERSIONS["tflint"]}',
    'checkov': f'bridgecrew/checkov:{VERSIONS["checkov"]}',
    'shellcheck': f'koalaman/shellcheck:v{VERSIONS["shellcheck"]}',
    'bats': f'bats/bats:{VERSIONS["bats"]}',
    'gitleaks': f'ghcr.io/gitleaks/gitleaks:v{VERSIONS["gitleaks"]}',
    'python': f'python:{VERSIONS["python"]}-slim',
  }
  work = '/workspace/' + directory.relative_to(ROOT).as_posix()
  network = ['--network', 'none'] if offline else []
  run(['docker', 'run', '--rm', *network, *extra, '-v', f'{ROOT}:/workspace', '-w', work,
     images[tool], *args])


def modules():
  paths = [ROOT / 'bootstrap', ROOT / 'envs/prod']
  paths.extend(sorted((ROOT / 'modules').glob('*')))
  if len(paths) < 3 or any(not list(p.glob('*.tf')) for p in paths):
    raise ValueError('Terraform roots and reusable modules must exist')
  return paths


def findings(text):
  """値を表示せず、識別子の種類だけを返す。"""
  result = set()
  if re.search(r'(?<![A-Za-z0-9])(?!123456789012(?![A-Za-z0-9]))\d{12}(?![A-Za-z0-9])', text):
    result.add('account-id')
  if re.search(r'discord(?:app)?\.com/api/webhooks/[A-Za-z0-9_-]+', text):
    result.add('webhook-url')
  # scp 形式の SSH clone URL はメールアドレスではない。
  email_text = re.sub(r'git@github\.com:', 'ssh-clone:', text)
  if re.search(r'\b(?!noreply@)[A-Za-z0-9._%+-]+@(?!example\.(?:com|org|net)\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}', email_text):
    result.add('email')
  examples = [ipaddress.ip_network(n) for n in ('192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24')]
  private = [ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
  for match in re.finditer(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])', text):
    try:
      address = ipaddress.ip_address(match.group())
    except ValueError:
      continue
    if address.is_global and not any(address in network for network in examples + private):
      result.add('ipv4')
  return result


def identifier_check():
  run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/ci', '-v'])
  run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/cd', '-v'])
  names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
  bad = False
  for name in filter(None, names):
    path = ROOT / name
    if not path.is_file():
      continue
    data = path.read_bytes()
    if b'\0' in data:
      continue
    kinds = findings(data.decode('utf-8', errors='replace'))
    if kinds:
      # パスや検出値も識別子を含み得るためログには出さない。
      print('Identifier check failed: ' + ', '.join(sorted(kinds)))
      bad = True
  if bad:
    raise ValueError('Tracked files contain identifiers; inspect locally')


def main(check):
  if check in ('fmt', 'validate', 'terraform-test', 'tflint'):
    paths = modules()
    if check == 'fmt':
      image('terraform', ['fmt', '-check', '-recursive'])
    for directory in paths:
      if check in ('validate', 'terraform-test'):
        if not (directory / '.terraform.lock.hcl').is_file():
          raise ValueError('Every Terraform root/module needs a committed lockfile')
        image('terraform', ['init', '-backend=false', '-input=false', '-lockfile=readonly'], directory)
        if check == 'terraform-test':
          tests = list((directory / 'tests').glob('*.tftest.hcl'))
          if not tests or any(
            len(re.findall(r'\brun\s+"[^"]+"\s*\{', p.read_text())) == 0
            or len(re.findall(r'\brun\s+"[^"]+"\s*\{', p.read_text()))
            != len(re.findall(r'\bcommand\s*=\s*plan\b', p.read_text()))
            or re.search(r'\bcommand\s*=\s*apply\b', p.read_text())
            for p in tests
          ):
            raise ValueError('Plan-only Terraform tests are required')
          # AWS 資格情報を渡さず、実 AWS への通信も禁止する。
          image('terraform', ['test', '-no-color'], directory, offline=True)
        else:
          image('terraform', ['validate', '-no-color'], directory)
      elif check == 'tflint':
        image('tflint', ['--init', '--config=/workspace/.tflint.hcl'], directory)
        image('tflint', ['--config=/workspace/.tflint.hcl'], directory)
  elif check == 'checkov':
    modules()
    for directory in [ROOT / 'bootstrap', ROOT / 'envs', ROOT / 'modules', ROOT / '.github']:
      # 非公開の変数はダミー値で補い、静的評価できない値による誤検知を避ける。
      dummy = ROOT / 'tests/checkov' / f'{directory.name}.tfvars.json'
      var_file = ['--var-file', str(dummy.relative_to(ROOT))] if dummy.is_file() else []
      image('checkov', ['-d', str(directory.relative_to(ROOT)), '--framework', 'terraform', 'github_actions',
                        '--compact', *var_file])
  elif check == 'pytest':
    if not list((ROOT / 'lambda').glob('*/tests/test_*.py')):
      raise ValueError('Lambda tests are required')
    image('python', ['sh', '-ec', 'pip install --no-cache-dir -r requirements-test.txt && python -m pytest lambda/'])
  elif check == 'shellcheck':
    files = sorted((ROOT / 'modules/minecraft_server/files/bin').glob('*.sh'))
    if not files:
      raise ValueError('Server scripts are required')
    image('shellcheck', ['-S', 'style', *[str(p.relative_to(ROOT)) for p in files]])
  elif check == 'bats':
    files = sorted((ROOT / 'tests').rglob('*.bats'))
    if not files:
      raise ValueError('Bats tests are required')
    # ホスト（AL2023）と同じく GNU tar・zstd・jq・openssl を使って検証する（外部 API はスタブ）。
    image('bats', ['-ec', 'apk add --no-cache --quiet jq openssl zstd tar coreutils util-linux >/dev/null && bats "$@"',
                   'bats', *[str(p.relative_to(ROOT)) for p in files]], entrypoint='bash')
  elif check == 'gitleaks':
    image('gitleaks', ['git', '--redact', '--no-banner', '--log-opts=--all', '.'])
  elif check == 'identifier-check':
    identifier_check()
  else:
    raise ValueError('Unknown check')


if __name__ == '__main__':
  try:
    main(sys.argv[1])
  except (ValueError, OSError, subprocess.CalledProcessError, IndexError) as error:
    print(f'CI check failed ({type(error).__name__}). See the preceding check result.', file=sys.stderr)
    sys.exit(1)
