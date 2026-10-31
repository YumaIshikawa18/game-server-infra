"""personal の一時資格情報で Terraform を実行し、公開可能なサマリーだけを出す。"""

import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

from scripts.ci.plan import summarize, strings
from scripts.local.prepare import ROOT, command, private_json


def invoke(args, credentials):
  environment = dict(os.environ)
  environment.update({
    'AWS_ACCESS_KEY_ID': credentials['AccessKeyId'],
    'AWS_SECRET_ACCESS_KEY': credentials['SecretAccessKey'],
    'AWS_SESSION_TOKEN': credentials['SessionToken'],
    'AWS_REGION': 'ap-northeast-1',
  })
  result = subprocess.run([
    'docker', 'run', '--rm', '-e', 'AWS_ACCESS_KEY_ID', '-e', 'AWS_SECRET_ACCESS_KEY',
    '-e', 'AWS_SESSION_TOKEN', '-e', 'AWS_REGION', '-e', 'TF_IN_AUTOMATION=true',
    '-v', str(ROOT) + ':/workspace', '-w', '/workspace/bootstrap',
    'hashicorp/terraform:1.17.1', *args,
  ], cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
  if result.returncode:
    # 生の診断は値を含み得るため、gitignore 済みの非公開ファイルにだけ保存する。
    path = ROOT / '.ci-private/bootstrap-diagnostics.log'
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'wb') as target:
      target.write(result.stdout + result.stderr)
    raise RuntimeError('Terraform failed; private diagnostics are in .ci-private/bootstrap-diagnostics.log')
  return result.stdout


def sources():
  paths = [*sorted((ROOT / 'bootstrap').glob('*.tf')),
           *sorted((ROOT / 'bootstrap').glob('*.tfvars')),
           *sorted((ROOT / 'bootstrap').glob('*.tfvars.json')),
           ROOT / 'bootstrap/.terraform.lock.hcl']
  return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def validate_policies(plan):
  # AWS の基本的な ValidatePolicy はリソースを作成しない。本文・ARN は出力しない。
  documents = []
  for resource in plan.get('resource_changes', []):
    if resource['type'] not in ('aws_iam_policy', 'aws_iam_role_policy'):
      continue
    policy = (resource['change'].get('after') or {}).get('policy')
    if policy:
      documents.append((resource['address'], policy))
  failed = []
  warnings = []
  for address, policy in documents:
    reply = command(['aws', '--profile', 'personal', 'accessanalyzer', 'validate-policy',
                     '--policy-type', 'IDENTITY_POLICY', '--policy-document', policy,
                     '--output', 'json'])
    for finding in reply.get('findings', []):
      entry = {
        'address': address, 'type': finding['findingType'], 'code': finding['issueCode'],
        'actions': re.findall(r'\b[a-z0-9-]+:[A-Z][A-Za-z]+\b', finding.get('findingDetails', '')),
      }
      (failed if finding['findingType'] == 'ERROR' else warnings).append(entry)
  private_json(ROOT / '.ci-private/bootstrap-policy-validation.json', {'errors': failed, 'warnings': warnings})
  if failed:
    print(json.dumps({'policy_errors': failed}, ensure_ascii=False))
    raise ValueError('IAM validation errors must be corrected before apply')
  print(json.dumps({'validated_policy_documents': len(documents), 'policy_warning_count': len(warnings)}))


def main():
  operation = sys.argv[1] if len(sys.argv) == 2 else ''
  if operation not in ('plan', 'apply'):
    raise ValueError('Use plan or apply')
  os.umask(0o077)
  private = ROOT / '.ci-private'
  private.mkdir(exist_ok=True)
  values = json.loads((ROOT / 'bootstrap/generated.auto.tfvars.json').read_text())
  identity = command(['aws', '--profile', 'personal', 'sts', 'get-caller-identity', '--output', 'json'])
  allowed = re.findall(r'"(\d{12})"', (ROOT / 'bootstrap/local.auto.tfvars').read_text())
  if identity['Account'] not in allowed:
    raise ValueError('The active account is not allowed')
  credentials = command(['aws', 'configure', 'export-credentials', '--profile', 'personal', '--format', 'process'])
  path = private / 'bootstrap-plan.bin'
  metadata_path = private / 'bootstrap-plan-review.json'
  if operation == 'plan':
    invoke(['init', '-backend=false', '-input=false', '-lockfile=readonly'], credentials)
    invoke(['plan', '-input=false', '-no-color', '-out=/workspace/.ci-private/bootstrap-plan.bin'], credentials)
    plan = json.loads(invoke(['show', '-json', '/workspace/.ci-private/bootstrap-plan.bin'], credentials))
    validate_policies(plan)
    private_json(metadata_path, {
      'plan_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'sources': sources(),
      'account_sha256': hashlib.sha256(identity['Account'].encode()).hexdigest(),
    })
    print(summarize(plan, list(strings(values)) + allowed))
  else:
    metadata = json.loads(metadata_path.read_text())
    if (metadata['sources'] != sources()
        or metadata['plan_sha256'] != hashlib.sha256(path.read_bytes()).hexdigest()
        or metadata['account_sha256'] != hashlib.sha256(identity['Account'].encode()).hexdigest()):
      raise ValueError('Reviewed bootstrap plan or source changed; generate and review a new plan')
    invoke(['apply', '-input=false', '-no-color', '/workspace/.ci-private/bootstrap-plan.bin'], credentials)
    outputs = json.loads(invoke(['output', '-json'], credentials))
    private_json(private / 'bootstrap-outputs.json', outputs)
    path.unlink()
    metadata_path.unlink()
    print('bootstrap の適用が完了しました。識別子を含む出力は非公開ファイルに保存しました。')


if __name__ == '__main__':
  try:
    main()
  except Exception as error:
    print('bootstrap 処理が失敗しました（' + type(error).__name__ + '）。生の値は出力していません。', file=sys.stderr)
    if isinstance(error, RuntimeError):
      print(str(error), file=sys.stderr)
    sys.exit(1)
