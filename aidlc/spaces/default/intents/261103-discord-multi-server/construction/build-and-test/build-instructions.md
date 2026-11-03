# Build Instructions

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-generation-plan.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/unit-test-instructions.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-summary.md`

この作業にコンパイルや成果物のビルドはありません。Terraform の検証と、配布するシェルスクリプトの検査が、ビルドの確認にあたります。

## 前提

| 項目 | 内容 |
|---|---|
| 実行環境 | Docker と Python 3。ツールの版は `.tool-versions` に固定されています |
| AWS の認証 | 下記のコマンドには不要です。渡しません |
| 環境変数と設定ファイル | 不要です。`terraform plan` と適用に必要な値は、CI の Secrets または gitignore 済みのファイルから渡します |
| 依存の導入 | 各コンテナの中で行います。手元への導入はありません |

## ビルドの確認

```bash
python3 scripts/ci/check.py fmt
python3 scripts/ci/check.py validate
python3 scripts/ci/check.py tflint
python3 scripts/ci/check.py shellcheck
```

## うまくいかないとき

| 症状 | 原因と対応 |
|---|---|
| `check.py validate` または `terraform-test` が AWS 認証のエラーで失敗する | 手元の `envs/prod/.terraform/terraform.tfstate` に残る S3 backend の情報が原因と思われます。`.terraform` のないコピーでは同じコマンドが成功しました。CI はクリーンな checkout で実行します。手元で通すには `TF_DATA_DIR` を別の場所に向けます |
| `.terraform` の中のファイルを消せない | コンテナの root が作ったファイルです。所有者を確認してください |
| `check.py bats` 以外で `bats` を直接実行すると `chown` が失敗する | コンテナの root で実行する前提です。`unit-test-instructions.md` のコマンドを使います |
| 新しいファイルの識別子を `identifier-check` が検出しない | 追跡済みのファイルだけを検査します。コミットの前は検出されません |
