# Tech Stack Decisions

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`、`team-practices.md`、`nfr-requirements-questions.md`（Q1〜Q6）。

## 選定一覧

| 領域 | 選定 | 理由 | 出典 |
|---|---|---|---|
| IaC | Terraform（`required_version = "~> 1.x"`。Construction で最新の安定マイナー版に固定する） | 本人の明言による | [desc], team-practices |
| AWS provider | `hashicorp/aws` `~> 6.x`（Construction で具体値を固定する）。`.terraform.lock.hcl` はコミットする | team-practices の Code Style | team-practices |
| CI/CD | GitHub Actions。PR では fmt / validate / tflint / Checkov / `terraform test` / plan を実行し、マージ後は Environments `prod` の承認を経て apply する | 本人の明言、Practices Discovery による | [desc], NFR8 |
| 静的解析 | tflint（`tflint-ruleset-aws`）、Checkov | Practices Discovery の Q4 による | NFR8 |
| テスト | `terraform test`（plan モード、全モジュールに最低 1 つ）。通知用の Lambda は pytest で単体テストを書く | Practices Discovery の Q5 による | NFR8 |
| リージョン | 東京 `ap-northeast-1` | [Q6] | [Q6] |
| コンピュート | EC2 オンデマンド、Graviton（arm64）。`instance_type` は変数で、既定は `m7g.xlarge`（16 GB） | [Q1] [Q2] [Q3] | NFR2, NFR9 |
| OS | Amazon Linux 2023（arm64）。AMI は SSM パブリックパラメータから取得し、更新時の置き換えは FR4.5 に従う | SSM Agent と Docker の導入が容易で、サポート期間が長い | NFR5 |
| サーバー実行方式 | Docker と `itzg/minecraft-server` イメージ（digest で固定）。`TYPE`（VANILLA / FORGE / NEOFORGE / FABRIC）と `VERSION` などの環境変数でローダーとバージョンを切り替える | [Q4]。FR2.1 / FR2.2 の切り替えを自作せずに満たせる | FR2, NFR5.12 |
| MOD の取得 | リポジトリの MOD 一覧（URL とチェックサム）をサーバーに配布し、起動前のスクリプトで検証・配置する。イメージの `MODS_FILE` 等の機能を使うかは NFR Design で決める | FR3.1, FR3.2 | FR3 |
| ワールドの保存 | 専用の EBS gp3（既定 30 GB、暗号化、`prevent_destroy`） | FR1.3 | NFR4.6 |
| バックアップ | 圧縮して S3 に保存する（短期 24 世代と停止時 7 世代でプレフィックスを分ける） | [Q5] | NFR4.3 |
| 秘匿値 | SSM Parameter Store SecureString（Webhook URL、whitelist、RCON パスワード）。GitHub Secrets（CI 用の識別子） | NFR6 | NFR6.2, NFR6.3 |
| 通知 | CloudWatch アラーム / EventBridge → SNS → Lambda（Python 3.13、arm64）→ Discord Webhook。メールは SNS の購読で届ける | Q10 | FR8.2 |
| 監視 | CloudWatch（カスタムメトリクス、アラーム、Logs）、CloudWatch Agent | NFR7 | NFR7 |
| コスト | AWS Budgets（80% / 100%）→ SNS | FR9.1 | NFR1 |
| 起動・停止・復元の操作 | GitHub Actions の `workflow_dispatch`（start / stop / restore）。GitHub Environment `ops`（承認なし、`master` のみ）から、OIDC の運用操作用ロール（NFR5.2c）で EC2 と SSM Run Command を呼ぶ。apply 用のロールは使わない | FR4, FR6.5, NFR3.1 | FR4, NFR5.2 |
| 外部 watchdog | EventBridge スケジュール（5 分ごと）→ Lambda（Python 3.13、arm64）。インスタンスの無応答・ステータス異常・連続稼働上限を見て停止する | 停止を忘れても課金が続かないことの担保（NFR7.9a） | FR5.2, NFR1 |
| IAM / OIDC | OIDC プロバイダー、3 つの GitHub Actions 用ロール、permissions boundary は `bootstrap/` で作る | NFR5.2d | NFR5 |
| 自動停止 | サーバー側の systemd timer で人数を監視し、自分自身を停止する。詳細は NFR Design で決める | FR5 | FR5 |

## 品質ゲート

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR8.1 | 全モジュール（`bootstrap/`、`envs/prod/`、`modules/*`）に、plan モードの `terraform test` を最低 1 つ置く | CI の `terraform test` ジョブが全ディレクトリで成功する | NFR8 |
| NFR8.2 | マージ必須のチェック（Branch protection の required checks に登録する）は次の 9 つとする。<br>`terraform fmt -check` / `terraform validate` / tflint / Checkov / `terraform test` / `terraform plan` / pytest（Lambda）/ 識別子チェック / gitleaks<br>このうち pytest・識別子チェック・gitleaks の 3 つは、`team.md` の必須チェック一覧への追加になる | 失敗を含む PR がマージ不可になる（AC7.1.1） | NFR8, FR7.1, NFR6.1 |
| NFR8.3 | 通知用 Lambda の単体テスト（pytest）。正常系に加えて、エラー・境界のケースを 2 つ以上含める（Webhook の失敗、本文に識別子が含まれないこと） | CI で pytest が成功する | NFR8, construction ガードレール |

## トレードオフの記録

### 判断 1: サーバーの実行方式（Docker と itzg、自作 systemd との比較）

- **Context**: ローダーとバージョンを設定値で切り替える必要がある（FR2）。1 名体制のため、保守の手間を最小にしたい。
- **Decision**: Docker と `itzg/minecraft-server`（digest で固定）を使う。
- **Consequences**:
  - 良い点: ローダーの切り替え、Java のバージョン、EULA、RCON をイメージが面倒を見る。
  - 悪い点: サードパーティのイメージに依存する。digest 固定と更新 PR で管理する（NFR5.12）。Docker の分だけメモリをわずかに使う。
  - セキュリティ面: イメージの改ざんリスクは digest 固定で抑える。コンテナはホストのポート 25565 だけを公開する。
- **Alternatives Rejected**:
  - systemd と自作スクリプト: 依存は少ないが、4 種類のローダーごとの導入手順を自作して保守する必要がある。
  - ECS on EC2 / Fargate: Fargate はワールドの永続化（EFS）とコストの面で不利。ECS on EC2 は 1 台構成には過剰。

### 判断 2: バックアップの方式（S3 圧縮と EBS スナップショットの比較）

- **Context**: 毎時と停止時に、世代を分けて保持する（FR6）。復元を簡単にしたい。
- **Decision**: ワールドを圧縮して S3 に保存する。
- **Consequences**:
  - 良い点: ワールド単位で復元でき、別 AZ への復元も容易。
  - 悪い点: 世代の削除をスクリプトで実装する必要がある。毎時の取得では圧縮に CPU を使う。
  - セキュリティ面: S3 は Block Public Access、SSE、TLS 強制、バージョニングで保護する（NFR5.10）。
- **Alternatives Rejected**:
  - EBS スナップショットと DLM: 世代管理は自動化できるが、プレフィックスを分けた 2 枠の運用と、ワールド単位の復元が難しい。

### 判断 3: CPU アーキテクチャ（Graviton と x86 の比較）

- **Context**: 予算は月 3,000 円で、16 GB を既定にした（[Q1]）。
- **Decision**: Graviton（arm64）を使う。
- **Consequences**:
  - 良い点: 同等の性能で 1〜2 割安い。
  - 悪い点: ネイティブライブラリを含む MOD が動かない可能性がある。その場合は `instance_type` を x86 に変える。
  - セキュリティ面: 差はない。
- **Alternatives Rejected**:
  - x86: 互換性は最大だが、コストが上がり予算の余裕が減る。

## Checkov の抑止一覧（初期）

| Check | 対象 | 理由 |
|---|---|---|
| （未定） | — | Construction で必要になったものを、理由と合わせてここに追記する |

## Sources

- `requirements.md` FR2〜FR9, NFR1〜NFR9
- `team-practices.md`
- `nfr-requirements-questions.md` [Q1]〜[Q6]

## Assumptions & Open Questions

- [assumption] Lambda のランタイムは Python 3.13（arm64）とする。
- Open: MOD の取得に itzg イメージの機能を使うか、自作の検証スクリプトにするか（FR3.2 のチェックサム検証を満たす方を選ぶ）。
- Open: Terraform / provider / イメージ digest の具体値は Construction で固定する。
