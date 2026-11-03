# Unit Test Instructions

## フレームワークと設定

既存のものを使います。新しい依存はありません。

| 対象 | ツール | 版 | 実行環境 |
|---|---|---|---|
| ホストのスクリプト | `bats` | 1.14.0（`.tool-versions`） | Docker。コンテナの root で実行します |
| Terraform モジュール | `terraform test`（plan のみ） | 1.17.1（`.tool-versions`） | Docker。ネットワーク遮断、AWS 認証なし |

## この作業のテストの実行

`bats`（追加するファイルだけ）:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace --entrypoint bash bats/bats:1.14.0 -ec 'apk add --no-cache --quiet jq openssl zstd tar coreutils util-linux >/dev/null && bats tests/host/prepare_env.bats'
```

`terraform test`（`minecraft_server` モジュールだけ）:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace/modules/minecraft_server hashicorp/terraform:1.17.1 init -backend=false -input=false -lockfile=readonly
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/modules/minecraft_server hashicorp/terraform:1.17.1 test -no-color
```

## 追加するテスト（`tests/host/prepare_env.bats`）

| # | 場合 | 確認すること | 要件 |
|---|---|---|---|
| 1 | 一覧が 1 名 | `secrets.env` に `OPS=` の名前、`ops.json` に名前とレベル 3 | FR1.1、FR1.3 |
| 2 | 一覧に空白がある | 空白を除いて処理する | FR1.2 |
| 3 | 一覧が 2 名 | `ops.json` に 2 項目 | FR1.2 |
| 4 | 古い名前が `ops.json` にある（回帰） | 一覧にない名前が消える | FR2.1、FR4.2 |
| 5 | パラメータが未登録 | 起動は成功し、`OPS=` が空で書かれ、`ops.json` が `[]`、通知なし、`ops=0` | FR2.2、FR3.1 |
| 6 | 読み取りが権限エラー | 失敗し、`start_failed`、`secrets.env` と `ops.json` は変わらない | FR3.2 |
| 7 | 一覧の形式が不正（`name;x`） | 失敗し、`start_failed`、文面とログに値がない | FR3.3、FR3.5 |
| 8 | 名前がホワイトリストにない | 失敗し、原因が分かる文面、文面とログに名前がない、ファイルは変わらない | FR3.4、FR3.5 |
| 9 | ホワイトリストと大文字小文字だけ異なる | 成功する | FR3.4 |
| 10 | `ops.json` の一時ファイルを書けない | 失敗し、`start_failed`、`secrets.env` は変わらない | NFR2 |
| 11 | ホワイトリストを読めない（既存の動作） | 失敗し、`start_failed` | FR6.1 |
| 12 | ホワイトリストの形式が不正（既存の動作） | 失敗し、`start_failed` | FR6.1 |
| 13 | 正常時のファイルの権限 | `secrets.env` が 0600、`ops.json` の所有者が UID 1000 | NFR2 |
| 14 | 正常時のログ | `players=` と `ops=` の人数があり、名前がない | NFR1、NFR5 |

## 追加するテスト（`minecraft_server.tftest.hcl`）

`secure_host` に 1 件の assert、または同じ形の run を追加します。

- `minecraft.env` に `EXISTING_OPS_FILE=SYNCHRONIZE` と `OP_PERMISSION_LEVEL=3` があること
- `minecraft.env` に `OPS=` の行がないこと
- `bin/prepare-env.sh` が配布対象であること

## カバレッジの目標

team.md の基準に従います。行カバレッジは測定せず、全モジュールに plan モードのテストがあること、必須チェックがすべて通ることを基準とします。全体の確認は Build and Test で行います。`prepare-env.sh` については、上の一覧のすべての場合を通すことを目標とします。

## スタブ

- 既存の `tests/host/helpers.bash` の `setup_host` と `aws` スタブを使います。
- SSM スタブはパラメータ名で分岐します。`STUB_WHITELIST`、`STUB_OPS` が値を返し、`STUB_OPS_ERROR` でエラーの種類（`ParameterNotFound`、権限エラー）を、`STUB_WHITELIST_FAIL` でホワイトリストの読み取り失敗を再現します。
- 通知は `aws sns publish` の呼び出しを `$CALLS` で確認します。

## テストデータ

- プレイヤー名は `player_one` などの架空の名前だけを使います。
- ファイルは `setup_host` の一時ディレクトリに置き、`SECRETS_ENV` で出力先を差し替えます。

## 実行しないもの

- 実機での確認（`ops.json` の同期、レベル、ゲーム内のコマンド、コンテナの再作成）は Deployment Execution で行います。
