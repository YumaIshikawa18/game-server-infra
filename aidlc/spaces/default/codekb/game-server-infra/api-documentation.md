# API Documentation

HTTP API はありません。以下がこのリポジトリの外部および内部の契約です。

## 外部公開

| 種類 | 内容 | 認証・制限 |
|---|---|---|
| Minecraft Java | 25565/TCP、`0.0.0.0/0` から | online-mode と whitelist（`modules/network/main.tf:61-68`、`deploy.tf:13-16`） |

RCON はコンテナ内の localhost でだけ使い、ポートを公開していません（`docker/compose.yml:13-14`）。

## SSM Parameter Store（本人が登録）

Terraform は値を管理せず、名前だけを出力します。

| パラメータ | 型 | 形式 | 読み手 | 名前の出力 |
|---|---|---|---|---|
| `/<prefix>/minecraft/whitelist` | SecureString | `^[A-Za-z0-9_]{3,16}(,[A-Za-z0-9_]{3,16})*$`（空白は除去） | `prepare-env.sh`（ホスト用ロール） | `whitelist_parameter`（sensitive） |
| `/<prefix>/minecraft/discord-webhook` | SecureString | Webhook URL | notifier Lambda | `discord_webhook_parameter`（sensitive） |

権限の範囲:

- ホスト用ロールは `ssm:GetParameter` だけで、対象は `parameter/<prefix>/minecraft/*` です。`ssm:GetParameters` はホストのポリシーにないため、複数をまとめて取得すると拒否されると読めます（`modules/minecraft_server/iam.tf:41`）。
- `kms:Decrypt` は `kms:ViaService` と `kms:EncryptionContext:PARAMETER_ARN` で絞っています（`iam.tf:42-45`）。
- boundary は `parameter/<prefix>/*` を許可します（`bootstrap/iam.tf:87-88`）。
- CI の apply ロールと plan ロールに `ssm:PutParameter` はありません。パラメータの登録は本人の権限で行います。

## SSM Run Command 文書

定義は `modules/minecraft_server/ssm.tf` です。引数は `allowedPattern` または `allowedValues` で検査してからシェルに渡します。

| 文書 | 引数 | 上限 | 実行 | 呼び出し元 |
|---|---|---|---|---|
| `mc-stop` | `reason`（`manual`、`idle`、`unresponsive`、`replace`、`start-failed`）、`requireBackup`（`true` / `false`、既定 `false`） | 900 秒 | `stop.sh` | Stop、Start の失敗時、Deploy の置き換え時 |
| `mc-health-check` | なし | 60 秒 | `health-check.sh` | Start、Deploy のスモークテスト |
| `mc-restore-apply` | `key`（`^(stop|hourly)/[0-9]{8}-[0-9]{6}\.tar\.zst$`） | 1800 秒 | `restore-apply.sh` | Restore |

`scripts/cd/common.py:107-114` が送信できる文書を上の 3 件に限定しています。

## SNS メッセージ

`events` トピックへの発行は 4 つのロール（`app-server`、`app-watchdog`、`ci-ops`、`ci-apply`）に限ります（`modules/notifier/main.tf:11-12`）。

独自 JSON の形:

```json
{"source": "host|workflow|watchdog", "event": "...", "severity": "info|warn|error", "message": "...", "session_id": "host のみ"}
```

メッセージ属性 `event` と `severity` を付けます。メール購読のフィルターは `severity` を使います。

| 発行元 | 主なイベント |
|---|---|
| ホスト | `start_failed`、`mod_sync_failed`、`boot_restore_mode`、`backup_failed`、`server_stopping`、`stop_refused`、`stop_failed`、`restore_failed`、`restore_applied` |
| workflow | `deployment-failed`、`start-failed`、`stop-failed`、`restore-failed`、`backup-unavailable` |
| watchdog | `watchdog_stop` |

notifier は独自 JSON、CloudWatch アラーム、AWS Budgets のテキストを判別します。判別できないものは warn として送ります。ARN、12 桁の数字、IPv4、インスタンス ID が文面にあれば、送信せず失敗にします（`lambda/notifier/notifier.py:24-29,69-73`）。

## カスタムメトリクス

名前空間は `Minecraft` で、サーバーを区別するディメンションはありません。

| メトリクス | 発行元 |
|---|---|
| `ServerUp`、`PlayersOnline` | `health.sh` |
| `BackupFailures`、`BackupSizeBytes`、`BackupDurationSeconds`、`BackupBucketBytes` | `backup-lib.sh`、`backup-hourly.sh`、`stop.sh` |
| `disk_used_percent` | CloudWatch Agent |

## コンテナへの環境変数

| 変数 | 由来 |
|---|---|
| `EULA`、`TYPE`、`VERSION`、`MEMORY`、`USE_AIKAR_FLAGS`、`ONLINE_MODE`、`ENABLE_WHITELIST`、`ENFORCE_WHITELIST`、`EXISTING_WHITELIST_FILE`、`ENABLE_RCON`、`MAX_PLAYERS`、`VIEW_DISTANCE`、`SIMULATION_DISTANCE`、`DIFFICULTY`、`MOTD`、`TZ`、ローダーの版 | `/opt/minecraft/minecraft.env`（`deploy.tf` が生成、Git 由来で秘匿値なし） |
| `WHITELIST`、`RCON_PASSWORD` | `/etc/minecraft/secrets.env`（`prepare-env.sh` が生成、0600） |

`OPS`、`EXISTING_OPS_FILE`、`OP_PERMISSION_LEVEL` は現在どちらにも設定されていません。

`itzg/minecraft-server` の公式ドキュメントでは次のように説明されています。

- `OPS` はユーザー名または UUID の、カンマまたは改行区切りの一覧です。
- `EXISTING_OPS_FILE` の値は `SKIP`、`SYNCHRONIZE`、`MERGE`、`SYNC_FILE_MERGE_LIST` で、既定は `SYNC_FILE_MERGE_LIST` です。
- `SYNCHRONIZE` はファイルの一覧を `OPS` に合わせ、既存の項目の `level` と `bypassesPlayerLimit` を保持します。
- `SYNC_FILE_MERGE_LIST` では `OPS` の利用者が追加マージされます。
- ユーザー名は既定で PlayerDB、`USER_API_PROVIDER` で Mojang を使って解決します。
- `OPS` が未設定または空のときの挙動と、名前を解決できないときに起動が止まるかどうかは記載がありません（要確認）。

実機での挙動は未確認です。

## GitHub Actions

| Workflow | 起動 | 環境 | 実行者の制限 |
|---|---|---|---|
| PR | `pull_request`（master 宛） | なし | plan は同一リポジトリかつ Dependabot 以外 |
| Deploy | `push`（master）、手動 | `prod`（apply） | 承認者 |
| Start、Stop | 手動 | `ops` | `master` かつ `OPERATOR_LOGIN` |
| Restore | 手動（入力 `backup_key`） | `ops` | `master` かつ `OPERATOR_LOGIN` |

必須チェックは `fmt`、`validate`、`tflint`、`checkov`、`terraform-test`、`pytest`、`shellcheck`、`bats`、`identifier-check`、`gitleaks`、`plan` の 11 件です。

## Terraform の入出力

- `envs/prod` の入力: `allowed_account_ids`、`prefix`、`region`、`availability_zone`、`backup_bucket_name`、`log_bucket_name`、`notification_email`、`monthly_budget_usd`、`accept_minecraft_eula`。CI では `TF_INPUTS_JSON` から渡します。
- `envs/prod` の出力: `instance_id`、`server_address`、`whitelist_parameter`、`discord_webhook_parameter`。すべて sensitive です。

## CLI

| コマンド | 用途 |
|---|---|
| `python3 scripts/ci/check.py <check>` | 必須チェックを Docker で実行（`plan` を除く） |
| `python3 scripts/ci/client_guide.py [--check]` | 手順書の生成と検査 |
| `python3 -m scripts.local.prepare` | 非公開の入力を準備 |
| `python3 -m scripts.local.terraform plan\|apply\|prod-plan` | bootstrap の適用、本番の plan 確認 |
| `python3 -m scripts.local.github_setup` | GitHub の Secrets と Variables を登録 |
| `python3 -m scripts.cd.deploy mask\|prepare\|apply\|notify-failure` | Deploy workflow から実行 |
| `python3 -m scripts.cd.operations mask\|start\|stop\|restore` | 運用 workflow から実行 |
