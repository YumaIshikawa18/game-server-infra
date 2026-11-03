# Test Results

実行日時: 2026-11-03T13:52:13Z

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-generation-plan.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/unit-test-instructions.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-summary.md`

## 結果

| チェック | 結果 | 件数 | 実行場所 |
|---|---|---|---|
| `fmt` | 成功 | - | 作業ツリー |
| `tflint` | 成功 | - | 作業ツリー |
| `shellcheck` | 成功 | - | 作業ツリー |
| `bats` | 成功 | 62 件成功、失敗 0 | 作業ツリー |
| `pytest` | 成功 | 31 件成功、失敗 0 | 作業ツリー |
| `identifier-check` | 成功 | 単体テスト 38 件 | 作業ツリー。追跡済みファイルのみ |
| `checkov` | 成功 | - | 作業ツリー |
| `gitleaks` | 成功 | 43 コミット | 作業ツリー。コミット済みの内容のみ |
| `validate` | 成功 | 8 ディレクトリ | `.terraform` のないコピーで `check.py` を実行 |
| `terraform-test` | 成功 | 8 ディレクトリ、42 run | `.terraform` のないコピーで `check.py` を実行 |

スキップしたテストはありません。

`unit-test-instructions.md` のコマンドも実行しました。`prepare_env.bats` は 16 件成功、`minecraft_server` の `terraform test` は 10 件成功です。

未コミットの内容は `identifier-check` と `gitleaks` の対象になりません。そのため Code Generation で、変更したファイルと未追跡のファイルに同じ識別子の検査を、変更したディレクトリに `gitleaks dir` を実行しました。その結果、`prepare_env.bats` の UUID を直しました。

## 変更前との比較

`git archive HEAD` で取り出した変更前のコードで `bats` を実行しました。Code Generation のステップ 1 の結果が記録に残っていなかったためです。

| 時点 | `bats` の件数 | 失敗 |
|---|---|---|
| 変更前（HEAD） | 46 | 0 |
| 変更後 | 62 | 0 |

増えた 16 件は `prepare_env.bats` の件数と一致します。既存のテストの失敗はありません。変更前の比較は `bats` だけです。

## テストの検知力（FR6.1、FR6.3）

レビューの指摘への回答により、このステージで確認しました。作業ツリーを変えずに、使い捨てのコピーを壊してテストを実行しました。変更前のコピーでは、両方のテストが成功しています。

| テスト | 壊した数 | 検知 | 見逃し |
|---|---|---|---|
| `prepare_env.bats` | 14 | 14 | 0 |
| `minecraft_server.tftest.hcl` | 3 | 3 | 0 |

**`prepare_env.bats`（`prepare-env.sh` を変更）**

| 壊した内容 | 失敗したテストの数 |
|---|---|
| ホワイトリストの照合を無効にする | 1 |
| 照合で大文字と小文字を区別する | 2 |
| `OPS=` を書かない | 5 |
| 種のレベルを 4 にする | 2 |
| 未登録を読み取り失敗として扱う | 1 |
| 読み取り失敗を未登録として扱う | 1 |
| 一覧の形式の検査を無効にする | 2 |
| 一覧の空白を除かない | 1 |
| ログに `ops=` を書かない | 3 |
| 種の `chown` を行わない | 1 |
| `secrets.env` の権限を制限しない（`umask` と `chmod` の両方を外す） | 1 |
| 不正な一覧の値をログに出す | 1 |
| ホワイトリストの形式の検査を無効にする | 1 |
| 0 人のとき古い `ops.json` を残す | 1 |

**`minecraft_server.tftest.hcl`（`deploy.tf` を変更）**

| 壊した内容 | 結果 |
|---|---|
| `EXISTING_OPS_FILE` を外す | 10 run 中 1 件が失敗 |
| `OP_PERMISSION_LEVEL` を 4 にする | 10 run 中 1 件が失敗 |
| 配布ファイルに `OPS=` を入れる | 10 run 中 1 件が失敗 |

## 手元の `check.py` の失敗

作業ツリーでは `check.py validate` が AWS 認証のエラーで失敗します。`.terraform` を含まないコピーでは、同じ `check.py` の `validate` と `terraform-test` が成功しました。原因は、手元の `envs/prod/.terraform` に残る backend の情報と思われます。ご本人の回答により、手元の状態は変更していません。実際の CI での結果は PR で確認します。

## 実行しなかったもの

| 対象 | 理由 | 確認する時期 |
|---|---|---|
| `terraform plan` | AWS の認証が必要です | PR の CI |
| GitHub Actions 上のチェック全体 | PR がまだありません | PR の CI |
| 実機の確認 | 本物のイメージと AWS が必要です | Deployment Execution |

## Target Verification Matrix

| Target ID | Source | Expected | Actual | Evidence | Owning Stage | Verdict |
|---|---|---|---|---|---|---|
| TC-STRATEGY | Testing Contract の `strategy_volume` | コンポーネントごとに 5〜8 件。単体と主要な境界のテスト | `prepare-env.sh` 16 件、`minecraft_server` モジュール 10 run | `bats`、`terraform test` | build-and-test | Met |
| TC-REGRESSION | Testing Contract の `scope_floor` | 対象の不具合の回帰テストがある | 古い名前が `ops.json` から消えるテストが成功 | `prepare_env.bats`。壊したコピーでも検知 | build-and-test | Met |
| TC-EXISTING | Testing Contract の `scope_floor` | 既存のテストが成功のまま | `bats` 46 件から 62 件で失敗 0、`pytest` 31 件成功 | 上の比較 | build-and-test | Met |
| TEAM-PLAN-TEST | team.md の Testing Posture | 全モジュールに plan モードのテストがある | 8 ディレクトリすべて、42 run が plan のみ | クリーンなコピーの `check.py terraform-test` | build-and-test | Met |
| TEAM-CHECKS | team.md の Testing Posture | `fmt`、`validate`、`tflint`、`checkov` が成功 | すべて成功 | 上の結果 | build-and-test | Met |
| TEAM-CI | team.md の Testing Posture | チェックを CI で実行し、マージ前に成功 | the plan runs no CI Pipeline | `aidlc-state.md` の `ci-pipeline` は SKIP。既存の PR チェックの結果は PR で確認します | build-and-test | N/A |

## 要件のうち実機で確認するもの

上の表の対象は、Testing Contract と team.md の基準です。要件の次の項目は、手元のテストだけでは完了を示せません。実装と手順は揃っていますが、**未確認です。**

| 要件 | 手元で確認した範囲 | 残り | 確認する時期 |
|---|---|---|---|
| FR1 の受け入れ基準 | 一覧とレベル 3 の種を書くこと | ゲーム内のコマンド | Deployment Execution |
| FR2、FR4 の受け入れ基準 | 同期の設定と、種の書き直し | 実際の取り消し、再登録、復元後の同期 | Deployment Execution |
| NFR1 | テスト、`identifier-check`、`gitleaks` | state、plan、Actions のログ | PR の CI、Deployment Execution |
| NFR3 | 種の書き直し | 起動直後の `ops.json` | Deployment Execution |
| NFR4 | 未登録のテスト | 実際の Start と接続 | Deployment Execution |
| NFR6 | `aws_` のリソースを追加していないこと | plan の件数とアドレス | PR の CI |
| NFR7 | 上の結果 | PR の必須チェック | PR の CI |
| NFR8 | 手順 | 実際の Start | Deployment Execution |
