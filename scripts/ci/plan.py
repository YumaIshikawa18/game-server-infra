"""plan の生データを出力せず、許可した項目だけを公開する。"""

import collections
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
MARKER = '<!-- terraform-plan-summary -->'


def required(name):
    value = os.environ.get(name, '')
    if not value:
        raise ValueError('Required CI setting is missing')
    return value


def inputs():
    value = json.loads(required('TF_INPUTS_JSON'))
    if not isinstance(value, dict) or not value:
        raise ValueError('Terraform inputs must be a nonempty object')
    if any(not re.fullmatch(r'[a-z][a-z0-9_]*', key) for key in value):
        raise ValueError('Invalid Terraform variable name')
    return value


def strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, (str, int, float)) and not isinstance(value, bool):
        yield str(value)


def mask():
    values = list(strings(inputs()))
    values += [required(key) for key in ('AWS_PLAN_ROLE_ARN', 'TF_STATE_BUCKET', 'TF_STATE_KEY')]
    values += re.findall(r'(?<!\d)\d{12}(?!\d)', required('AWS_PLAN_ROLE_ARN'))
    for value in values:
        if value:
            escaped = value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
            print('::add-mask::' + escaped)


def summarize(plan, secret_values=()):
    if not isinstance(plan, dict) or not re.fullmatch(r'1\.\d+', str(plan.get('format_version', ''))):
        raise ValueError('Unsupported or malformed plan JSON')
    if plan.get('errored') is True or plan.get('complete') is False or plan.get('deferred_changes'):
        raise ValueError('Incomplete plan cannot pass')
    counts = collections.Counter()
    lines = []
    for change in plan.get('resource_changes', []):
        if change.get('mode', 'managed') != 'managed':
            continue
        actions = change['change']['actions']
        if actions == ['no-op']:
            continue
        if not actions or any(action not in ('create', 'update', 'delete', 'read', 'forget') for action in actions):
            raise ValueError('Unknown Terraform action')
        for action in actions:
            counts[action] += 1
        address = change['address']
        # 文字列 index は秘匿値を含み得るので、公開するアドレスでは伏せる。
        address = re.sub(r'\["(?:[^"\\]|\\.)*"\]', '[redacted]', address)
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.\[\]-]*', address):
            raise ValueError('Unexpected resource address')
        for value in sorted(set(secret_values), key=len, reverse=True):
            if value and value in address:
                address = address.replace(value, 'redacted')
        if re.search(r'\d{12}|arn:|@', address):
            raise ValueError('Resource address contains an identifier')
        lines.append(f'- `{address}`: ' + ', '.join(actions))
    warning = '**削除または置き換えがあります。**\n\n' if counts['delete'] or counts['forget'] else ''
    return (MARKER + '\n## Terraform plan\n\n' + warning
            + f'追加: {counts["create"]} / 変更: {counts["update"]} / 削除: {counts["delete"]}\n\n'
            + '\n'.join(lines) + '\n')


def terraform(args):
    # stdout / stderr に state、ARN、診断内の値が含まれ得るため返却も表示もしない。
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('GH_TOKEN', 'TF_INPUTS_JSON', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN')}
    for key, value in inputs().items():
        environment['TF_VAR_' + key] = value if isinstance(value, str) else json.dumps(value)
    result = subprocess.run(['terraform', '-chdir=envs/prod', *args], cwd=ROOT, env=environment,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise RuntimeError('Terraform command failed; inspect locally without publishing raw output')
    return result.stdout


def api(method, path, body=None):
    base = required('GITHUB_API_URL')
    # github.com の public リポジトリを対象とする。
    if base != 'https://api.github.com':
        raise ValueError('Unexpected API endpoint')
    request = urllib.request.Request(base + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={'Authorization': 'Bearer ' + required('GH_TOKEN'),
                                              'Accept': 'application/vnd.github+json',
                                              'Content-Type': 'application/json',
                                              'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def comment(summary):
    event = json.loads(pathlib.Path(required('GITHUB_EVENT_PATH')).read_text())
    number = event['pull_request']['number']
    repo = required('GITHUB_REPOSITORY')
    if not isinstance(number, int) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid PR context')
    base = f'/repos/{repo}'
    page = 1
    while True:
        comments = api('GET', f'{base}/issues/{number}/comments?per_page=100&page={page}')
        for item in comments:
            if item['user']['login'] == 'github-actions[bot]' and item['body'].startswith(MARKER):
                api('PATCH', f'{base}/issues/comments/{item["id"]}', {'body': summary})
                return
        if len(comments) < 100:
            break
        page += 1
    api('POST', f'{base}/issues/{number}/comments', {'body': summary})


def main():
    if sys.argv[1] == 'mask':
        mask()
        return
    if sys.argv[1] != 'run':
        raise ValueError('Unknown operation')
    values = inputs()
    directory = ROOT / 'envs/prod'
    if not list(directory.glob('*.tf')) or not (directory / '.terraform.lock.hcl').is_file():
        raise ValueError('Production Terraform and lockfile are required')
    os.umask(0o077)
    private = ROOT / '.ci-private'
    private.mkdir(exist_ok=True)
    work = pathlib.Path(tempfile.mkdtemp(dir=private))
    try:
        # partial backend config の値はプロセス引数にも置かない。
        backend = work / 'backend.hcl'
        backend.write_text('\n'.join(f'{key} = {json.dumps(value)}' for key, value in {
            'bucket': required('TF_STATE_BUCKET'), 'key': required('TF_STATE_KEY'),
            'region': required('AWS_REGION'), 'encrypt': True, 'use_lockfile': True,
        }.items()))
        terraform(['init', '-input=false', '-lockfile=readonly', f'-backend-config={backend}'])
        plan = work / 'plan.bin'
        terraform(['plan', '-input=false', '-no-color', '-lock-timeout=5m',
                   f'-out={plan}'])
        summary = summarize(json.loads(terraform(['show', '-json', str(plan)])),
                            [*strings(values), required('TF_STATE_BUCKET'), required('TF_STATE_KEY')])
        with open(required('GITHUB_STEP_SUMMARY'), 'a', encoding='utf-8') as target:
            target.write(summary)
        comment(summary)
    finally:
        shutil.rmtree(work)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # 外部 API の例外本文にも識別子が含まれる可能性がある。
        print('::error::Plan or summary publication failed. No raw Terraform output was published.')
        sys.exit(1)
