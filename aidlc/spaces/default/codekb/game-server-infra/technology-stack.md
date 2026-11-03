# Technology Stack

## 言語

| 言語 | 版 | 用途 |
|---|---|---|
| HCL（Terraform） | Terraform 1.17.1（`~> 1.17.0`） | インフラ |
| Bash | AL2023 付属 | ホストのスクリプト、user data |
| Python | 3.13.18（CI）、`python3.13`（Lambda） | Lambda、CI / CD ツール |
| YAML | - | GitHub Actions、Compose |

## Terraform プロバイダー

| プロバイダー | 制約 | ロック |
|---|---|---|
| `hashicorp/aws` | `~> 6.71.0` | 6.71.0 |
| `hashicorp/archive` | `~> 2.8.0`（`envs/prod`、`notifier`、`watchdog`） | 2.8.1 |

## AWS サービス

| サービス | 用途 |
|---|---|
| EC2、EBS（gp3、暗号化）、EIP | ホスト。既定は `m7g.xlarge`（arm64）、ワールド 30 GB、ヒープはメモリの 75% |
| VPC、フローログ | 専用ネットワーク。NAT なし |
| S3 | state、運用ロック、バックアップ、配布、アクセスログ |
| SSM | Run Command、Parameter Store、管理接続 |
| KMS | SecureString の復号（AWS 管理キー想定、`kms:ViaService` で制限） |
| IAM、GitHub OIDC | CI ロール 3 つ、app ロール、permissions boundary |
| Lambda（arm64、128 MB、30 秒） | notifier、watchdog |
| EventBridge Scheduler | watchdog の 5 分周期 |
| SNS | `events`、`alerts` |
| CloudWatch | ログ（14 日）、カスタムメトリクス、アラーム |
| AWS Budgets | 月次予算 |

## ランタイム

| 構成要素 | 版 |
|---|---|
| OS | Amazon Linux 2023（SSM の最新 AMI を初回解決。以後は `ignore_changes`） |
| コンテナ | `itzg/minecraft-server:2026.10.0-java25`（digest 固定） |
| Minecraft | 26.3、vanilla（Java 25 が必要） |
| Docker | `dnf` で導入 |
| docker compose プラグイン | v5.6.1（sha256 固定） |
| ホストのツール | `amazon-cloudwatch-agent`、`zstd`、`jq` |
| コンテナ内のツール | `rcon-cli`、`mc-monitor` |

## CI / 品質ツール

バージョンは `.tool-versions` で固定します。

| ツール | 版 |
|---|---|
| tflint | 0.65.0（AWS ルールセット 0.50.0） |
| Checkov | 3.4.0 |
| shellcheck | 0.11.0 |
| bats | 1.14.0 |
| gitleaks | 8.30.1 |
| pytest | 9.1.1 |

## GitHub Actions

いずれもコミット SHA で固定し、実行環境は `ubuntu-24.04` です。

| Action | 版 |
|---|---|
| `actions/checkout` | v7.0.1 |
| `hashicorp/setup-terraform` | v4.0.1 |
| `aws-actions/configure-aws-credentials` | v6.3.0 |

## 固定の方針

- Minecraft のバージョンと MOD は具体値を必須とします。`latest` は拒否します（`modules/minecraft_server/variables.tf:108-116`、`143-167`）。
- コンテナイメージは digest を必須とします（`variables.tf:198-206`）。
- MOD は sha256 を照合してから配置します。
