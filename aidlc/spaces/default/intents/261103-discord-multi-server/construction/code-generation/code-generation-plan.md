# Code Generation Plan

## Summary

- Builds: 今のサーバーで、秘匿パラメータの一覧からオペレーター権限（レベル 3）を付与し、取り消せる起動処理
- Touches: `prepare-env.sh`、`deploy.tf`、`envs/prod/outputs.tf`、`docker/compose.yml`（コメント）、`README.md`、`tests/host/`、`minecraft_server.tftest.hcl`
- Tests: `bats` 15 件程度と plan モードの `terraform test` 1 run の追加。AWS への適用は行いません

## 入力

- 要件: `aidlc/spaces/default/intents/261103-discord-multi-server/inception/requirements-analysis/requirements.md`
- 設計: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/infrastructure-design/infrastructure-specification.md`、`cicd-pipeline.md`、`monitoring-design.md`
- このプランに Unit とユーザーストーリーはありません。各ステップは FR と NFR に対応づけます。

## Steps

- [x] **Step 1: テストの実行環境を確認する（要件なし）。** `unit-test-instructions.md` のコマンドで、変更前の `bats` と `terraform test` を実行して結果を記録します。既存の失敗があれば、以降の変更と区別できるように記録します。

- [x] **Step 2: 起動処理を実装する（FR1、FR2、FR3、FR4、NFR1、NFR2、NFR5）。** `modules/minecraft_server/files/bin/prepare-env.sh` を次のとおり変更します。
  - `<MC_PARAM_PREFIX>/ops` を読みます。`ParameterNotFound` だけを未登録（0 人）として扱い、ほかのエラーは `start_failed` にします。`aws` のエラー出力はログと通知に出しません。
  - 空白を除いて、ホワイトリストと同じ形式で検査します。形式の検査は既存の関数を共用し、用途に合う名前に変えます。
  - 各名前がホワイトリストにあることを、大文字と小文字を区別せずに検査します。
  - `ops.json` の種（名前、空の UUID、レベル 3、0 人なら `[]`）と `secrets.env` を一時ファイルに書いてから、`mv` で置き換えます。`ops.json` は UID 1000 のユーザーが読み書きできるようにします。`secrets.env` には `OPS=` を必ず書きます。
  - イベント `ops_unavailable`、`ops_invalid`、`ops_not_whitelisted`、`ops_seed_failed` を記録し、文面に名前を含めません。`env_prepared` に `ops=` の人数を追加します。

- [x] **Step 3: テストのスタブを直す（FR6.2）。** `tests/host/helpers.bash` の SSM スタブが、パラメータ名ごとに値を返し、未登録と読み取り失敗を再現できるようにします。既存のテストの動作は変えません。

- [x] **Step 4: 起動処理のテストを書いて実行する（FR6.1）。** `tests/host/prepare_env.bats` を新規に作ります。内容は `unit-test-instructions.md` の一覧のとおりです。

- [x] **Step 5: 配布設定を変更する（FR1.3、FR2.1）。** `modules/minecraft_server/deploy.tf` の `minecraft_env` に `EXISTING_OPS_FILE = "SYNCHRONIZE"` と `OP_PERMISSION_LEVEL = "3"` を追加します。`envs/prod/outputs.tf` に `ops_parameter`（`sensitive`）を追加します。`docker/compose.yml` の `secrets.env` のコメントに、オペレーターの一覧を追記します。

- [x] **Step 6: Terraform のテストを書いて実行する（FR6.3、NFR1）。** `modules/minecraft_server/tests/minecraft_server.tftest.hcl` に、設定値があること、`OPS=` が配布ファイルに含まれないこと、`prepare-env.sh` が配布対象であることの検査を追加します。既存の `secure_host` の秘匿値の検査は残します。

- [x] **Step 7: 手順書を更新する（FR5、NFR8）。** `README.md` に次を追加します。実際の名前や識別子は書きません。
  - 一覧の登録、変更、取り消し（パラメータの削除）
  - 反映の確認（起動ログの `ops=`、起動直後の `ops.json`、ゲーム内のコマンド）
  - ホワイトリストから外すときは、先にオペレーターの一覧から外す順序
  - ロールバックの順序と、残った `ops.json` を `[]` にする手順
  - イメージの digest を更新するときのレベルの確認

- [x] **Step 8: 全体のチェックを実行する（NFR7）。** `python3 scripts/ci/check.py` で `fmt`、`validate`、`tflint`、`terraform-test`、`shellcheck`、`bats`、`pytest`、`identifier-check` を実行します。`checkov` と `gitleaks` も実行します。`plan` は AWS の認証が必要なため、CI に任せます。

## 変更しないもの

- `scripts/`、`.github/workflows/`、`bootstrap/`、`modules/` のうち `minecraft_server` 以外、`lambda/`、`user_data.sh.tftpl`、`minecraft.service`。
- AWS 上のリソースとパラメータ。`aws` コマンドは実行しません。パラメータの登録とデプロイは Deployment Execution で行います。

## リスク

| リスク | 対応 |
|---|---|
| `bats` の環境では `chown` が root を前提とする | `check.py` の `bats` はコンテナの root で実行します。手元で直接実行する場合は対象外です |
| `ops.json` の種の形式がイメージの内部の動作に依存する | 固定している digest で確認済みです。実機の確認は Deployment Execution で行います |

## Testing Contract

```json
{
  "version": 1,
  "methodology": "test-after",
  "source": "team",
  "ordering": "各 Terraform モジュール（または環境のルートモジュール）を実装した後に、そのモジュールの plan モード `terraform test` を書いて実行し、あわせて fmt / validate / tflint / Checkov を通してから PR に出します。",
  "scope": "bugfix",
  "test_strategy": "standard",
  "project_type": "brownfield",
  "applicable_notes": [
    {
      "layer": "org",
      "text": "We treat tests as a first-class deliverable in every Bolt. The specific\nmethodology (TDD, BDD, ATDD, or classic test-after) is affirmed at\npractices-discovery and recorded in `team.md` under this heading with explicit\n`Methodology` and `Ordering` fields; Code Generation resolves those fields\nindependently from coverage, tooling, and scope notes.\n\nWhen no posture has been affirmed, our default per scope is:\n- **Methodology**: test-after\n- **Ordering**: implement each applicable testable layer, then write and run\n  that layer's tests.\n- `mvp`, `enterprise`, `feature`, `infra`, `classic` add an 80% line-coverage\n  floor and CI execution before merge.\n- `bugfix`, `security-patch` add a targeted regression for the specific\n  bug/vulnerability and require the existing suite to remain green.\n- `express` uses the Minimal strategy: requirement-driven unit tests (one per\n  requirement, with a happy-path floor per component); existing tests remain\n  green.\n- `poc`, `refactor`, `workshop` add no extra new-test floor and require the\n  existing suite to remain green.\n\nThe active `Test Strategy` still applies in every scope and determines test\nvolume/types. Scope floors are additive; they never reduce or replace the\nselected strategy.\n\nBuild and Test verifies defined coverage floors and affirmed quality targets;\nthey may not be weakened to make a step pass.\n\nAffirm a stricter posture in `team.md` if the team commits to one."
    },
    {
      "layer": "team",
      "text": "- **Methodology**: test-after\n- **Methodology evidence**: 本人が Q5 で「plan モードの `terraform test` を全モジュールに最低 1 つ + 静的チェック・スキャンすべて通過」（A）を選び、テスト先行の方法論は求めていません。Terraform 中心のリポジトリで、モジュールを書いてから plan モードのテストで期待値を確認する流れが自然なため、test-after とします。\n- **Ordering**: 各 Terraform モジュール（または環境のルートモジュール）を実装した後に、そのモジュールの plan モード `terraform test` を書いて実行し、あわせて fmt / validate / tflint / Checkov を通してから PR に出します。\n- PR ごとに GitHub Actions で次のチェックを実行し、1 つでも失敗したらマージをブロックします。[Q4]\n  - `terraform fmt -check`\n  - `terraform validate`\n  - tflint（AWS ルールセット付き）\n  - Checkov（IaC セキュリティスキャン）\n  - Trivy は採用しません。\n- org.md の `infra` スコープ既定である「80% line-coverage floor」は、Terraform には行カバレッジがそのまま当てはまらないため、次の基準に **置き換え** ます（緩和ではありません）。[Q5]\n  - すべてのモジュールに、plan モード（実リソースを作らない）の `terraform test` が最低 1 つあること\n  - 上記の必須チェックがすべて通過していること\n  - これらを CI で実行し、マージ前に成功していること\n- 実 apply を伴う統合テストは行いません。実環境での確認は、デプロイ後のスモークテスト（`## Deployment`）で担保します。\n- Build and Test では、この置き換え基準を弱めてステップを通すことはしません。"
    }
  ],
  "obligations": {
    "strategy": "standard",
    "strategy_volume": [
      "Five to eight tests per component.",
      "Unit tests plus integration tests for key boundaries.",
      "Add E2E, performance, or security tests when requirements demand them."
    ],
    "scope_floor": [
      "Include a targeted regression for the bug or vulnerability.",
      "Keep the existing test suite green."
    ],
    "combination_rule": "Apply every selected-strategy obligation and every scope-floor obligation; neither replaces the other, and a targeted scope regression may add the narrowest necessary test type beyond the strategy default."
  },
  "plan_profile": {
    "methodology": "test-after",
    "runner_step": "Verify the existing test runner/configuration and record the exact unit-scoped command.",
    "runner_ready_before_first_test": true,
    "testable_layers": [
      "Data model / database behavior",
      "Repository / data access",
      "Business logic",
      "API / endpoint",
      "Frontend behavior"
    ],
    "steps": [
      "Project structure and production configuration skeleton.",
      "Verify the existing test runner/configuration and record the exact unit-scoped command.",
      "Data model / database behavior - implement.",
      "Data model / database behavior - write and run its tests after implementation.",
      "Repository / data access - implement.",
      "Repository / data access - write and run its tests after implementation.",
      "Business logic - implement.",
      "Business logic - write and run its tests after implementation.",
      "API / endpoint - implement.",
      "API / endpoint - write and run its tests after implementation.",
      "Frontend behavior - implement.",
      "Frontend behavior - write and run its tests after implementation.",
      "Environment/build configuration.",
      "Documentation and traceability."
    ]
  },
  "input_sha256": "sha256:32d3c3508b8e0acc69aa7170b6fa9c41f3f7796a80ae299581081ebfc3789c25",
  "contract_sha256": "sha256:54ecba1976535a9c2a0ddbcf4c33db0b0db32d2b75d40ba751c56a3509dd7c2e"
}
```
