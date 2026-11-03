# Build and Test Summary

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-generation-plan.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/unit-test-instructions.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-summary.md`

## 状況

手元で実行できるチェックは、すべて成功しました。詳細は `test-results.md` です。

## テストの種類

| 種類 | ファイルまたは方法 | 結果 |
|---|---|---|
| 単体（スタブ） | `bats`、`pytest` | 62 件、31 件が成功 |
| モジュール（plan のみ） | `terraform test` | 8 ディレクトリ、42 run が成功 |
| 静的解析とスキャン | `fmt`、`validate`、`tflint`、`shellcheck`、`checkov`、`gitleaks`、`identifier-check` | 成功 |
| テストの検知力 | 使い捨てのコピーを壊して実行 | 17 パターンすべて検知 |
| 統合 | `integration-test-instructions.md` | 手元の分は上記に含みます。実機の分は Deployment Execution で行います |

性能とセキュリティの手順書は作りません。テスト戦略が Standard で、性能の要件もないためです。

## カバレッジの基準

team.md のとおり、行カバレッジは測定しません。全モジュールに plan モードのテストがあること、必須チェックが成功することを基準とします。この作業に Unit はありません。

## Target Verification Matrix

| Target ID | Source | Expected | Actual | Evidence | Owning Stage | Verdict |
|---|---|---|---|---|---|---|
| TC-STRATEGY | Testing Contract の `strategy_volume` | コンポーネントごとに 5〜8 件。単体と主要な境界のテスト | `prepare-env.sh` 16 件、`minecraft_server` モジュール 10 run | `test-results.md` | build-and-test | Met |
| TC-REGRESSION | Testing Contract の `scope_floor` | 対象の不具合の回帰テストがある | 古い名前が消えるテストが成功 | `test-results.md` | build-and-test | Met |
| TC-EXISTING | Testing Contract の `scope_floor` | 既存のテストが成功のまま | `bats` 46 件から 62 件で失敗 0、`pytest` 31 件成功 | `test-results.md` | build-and-test | Met |
| TEAM-PLAN-TEST | team.md の Testing Posture | 全モジュールに plan モードのテストがある | 8 ディレクトリ、42 run | `test-results.md` | build-and-test | Met |
| TEAM-CHECKS | team.md の Testing Posture | `fmt`、`validate`、`tflint`、`checkov` が成功 | すべて成功 | `test-results.md` | build-and-test | Met |
| TEAM-CI | team.md の Testing Posture | チェックを CI で実行し、マージ前に成功 | the plan runs no CI Pipeline | `aidlc-state.md` の `ci-pipeline` は SKIP | build-and-test | N/A |

## 準備の状況

| 観点 | 状況 |
|---|---|
| ビルド | 準備済み |
| テスト | 準備済み。手元のテストはすべて成功 |
| デプロイ | PR の CI と `terraform plan` の成功が前提です。実機の確認はこれからです |

## 残っている項目

- PR の CI で `validate`、`terraform test`、`plan` が成功することを確認してからマージします。手元の `check.py validate` は失敗しますが、`.terraform` のないコピーでは成功しました。
- 空の UUID の種は、実際のサーバー起動では未確認です。Deployment Execution の最初に確認します。この前提が崩れるとサーバーが起動しないため、最も大きいリスクです。
- 要件のうち、ゲーム内の権限、取り消し、接続などは未確認です（`test-results.md` の「要件のうち実機で確認するもの」）。
- 変更はまだコミットしていません。
