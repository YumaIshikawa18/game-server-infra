# Integration Test Instructions

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-generation-plan.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/unit-test-instructions.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-summary.md`

実 apply を伴う統合テストは行いません（team.md の Testing Posture）。境界の確認は、手元の 2 種類のテストと、Deployment Execution の実機確認で行います。

## 手元で確認する境界

| 境界 | テスト | コマンド | 期待 |
|---|---|---|---|
| 起動処理と SSM、SNS（スタブ） | `tests/host/prepare_env.bats` | `python3 scripts/ci/check.py bats` | 全件成功 |
| 配布設定と `minecraft.env` | `minecraft_server.tftest.hcl` の `secure_host` | `python3 scripts/ci/check.py terraform-test` | 全件成功 |
| 出力とルートモジュール | `envs/prod/tests/prod.tftest.hcl` | 同上 | 全件成功 |

テストのデータは架空の名前だけを使い、`setup_host` の一時ディレクトリに置きます。カバレッジの基準は team.md のとおりで、行カバレッジは測定しません。

## Deployment Execution で確認する境界

本物のイメージと AWS を使うため、Deployment Execution で確認します。

レビューの指摘への回答により、最初の項目を空の UUID の種の確認とします。

| # | 確認 | 方法 | 要件 |
|---|---|---|---|
| 1 | 空の UUID の種をイメージが受け付け、サーバーが起動する | 一覧を登録して Start。`ops.json` のレベルが 3 で UUID が補われ、クライアントから接続できる | FR1.3、A-3 |
| 2 | 権限のレベル | ゲーム内で `/gamemode` と `/kick` が成功し、`/stop` が拒否される | FR1 |
| 3 | 取り消し | パラメータを削除して次の起動を行い、`ops.json` が `[]` で、`/gamemode` が拒否される | FR2.2、OQ1 |
| 4 | 再登録 | 再登録して次の起動を行い、`/gamemode` が成功する | FR2 |
| 5 | コンテナの再作成 | 一覧の変更が次の起動で反映される | FR4.1、OQ4 |
| 6 | 未登録のままの互換性 | 起動、接続、ホワイトリスト、ワールドが変わらない | NFR4 |
| 7 | 対象外の人に権限がない | 起動直後、`/op` を使う前の `ops.json` に対象外の名前がない | NFR3 |

項目 1 が失敗した場合は、パラメータを削除して Stop と Start を行って戻します。手順は `README.md` のとおりです。
