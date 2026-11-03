# Code Structure

## ディレクトリ構成

```text
.github/workflows/          PR、Deploy、Start、Stop、Restore
bootstrap/                  state、ログ、CI 用 IAM。手元から適用
envs/prod/                  本番のルートモジュール、minecraft.json
modules/
  network/                  VPC、サブネット、SG、フローログ
  minecraft_server/         EC2、EBS、EIP、IAM、SSM 文書、配布
    deploy.tf               minecraft.env などの配布ファイルを生成
    iam.tf                  ホスト用ロール
    ssm.tf                  Run Command 文書
    user_data.sh.tftpl      初回起動の処理
    files/bin/              ホストのスクリプト
    files/systemd/          ユニットとタイマー
  world_backup/             バックアップ兼配布バケット
  notifier/                 SNS、メール、notifier Lambda
  watchdog/                 watchdog Lambda、Scheduler
  monitoring/               アラーム、予算
lambda/notifier/            Discord 通知
lambda/watchdog/            外部強制停止
docker/compose.yml          コンテナ定義
scripts/ci/                 CI チェック、plan 要約、手順書生成
scripts/cd/                 デプロイ、運用操作
scripts/local/              手元の準備、bootstrap の実行
tests/host/                 ホストスクリプトの bats
tests/ci/、tests/cd/        Python スクリプトの unittest
tests/checkov/              Checkov 用のダミー入力
docs/                       クライアント手順書、構成図
```

各 Terraform のモジュールは `main.tf`、`variables.tf`、`outputs.tf`（必要な場合）、`versions.tf`、`.terraform.lock.hcl`、`tests/*.tftest.hcl` の形で揃っています。

## ファイルの分類

| 分類 | ファイル |
|---|---|
| Configuration（IaC） | `bootstrap/*.tf`、`envs/prod/*.tf`、`modules/*/*.tf` |
| Configuration（ゲーム） | `envs/prod/minecraft.json`、`docker/compose.yml` |
| Configuration（ツール） | `.tool-versions`、`.tflint.hcl`、`.shellcheckrc`、`.editorconfig`、`.github/dependabot.yml` |
| Controller / Handler | `lambda/notifier/notifier.py`、`lambda/watchdog/watchdog.py`、`.github/workflows/*.yml`、`files/systemd/*` |
| Service / UseCase | `files/bin/{stop,backup-hourly,health,health-check,mod-sync,prepare-env,restore-apply,boot-mode}.sh`、`scripts/cd/{deploy,operations}.py`、`scripts/ci/{check,plan,client_guide}.py`、`scripts/local/{prepare,terraform,github_setup}.py` |
| Utility | `files/bin/common.sh`、`files/bin/backup-lib.sh`、`scripts/cd/common.py` |
| Test | `*/tests/*.tftest.hcl`、`lambda/*/tests/*.py`、`tests/host/*`、`tests/ci/*`、`tests/cd/*`、`tests/checkov/*` |
| Static / Asset | `docs/images/architecture.drawio.png`、`docs/client-setup.md`（生成物） |

## コードのパターン

### Bash（ホスト）

- すべて `set -euo pipefail` で始め、`MC_BIN` から `common.sh` を読みます。
- 最後の `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi` で、テストから関数単位で読み込めます。
- パスは環境変数で上書きでき（`MC_ROOT`、`SECRETS_ENV` など）、bats はこれとスタブで検証します。
- ログは `log <level> event=... key=value` の形です。
- 通知は `notify <event> <severity> <日本語の文面>` です。文面に識別子を入れません。
- 識別子は `/etc/minecraft/host.env` から読みます。
- 書き込みは一時ファイルと `mv` で行います（`prepare-env.sh:37-39`、`health.sh:22-26`）。

### Terraform

- 識別子を含む変数と出力は `sensitive = true` です。
- 入力は `validation` で検査し、テストは `expect_failures` で拒否を確認します。
- Checkov の skip には理由をコメントで残します。
- リソース名は `<prefix>-...` で、変数でパラメータ化します。

### Python

- インデントは 2 スペースです。
- 例外本文やコマンド出力を公開ログに出しません。固定のラベルだけを出します（`scripts/ci/plan.py:20-68`、`scripts/cd/deploy.py:25-42`）。
- 標準ライブラリだけで動きます。boto3 は関数内で遅延 import し、テストでは差し替えます。

## 今回の作業に関係するファイル

| ファイル | 現在の役割 |
|---|---|
| `modules/minecraft_server/files/bin/prepare-env.sh` | whitelist の取得、検査、`secrets.env` の生成 |
| `modules/minecraft_server/deploy.tf` | `minecraft.env` の生成。whitelist の同期方式を設定 |
| `docker/compose.yml` | `secrets.env` をコンテナへ渡す |
| `modules/minecraft_server/iam.tf` | `parameter/<prefix>/minecraft/*` の読み取りと復号 |
| `modules/minecraft_server/outputs.tf`、`envs/prod/outputs.tf` | パラメータ名の出力 |
| `modules/minecraft_server/tests/minecraft_server.tftest.hcl` | 設定と秘匿値の非混入の検査 |
| `envs/prod/tests/prod.tftest.hcl` | パラメータ接頭辞の検査 |
| `tests/host/helpers.bash` | SSM のスタブ。`prepare-env.sh` のテスト本体はありません |
| `README.md` | 手順 6 に SSM の登録手順 |

`modules/minecraft_server/user_data.sh.tftpl` と `scripts/local/prepare.py` は whitelist の値を扱っていません。`deploy.tf` の `static_files` は `files/**` を自動で配布対象にします。
