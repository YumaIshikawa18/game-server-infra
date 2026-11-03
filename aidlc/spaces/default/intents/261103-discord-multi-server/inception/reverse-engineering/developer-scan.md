# Reverse Engineering: Developer Scan（game-server-infra）

## Developer Code Scan Results

対象コミットは `5b2093db7c36855f7d5b59e1e29d3cb2580857e1`、深さは Standard、幅はリポジトリ全体です。コードは読むだけで、テスト・ビルド・プログラムは実行していません。識別子の実値（AWS アカウント ID、IAM ロール名や ARN、バケット名）は本書に記載していません。ソースに現れるのはテスト用のダミー値だけです。

### Scan Coverage
- **Analyzed deeply**:
  - `.github/workflows/`、`.github/dependabot.yml`、`.github/CODEOWNERS`
  - `bootstrap/`（`*.tf`、`tests/`）
  - `envs/prod/`（`*.tf`、`minecraft.json`、`tests/`）
  - `modules/minecraft_server/`（`*.tf`、`user_data.sh.tftpl`、`files/bin/`、`files/systemd/`、`tests/`）
  - `modules/network/`、`modules/world_backup/`、`modules/notifier/`、`modules/watchdog/`、`modules/monitoring/`
  - `lambda/notifier/`、`lambda/watchdog/`
  - `docker/compose.yml`
  - `scripts/ci/`、`scripts/cd/`、`scripts/local/`
  - `tests/host/`、`tests/ci/`、`tests/cd/`、`tests/checkov/`
  - `README.md`、`docs/client-setup.md`
  - `.gitignore`、`.editorconfig`、`.shellcheckrc`、`.tflint.hcl`、`.tool-versions`、`requirements-test.txt`
- **Skimmed only**:
  - `bootstrap/.terraform.lock.hcl`、`envs/prod/.terraform.lock.hcl`、`modules/notifier/.terraform.lock.hcl`（プロバイダーの版だけを確認）
  - `modules/` の残りの `.terraform.lock.hcl`（存在だけを確認）
  - `docs/images/architecture.drawio.png`（バイナリ。存在だけを確認）
  - `LICENSE`（README の記載だけを確認）
- **Left out**:
  - `.gitignore` が除外するもの（`.terraform/`、`*.tfstate*`、`*.auto.tfvars`、`*.auto.tfvars.json`、`backend.hcl`、`.ci-private/`、`.build/`、`__pycache__/`、`.pytest_cache/`、`*tfplan*`、`override.tf` 系）
  - AI-DLC 本体（`.claude/`、`.kiro/`、`.codex/`、`.cursor/`、`.opencode/`、`.aidlc/`、`aidlc/`、`.agents/`、`aidlc.settings.json`、`AGENTS.md` のマーカー区間、`.gitignore` のマーカー区間、`.mcp.json` のサーバー定義）

### Packages Found
- `bootstrap` — Terraform ルートモジュール — HCL — state バケット、ログバケット、CI 用 IAM ロール、OIDC、permissions boundary。手元から適用
- `envs/prod` — Terraform ルートモジュール — HCL — 本番の組み立て。ゲーム設定は `minecraft.json`
- `modules/network` — Terraform モジュール — HCL — 専用 VPC、公開サブネット、25565/TCP の SG、フローログ
- `modules/minecraft_server` — Terraform モジュール＋ホスト資材 — HCL / Bash / systemd — EC2、ワールド EBS、EIP、ホスト用 IAM、SSM 文書、S3 配布ファイル
- `modules/world_backup` — Terraform モジュール — HCL — バックアップ兼配布バケット
- `modules/notifier` — Terraform モジュール — HCL — SNS 2 トピック、メール購読、notifier Lambda
- `modules/watchdog` — Terraform モジュール — HCL — 外部強制停止 Lambda と EventBridge Scheduler
- `modules/monitoring` — Terraform モジュール — HCL — CloudWatch アラームと予算
- `lambda/notifier`、`lambda/watchdog` — Lambda — Python 3.13 — Discord 通知、強制停止
- `docker` — コンテナ定義 — Compose — `itzg/minecraft-server`
- `scripts/ci`、`scripts/cd`、`scripts/local` — ツール — Python — CI チェック、デプロイと運用、手元の準備

### Build System
- **Type**: Terraform（ルート 2、モジュール 6）。アプリのビルドはなく、Lambda は `archive_file` で zip 化します。チェックは Docker イメージ上で `scripts/ci/check.py` が実行します
- **Config Files**: `.tool-versions`、各 `versions.tf`、各 `.terraform.lock.hcl`、`.tflint.hcl`、`.shellcheckrc`、`.editorconfig`、`requirements-test.txt`
- **Build Dependencies**: `envs/prod` → 6 モジュール。`minecraft_server` → `network`（subnet、SG）、`world_backup`（バケット）、`notifier`（events トピック）。`watchdog` → `notifier`。`monitoring` → `notifier`。`envs/prod` は `docker/compose.yml` と `lambda/*` をファイルとして読みます。`scripts/cd/common.py` と `scripts/local/terraform.py` は `scripts/ci/plan.py` に依存します

### APIs Discovered
- HTTP API — なし。公開面は Minecraft Java の 25565/TCP だけです（`modules/network/main.tf:61-68`）
- SSM Run Command 文書 — `modules/minecraft_server/ssm.tf:4-25` — 3 件（`mc-stop`、`mc-health-check`、`mc-restore-apply`）
- SSM Parameter Store（本人が手で登録）— `modules/minecraft_server/files/bin/prepare-env.sh:21`、`envs/prod/main.tf:36` — 2 件（`/<prefix>/minecraft/whitelist`、`/<prefix>/minecraft/discord-webhook`）
- SNS メッセージ契約 — `modules/minecraft_server/files/bin/common.sh:50-60`、`scripts/cd/common.py:176-184`、`lambda/watchdog/watchdog.py:64-69` — 独自 JSON の発行元 3 種と、notifier が解釈する 3 形式
- GitHub Actions workflow — `.github/workflows/` — 5 件（PR、Deploy、Start、Stop、Restore）
- CLI — `scripts/ci/check.py`、`scripts/ci/client_guide.py`、`scripts/ci/plan.py`、`scripts/cd/deploy.py`、`scripts/cd/operations.py`、`scripts/local/{prepare,terraform,github_setup}.py`

### Frameworks & Libraries
- Terraform — 1.17.1（`~> 1.17.0`）— IaC
- hashicorp/aws — 6.71.0（`~> 6.71.0`）— AWS プロバイダー
- hashicorp/archive — 2.8.1（`~> 2.8.0`）— Lambda の zip
- itzg/minecraft-server — `2026.10.0-java25`（digest 固定）— サーバーコンテナ
- Minecraft — 26.3、vanilla — ゲーム本体
- docker compose プラグイン — v5.6.1（sha256 固定）— ホスト上のコンテナ起動
- Python — 3.13.18（CI）、python3.13（Lambda ランタイム）。標準ライブラリのみで、boto3 は Lambda 実行環境のものを使います
- pytest — 9.1.1 — Lambda のテスト
- Amazon Linux 2023 — AMI 最新を初回解決（以後 `ignore_changes`）— ホスト OS
- GitHub Actions — `actions/checkout` v7.0.1、`hashicorp/setup-terraform` v4.0.1、`aws-actions/configure-aws-credentials` v6.3.0（いずれも SHA 固定）

### Test Coverage
- **Test Directories**: `bootstrap/tests/`、`envs/prod/tests/`、`modules/*/tests/`（plan のみ）、`lambda/*/tests/`（pytest）、`tests/host/`（bats）、`tests/ci/`、`tests/cd/`（unittest）
- **Test Frameworks**: `terraform test`（`mock_provider`、ネットワーク遮断）、bats 1.14.0、pytest、unittest
- **Coverage Config**: absent。行カバレッジは取っていません。team.md がテスト存在とチェック通過の基準に置き換えています。`check.py` は plan 以外の `terraform test` を拒否します（`scripts/ci/check.py:100-108`）

### Code Quality Indicators
- **Linting**: `terraform fmt -check`、`terraform validate`、tflint 0.65.0（AWS ルールセット 0.50.0）、Checkov 3.4.0、shellcheck 0.11.0（`-S style`）、gitleaks 8.30.1、独自の identifier-check。Python 向けのリンターはありません
- **CI/CD**: `.github/workflows/pr.yml`（10 チェック＋ plan）、`deploy.yml`（plan → 承認 → digest 照合 → apply → スモークテスト）、`start.yml`、`stop.yml`、`restore.yml`
- **Documentation**: `README.md` は詳細です。`docs/client-setup.md` は `minecraft.json` から生成し、CI で食い違いを検出します。コメントは「なぜそうするか」を日本語で記録し、Checkov の skip にはすべて理由があります

### Technical Debt Signals
- `prepare-env.sh`、`boot-mode.sh`、`health-check.sh` を呼ぶ bats テストがありません。`tests/host/helpers.bash:54` の `STUB_WHITELIST` はどのテストからも使われていません
- `docker/compose.yml:1` は Dependabot（docker-compose）によるイメージ更新を述べていますが、`.github/dependabot.yml` の対象は `github-actions` だけです
- `scripts/local/terraform.py:27` が Terraform イメージの版を直書きしており、`.tool-versions` と二重管理です
- `scripts/ci/check.py:68-70` の `identifier-check` が `tests/ci` と `tests/cd` の単体テストも実行しています。チェック名と内容が一致しません
- 使われていない出力があります（`modules/minecraft_server` の `role_name`、`modules/world_backup` の `bucket_arn`、`modules/network` の `vpc_id`）
- `.gitignore` の先頭に Java や Node.js のテンプレートの名残があります（`target/`、`.sts4-cache` など）
- `envs/prod/main.tf:36` が `/<prefix>/minecraft` を、`modules/minecraft_server/main.tf:22` の `param_prefix` とは別に組み立てています
- TODO / FIXME / HACK はありません。`shellcheck disable` は 2 件、`noqa` は 2 件で、いずれも局所的です

## Handoff Summary
- **Intent-relevant finding**: whitelist は次の 5 点を通って流れており、op 権限はこの経路に沿って追加できます。
  1. 本人が SSM SecureString `/<prefix>/minecraft/whitelist` を手で登録します（`README.md:100-102`、`envs/prod/outputs.tf:14-18`）。Terraform は値を持ちません。
  2. `minecraft.service` の `ExecStartPre` である `prepare-env.sh` が起動ごとに読み、空白を除去し、形式を検査して `/etc/minecraft/secrets.env`（0600）へ `WHITELIST=` を書きます（`prepare-env.sh:14-16,21-39`、`files/systemd/minecraft.service:12`）。
  3. `docker/compose.yml:15-18` の `env_file` がコンテナに渡します。
  4. 同期方式は `deploy.tf:14-16` の `ENABLE_WHITELIST`、`ENFORCE_WHITELIST`、`EXISTING_WHITELIST_FILE=SYNCHRONIZE` で決まります。
  5. IAM は `ssm:GetParameter` と `kms:Decrypt` を `parameter/<prefix>/minecraft/*` に許可済みです（`iam.tf:8,41-45`）。boundary は `parameter/<prefix>/*` です（`bootstrap/iam.tf:9,87-88`）。

  同じ接頭辞の下に新しいパラメータを置くなら、IAM と `user_data.sh.tftpl` の変更は不要と読めます。現在 `OPS` と `EXISTING_OPS_FILE` はどこにも設定されていません。`scripts/local/prepare.py` は whitelist に関与していません。
- **Risks / follow-up**:
  - **fail-closed の波及**: whitelist と同じく必須にすると、パラメータ未登録のまま次に起動した時点で `start_failed` になります。Deploy のスモークテストは起動中の既存サーバーへの ping だけで、配布スクリプトも次の起動まで反映されないため、問題が初めて出るのは次の Start です（`deploy.tf:1-2`、`user_data.sh.tftpl:59-74`、`scripts/cd/deploy.py:117-128`）。
  - **権限の取り消し**: itzg の `EXISTING_OPS_FILE` の既定は `SYNC_FILE_MERGE_LIST` で、`OPS` は追加マージです。一覧から外しても権限が残らないようにするには `SYNCHRONIZE` が必要と読めます（公式ドキュメント。実機は要確認）。
  - **op が 0 人の表現**: 現在の検査は 1 名以上を要求します。SSM の値は空にできないと思われ（要確認）、`OPS` 未設定時の `SYNCHRONIZE` の挙動も公式ドキュメントに記載がありません（要確認）。
  - **未確認の仕様**: vanilla では op が whitelist を迂回できる可能性があります。`op-permission-level` は未設定で、既定値は 4 と思われます（いずれも要確認）。
  - **既存の ops.json**: ワールド EBS 上の `ops.json` は確認していません。手動で付けた権限があれば `SYNCHRONIZE` で消えます。
  - **テストの欠落**: `prepare-env.sh` のテストがなく、スタブの `ssm get-parameter` はパラメータ名を区別しません（`tests/host/helpers.bash:54`）。回帰テストの追加時にスタブの修正が必要です。
  - **ログ**: `prepare-env.sh` はプレイヤー名ではなく人数だけをログに出します（`prepare-env.sh:40`）。この性質は維持が必要です。
  - **単一サーバー前提**: 後続の作業に関わるため `architecture.md` と `code-quality-assessment.md` に一覧化しました。本作業では設計していません。
