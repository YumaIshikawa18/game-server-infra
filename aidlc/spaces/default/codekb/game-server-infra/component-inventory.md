# Component Inventory

## bootstrap

- **パス**: `bootstrap/`
- **責務**: state バケット、ログバケット、GitHub OIDC、CI ロール（plan、apply、ops）、app ロール用 permissions boundary を作ります。
- **依存**: AWS。入力は `scripts/local/prepare.py` が生成します。
- **テスト**: `bootstrap/tests/security.tftest.hcl`（12 run）

## envs-prod

- **パス**: `envs/prod/`
- **責務**: 6 モジュールを組み立てる本番のルートモジュールです。ゲーム設定は `minecraft.json` にあります。
- **依存**: `network`、`world_backup`、`notifier`、`minecraft_server`、`watchdog`、`monitoring`、`docker/compose.yml`、`lambda/*`
- **テスト**: `envs/prod/tests/prod.tftest.hcl`（3 run）

## network

- **パス**: `modules/network/`
- **責務**: 専用 /24 VPC、公開サブネット、IGW、25565/TCP だけを許可する SG、S3 へのフローログを作ります。
- **依存**: ログバケット
- **テスト**: `modules/network/tests/network.tftest.hcl`（4 run）

## minecraft_server

- **パス**: `modules/minecraft_server/`
- **責務**: EC2、ワールド EBS、EIP、ENI、ホスト用 IAM、SSM 文書、ログループ、S3 の配布ファイルを作ります。`minecraft.env` などを生成します。
- **依存**: `network`、`world_backup`、`notifier`、boundary、`docker/compose.yml`
- **テスト**: `modules/minecraft_server/tests/minecraft_server.tftest.hcl`（10 run）

## host-scripts

- **パス**: `modules/minecraft_server/files/bin/`、`modules/minecraft_server/files/systemd/`
- **責務**: ホスト上の起動順序、秘匿値の準備、MOD の同期、ヘルスチェック、バックアップ、停止、復元を担います。

| スクリプト | 責務 | bats |
|---|---|---|
| `common.sh` | ログ、通知、メトリクス、RCON、タグ、マウント確認 | 間接的にあり |
| `backup-lib.sh` | 圧縮、送信、照合、世代整理 | `backup.bats` |
| `backup-hourly.sh` | 毎時バックアップ | `backup.bats` |
| `stop.sh` | 停止処理 | `backup.bats` |
| `health.sh` | 1 分ごとの判定と自動停止 | `health.bats` |
| `health-check.sh` | SSM 文書用の ping | なし |
| `mod-sync.sh` | MOD の取得、照合、配置 | `mod-sync.bats` |
| `restore-apply.sh` | 復元の適用 | `restore.bats` |
| `boot-mode.sh` | 通常と復元の判定 | なし |
| `prepare-env.sh` | whitelist の取得と検査、`secrets.env` の生成 | なし |

- **依存**: AWS CLI、docker、jq、zstd、curl、flock、`/etc/minecraft/host.env`
- **テスト**: `tests/host/`（46 件）

## world_backup

- **パス**: `modules/world_backup/`
- **責務**: バックアップ（`hourly/`、`stop/`）と配布ファイル（`deploy/`）のバケットを作ります。世代の削除はホスト側が行います。
- **依存**: ログバケット
- **テスト**: `modules/world_backup/tests/world_backup.tftest.hcl`（3 run）

## notifier

- **パス**: `modules/notifier/`、`lambda/notifier/`
- **責務**: SNS の `events` と `alerts`、メール購読、Discord へ送る Lambda を提供します。
- **依存**: SSM の Webhook パラメータ、Discord
- **テスト**: `modules/notifier/tests/notifier.tftest.hcl`（3 run）、`lambda/notifier/tests/test_notifier.py`

## watchdog

- **パス**: `modules/watchdog/`、`lambda/watchdog/`
- **責務**: 5 分ごとに、無応答 60 分、ステータス異常 15 分、起動 12 時間のいずれかで強制停止します。`mc:stopping` のあるインスタンスには触りません。
- **依存**: EventBridge Scheduler、CloudWatch、EC2、`events` トピック
- **テスト**: `modules/watchdog/tests/watchdog.tftest.hcl`（3 run）、`lambda/watchdog/tests/test_watchdog.py`

## monitoring

- **パス**: `modules/monitoring/`
- **責務**: バックアップ失敗、ディスク使用率、バケット容量、Lambda エラーのアラームと、月次予算を作ります。
- **依存**: `alerts` トピック
- **テスト**: `modules/monitoring/tests/monitoring.tftest.hcl`（4 run）

## minecraft-container

- **パス**: `docker/compose.yml`
- **責務**: digest 固定の `itzg/minecraft-server` を、25565 公開、`/srv/minecraft/data:/data`、awslogs 出力で動かします。`minecraft.env` と `secrets.env` を読みます。
- **依存**: `host-scripts`、`minecraft_server`
- **テスト**: `minecraft_server` の `reject_unpinned_image`（digest 固定の検査のみ）

## ci-tooling

- **パス**: `scripts/ci/`、`.github/workflows/pr.yml`
- **責務**: AWS 認証なしのチェック、plan の安全な要約、手順書の生成と検査、識別子の検査を行います。
- **依存**: Docker、`.tool-versions`、GitHub API
- **テスト**: `tests/ci/test_ci.py`

## cd-tooling

- **パス**: `scripts/cd/`、`.github/workflows/deploy.yml`、`.github/workflows/start.yml`、`.github/workflows/stop.yml`、`.github/workflows/restore.yml`
- **責務**: 承認付きデプロイ、plan の digest 照合、運用ロック、起動、停止、復元を行います。
- **依存**: `scripts/ci/plan.py`、AWS CLI、SSM 文書
- **テスト**: `tests/cd/test_cd.py`

## local-tooling

- **パス**: `scripts/local/`
- **責務**: 非公開入力の生成、bootstrap の plan と apply、本番 plan の確認、GitHub の Secrets と Variables の登録を行います。値を表示しません。
- **依存**: `personal` プロファイル、`gh`、Docker
- **テスト**: なし

## client-guide

- **パス**: `docs/client-setup.md`、`scripts/ci/client_guide.py`
- **責務**: `minecraft.json` から参加者向けの手順書を生成します。
- **依存**: `envs/prod/minecraft.json`
- **テスト**: `tests/ci/test_ci.py` の `ClientGuide`
