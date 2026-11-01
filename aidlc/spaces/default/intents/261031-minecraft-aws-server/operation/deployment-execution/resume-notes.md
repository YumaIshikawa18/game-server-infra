# 次回の再開メモ（Deployment Execution）

## 現在地

Environment Provisioning は承認済み。Deployment Execution の質問 Q1〜Q4 とまとめの確認（Looks correct）が済み、デプロイの前の作業中に本人の希望で中断（2026-11-01）。

## 決まっていること

- Q1: master の承認ルールは変えず、管理者としてセルフマージする。マージ前に PR の必須チェック 11 件の全成功を目で確認する。必須チェック 11 件は Branch protection に登録する。
- Q2: apply の前に whitelist と Discord の Webhook を SSM SecureString に登録する。
- Q3: マージ後、30 分以内にクライアントから接続できるときに prod を承認する。
- Q4: 最新コミットへの Codex のレビューを確認し、指摘があれば確かめて直してからマージする。

## PR #3 の状態

- 最新コミットは `c1bf5b3`（push 済み）。CI と Codex のレビューの結果は未確認。
- Codex の指摘はこれまで 13 件。12 件は修正し、#12（caller identity による digest 不一致）は実際の plan の構造で再現しないことを確認して、根拠を返信し、テストで固定した。すべての指摘に返信済み（前置きの謝辞は書かない）。

## 次に行うこと

1. `c1bf5b3` の CI 11 件と、Codex のレビューを確認する。新しい指摘は、実際の挙動で確かめてから対応する。
2. 本人の作業の完了を確認する（値は見ない）: Branch protection の必須チェック 11 件、SSM の whitelist と discord-webhook（`aws ssm describe-parameters` で件数だけを見る）。
3. 本人が PR #3 をマージする → deploy.yml の plan サマリーを確認 → 本人が prod を承認する（30 分以内に接続できるとき）。
4. apply の結果を確認する。CI の apply ロールの権限が足りなければ、bootstrap の追加 plan を本人に見せ、本人が適用する（apply は本人が `!` で実行する。自動実行は止められる）。
5. スモークテスト（mc-health-check）、メール購読の確認（2 通）、クライアントからの接続（walking skeleton の完了条件）。
6. 成果物（deployment-log.md、smoke-test-results.md、health-check-report.md）を作り、承認を求める。

## 注意

- ローカルの bats は `local/bats-host:1`（jq などを入れた手元のイメージ）で実行すると、パッケージのダウンロード待ちで止まらない。CI はそのまま `scripts/ci/check.py bats` で動く。
- Terraform は手元の版が古いので、`hashicorp/terraform:1.17.1` のコンテナで実行する。
