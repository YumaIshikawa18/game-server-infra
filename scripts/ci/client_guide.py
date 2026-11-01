"""envs/prod/minecraft.json からクライアント向けの手順書を生成・検査する。

使い方:
  python3 scripts/ci/client_guide.py          手順書を更新する
  python3 scripts/ci/client_guide.py --check  手順書が設定と食い違っていれば失敗する
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = ROOT / 'envs/prod/minecraft.json'
GUIDE = ROOT / 'docs/client-setup.md'
LOADERS = {'forge': 'Forge', 'neoforge': 'NeoForge', 'fabric': 'Fabric'}


def client_mods(settings):
  """クライアントに必要な MOD を名前順で返す。サーバー専用（side=server）は除く。"""
  return sorted((mod for mod in settings['mods'] if mod['side'] != 'server'), key=lambda mod: mod['name'])


def render(settings):
  lines = [
    '# クライアントの準備',
    '',
    '<!-- envs/prod/minecraft.json から生成しています。直接編集せず、`python3 scripts/ci/client_guide.py` を実行してください。 -->',
    '',
    'このサーバーに接続するために必要な準備です。',
    '',
    '## 必要なもの',
    '',
    '- Minecraft: Java Edition のアカウント',
    '- ホワイトリストへの登録（管理者に Minecraft のユーザー名を伝えてください）',
    '- サーバーのアドレス（管理者から受け取ってください。公開の場所には書かないでください）',
    '',
    '## バージョン',
    '',
    '| 項目 | 値 |',
    '|---|---|',
    f'| Minecraft | `{settings["version"]}` |',
  ]
  loader = settings['loader']
  if loader == 'vanilla':
    lines += ['| MOD ローダー | なし（バニラ） |']
  else:
    lines += [f'| MOD ローダー | {LOADERS[loader]} `{settings["loader_version"]}` |']
  lines += ['', '## 手順', '']
  mods = client_mods(settings)
  steps = [f'Minecraft Launcher で、バージョン `{settings["version"]}` の起動構成を作ります。']
  if loader != 'vanilla':
    steps.append(f'{LOADERS[loader]} `{settings["loader_version"]}` をインストールし、その起動構成を選びます。')
  if mods:
    steps.append('下の表の MOD をすべてダウンロードし、Minecraft の `mods` フォルダーに入れます。')
  steps += [
    'Minecraft を起動し、「マルチプレイ」でサーバーのアドレスを追加して接続します。',
    'サーバーが停止中のときは接続できません。管理者に起動を依頼してください。',
  ]
  lines += [f'{number}. {step}' for number, step in enumerate(steps, 1)]
  lines += ['', '## クライアントに必要な MOD', '']
  if mods:
    lines += ['| MOD | バージョン | ダウンロード | SHA-256 |', '|---|---|---|---|']
    lines += [f'| {mod["name"]} | `{mod["version"]}` | [取得]({mod["url"]}) | `{mod["sha256"]}` |' for mod in mods]
    lines += ['', 'ファイルの SHA-256 が表の値と一致しないときは、使わずに管理者へ連絡してください。']
  else:
    lines += ['ありません。']
  return '\n'.join(lines) + '\n'


def main(arguments):
  expected = render(json.loads(SETTINGS.read_text(encoding='utf-8')))
  if arguments == ['--check']:
    if not GUIDE.is_file() or GUIDE.read_text(encoding='utf-8') != expected:
      print('docs/client-setup.md is out of date. Run: python3 scripts/ci/client_guide.py', file=sys.stderr)
      return 1
    return 0
  if arguments:
    print('Use no arguments or --check', file=sys.stderr)
    return 2
  GUIDE.parent.mkdir(parents=True, exist_ok=True)
  GUIDE.write_text(expected, encoding='utf-8')
  return 0


if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
