# Infrastructure Specification

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/` の performance-design.md / security-design.md / scalability-design.md / reliability-design.md / observability-design.md / logical-components.md。

infra スコープのため、`components.md`（domain-design）と `functional-spec.md`（functional-design）はありません。構成要素は logical-components.md（LC1〜LC11）から導いています。

## Deployment

| Facet | Choice | Rationale |
|---|---|---|
| Compute model | EC2 1 台（オンデマンド、Graviton `m7g.xlarge` を既定、`instance_type` と `cpu_architecture` は変数）。AL2023 の上で Docker と `docker compose` を使い、itzg/minecraft-server を digest 固定で動かす | NFR2.4 / NFR2.5 / NFR9.3。tech-stack 判断 1。Dependabot で digest を追従するため compose を使う（[Q3]） |
| Networking topology | 専用 VPC（/24）、パブリックサブネット 1 つ（1 AZ）、IGW。NAT なし、IPv4 のみ。Elastic IP を ENI に関連付ける。SG の ingress は 25565/TCP（0.0.0.0/0）のみ、egress は全許可 | NFR Design [Q2]、NFR5.5、FR8.1 |
| Storage strategy | ルート EBS gp3 8 GB（暗号化）。ワールド用 EBS gp3 30 GB（暗号化、`prevent_destroy`、`/srv/minecraft`。Docker の data-root と MOD キャッシュも置く）。バックアップは S3（`hourly/` は 24 世代、`stop/` は 7 世代、旧版は 7 日で削除） | NFR4.3、NFR4.6、NFR5.9、performance-design のキャッシュ |
| Environments | `prod` の 1 つのみ | team-practices の Deployment |
| IaC approach | Terraform。`bootstrap/`（state バケット、OIDC プロバイダー、`${prefix}-ci-*` の 3 ロール、permissions boundary。手元で 1 回 apply）と `envs/prod/`（`modules/*` を組み合わせる。CI から apply）に分ける。backend は S3（`use_lockfile = true`、partial configuration） | team-practices、NFR5.2d、NFR5.11 |
| Resource sizing | 既定は `m7g.xlarge`（4 vCPU / 16 GB）、JVM ヒープは 12 G。ワールド EBS は 30 GB、gp3 のベースライン性能 | NFR2.4、NFR2.8 |
| Region | `ap-northeast-1`（東京） | NFR Requirements の [Q6] |
| Tagging | provider の `default_tags` で `Project`、`Environment=prod`、`ManagedBy=terraform` を付ける。対象インスタンスには `mc:managed=true` を付ける | コスト配分、IAM の条件 |

## Infrastructure Services

| Service | Role | Configuration | Notes |
|---|---|---|---|
| Amazon EC2 | ゲームホスト（LC4） | IMDSv2 必須（hop 2）、キーペアなし、インスタンスプロファイル `${prefix}-app-server`、user data（cloud-init）でホスト上のファイルを配置。AMI は SSM パラメータから取得し、`ignore_changes = [ami]` を付け、更新は変数で明示的に行う | AMI の更新による意図しない置き換えを防ぐ（置き換えは FR4.5 の保護付きで実施） |
| Elastic IP | 接続先 | `prevent_destroy`、`aws_eip_association` | 停止中も課金される |
| Amazon EBS | ワールド | gp3、暗号化、`aws_volume_attachment`（`/dev/sdf`）、`prevent_destroy` | 置き換え時もボリュームを残す |
| Amazon S3 | バックアップ（LC6） | BPA、SSE-S3、TLS 強制、バージョニング、ライフサイクル（noncurrent は 7 日、未完了のマルチパートは 7 日で削除）、`prevent_destroy` | バケット名は変数（Secrets） |
| Amazon S3 | Terraform state（LC1） | bootstrap で作成。BPA、SSE-S3、TLS 強制、バージョニング、`prevent_destroy` | バケット名は Secrets |
| AWS Systems Manager | Session Manager、Run Command、Parameter Store | Run Command は独自ドキュメント（`mc-stop`、`mc-health-check`、`mc-restore-apply`）を Terraform で作り、ci-ops にはこのドキュメントだけを許可する。SecureString は `aws/ssm` 鍵で暗号化し、手動で登録する | NFR5.2c、NFR6.3 |
| AWS Lambda | watchdog（LC8）、notifier（LC9） | Python 3.13、arm64、メモリ 128 MB、タイムアウト 30 秒。予約同時実行数 1。ロググループは 14 日保持 | NFR4.11、NFR7.15 |
| Amazon EventBridge Scheduler | watchdog の起動 | `rate(5 minutes)` | 無料枠の範囲で動く |
| Amazon SNS（`events` トピック） | スクリプトとワークフローが送るイベント（独自 JSON、メッセージ属性 `severity` / `event` 付き） | 購読は 2 つ。① notifier Lambda（全件）② メール（属性 `severity` が warn / error のものだけを通すフィルタ）。トピックポリシーで Publish を許可するのは `${prefix}-app-server`、`${prefix}-app-watchdog`、`${prefix}-ci-ops`、`${prefix}-ci-apply` だけ | NFR Design の D2 |
| Amazon SNS（`alerts` トピック） | CloudWatch アラームと Budgets の通知 | 購読は 2 つ。① notifier Lambda ② メール（フィルタなし。アラームと予算はすべて warn / error 扱い）。トピックポリシーで `cloudwatch.amazonaws.com` と `budgets.amazonaws.com` からの Publish を許可し、`aws:SourceAccount` 条件で自アカウントに限る | アラームと Budgets のメッセージには独自の属性が付かないため、トピックを分ける |
| SNS の暗号化 | 両トピックとも SSE なし | `alias/aws/sns` はキーポリシーを変更できず、CloudWatch と Budgets から暗号化トピックに Publish するにはカスタマーマネージドキー（月 $1 ≒ 150 円）が要る。本文に秘匿値や識別子を含めない設計（NFR6.5）であり、予算の余裕も小さいので、暗号化しない。Checkov の該当チェック（CKV_AWS_26）は理由付きで抑止する | 承認前の確認で本人が決定 |
| Amazon CloudWatch | メトリクス、アラーム、Logs | 名前空間 `Minecraft`。ロググループは 14 日保持 | monitoring-design.md |
| AWS Budgets | コスト監視 | 月 3,000 円相当（USD 換算は変数）。実績・予測の 80% と 100% で SNS に通知 | FR9.1 |
| AWS IAM | ロール 6 つ | security-design.md §2。boundary は `${prefix}-ci-boundary` | NFR5.2 |
| IAM OIDC provider | GitHub Actions | `token.actions.githubusercontent.com`、`aud` は `sts.amazonaws.com` | bootstrap |

## 月額コストの再計算（東京、月 40 時間稼働）

| 項目 | 上流の見積もり（scalability-requirements.md） | この設計での月額 |
|---|---|---|
| EC2 / EIP / EBS / S3 バックアップ | 約 2,480〜2,630 円 | 約 2,480〜2,630 円（変わらない） |
| CloudWatch（上流の「約 100 円」を次の 3 行に分けて精算） | 約 100 円 | — |
| ├ アラーム 3 個 | （上の約 100 円に含む） | 約 45 円（$0.10 × 3） |
| ├ カスタムメトリクス 7 本（稼働時間で按分） | （同上） | 約 17 円（$0.30 × 7 × 40/730 × 150 円。CloudWatch Agent のディスク指標がディメンションの組ごとに分かれる場合は増える。要確認） |
| └ Logs（取り込み 1 GB 未満、14 日保持） | （同上） | 約 0〜115 円 |
| S3 の `deploy/` 配布（数 MB） | — | 約 0 円 |
| SNS の暗号化キー | — | 0 円（暗号化しない。承認前の確認で本人が決定） |
| Lambda / EventBridge Scheduler / SNS 配信 | 約 0〜10 円 | 約 0〜10 円（無料枠内） |
| **合計** | 約 2,580〜2,740 円 | **約 2,542〜2,817 円**（予算 3,000 円の範囲内。余裕は約 183〜458 円） |

金額は 2026 年時点の概算で、1 USD = 150 円で換算しています。要確認です。

## Shared Infrastructure

Unit が 1 つだけなので、この節は該当しません。

## ホスト上の構成（参考）

| パス | 内容 |
|---|---|
| `/srv/minecraft/` | ワールド EBS のマウントポイント（`data/`、`mods-cache/`、`docker/`、`.lock`） |
| `/opt/minecraft/compose.yml` | リポジトリの `docker/compose.yml` を配置したもの（itzg の digest 固定。`env_file` は `/etc/minecraft/env`（0600）） |
| `/opt/minecraft/bin/*.sh` | mod-sync / health / idle-stop / backup-hourly / stop / restore-apply / boot-mode |
| `/etc/systemd/system/` | `mod-sync.service`、`minecraft.service`（`docker compose up`）、`health.timer`、`backup-hourly.timer`、`boot-mode.service`、`restore.target` |

- 設定ファイル（`config/server.properties` など）、MOD 一覧（`config/mods.yaml`）、compose ファイル、スクリプトは S3 のバックアップバケットとは別のプレフィックス `deploy/` に、apply 時に `aws_s3_object` で配置します。ホストは起動時にこれを同期します。
  - user data のサイズ上限（16 KB）を避けるため、user data には同期処理だけを書きます。

## Sources

- `nfr-design/` 各ファイル（LC1〜LC11、security-design §2、reliability-design、performance-design）
- `infrastructure-design-questions.md` [Q1]〜[Q3]

## Assumptions & Open Questions

- [assumption] VPC の CIDR は `10.20.0.0/24` とする（RFC1918 の範囲内なので、識別子チェックの許可リストに当たる）。
- [assumption] デプロイ用ファイルは S3 の `deploy/` プレフィックスで配布する。ホストのロールには `deploy/` の Get / List を加える（security-design.md §2 の app-server への追加）。
