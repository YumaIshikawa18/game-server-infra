# 次回の再開メモ（Deployment Execution）

## 現在地

Environment Provisioning は承認済み。Q9 の本人回答で PR #4 のマージと新しい prod 承認が完了したが、Deploy run 41296893187（909a373）の apply は部分作成後に失敗した。state と運用ロックを保持している。現在の復旧準備は `partial-deployment-recovery.md` に記録した。Q11で本人がbootstrapの変更5件を適用済み、再planの差分0件を確認。その後、既存リソースのrefresh用読み取り2操作の不足がCIで判明し、追加のbootstrap変更3件を準備した。Q12で本人はLambda予約枠を外し共有枠を使う構成を選択済み。以前の上限1,000への申請はCASE_OPENEDのままで取り下げ未実施だが、デプロイに増枠は不要。

現在の作業ブランチは `fix/deployment-resource-permissions`。PR #5の最新HEADは`f56f72a`。Lambda2関数を予約枠なし（-1）へ変更済み。以前の読み取り修正はQ11 / Q13 / Q14ですべて本人が適用し、それぞれ再plan差分0を確認済み。SGルールの作成時タグ付けの不足を予防検査で確認し修正。また残っていたCI plan失敗はBudgetsタグ読み取りの不足と米国東部のCloudTrailで特定した。最新bootstrap変更3件（applyのcompute / reads、planのinline policy）はQ15で適用済みで、再plan差分0。対象Terraformテスト26件、Python61件、IAMシミュレーション70件が成功。

## 初回 apply の失敗と修正

- `initial-deployment-failure.md` に原因、検証、安全性、復旧を記録した。
- 同じ入力で実環境 plan を連続生成すると `relevant_attributes` の順序だけが変わることを再現。修正後は同じ内容として比較されることを確認した。内容や属性パス内の順序の変更は拒否する。
- ETag 指定の DeleteObject には GetObject も必要だったため、apply / ops に専用ロック 1 キーだけの読み取りを追加した。If-Match の条件、state の分離は維持。
- bootstrap の追加 plan（追加 0 / 変更 2 / 削除 0）は本人が適用済み。対象は apply の state 用管理ポリシーと ops の inline policy。適用後に再 plan して差分 0 件を確認した。
- ローカル CD テスト 38 件、CI テスト 15 件、bootstrap の plan モードテスト 9 件、識別子検査が成功。Access Analyzer のポリシーエラーなし。
- PR #4 の最新 HEAD f7b8532 に対する CI 11 件成功（run 41296445844）、Codex Review Summary の completed / has_any_findings=false / has_unresolved_findings=false、未解決スレッド 0 件を確認した。
- `.aidlc-engine/initial-deploy-unlock.py --release` は本人が実行して成功。メタデータでロック不在を確認した。このスクリプトは初回失敗 run に固定されているため、今後の別 run のロック解除には流用しない。

## 決まっていること

- Q1: master の承認ルールは変えず、管理者としてセルフマージする。マージ前に PR の必須チェック 11 件の全成功を目で確認する。必須チェック 11 件は Branch protection に登録する。
- Q2: apply の前に whitelist と Discord の Webhook を SSM SecureString に登録する。
- Q3: マージ後、30 分以内にクライアントから接続できるときに prod を承認する。
- Q4: 最新コミットへの Codex のレビューを確認し、指摘があれば確かめて直してからマージする。

## PR #3 の状態

- 再開時の最新コミット `928790a` の CI 11 件はすべて成功（run `41293574348`）。
- 最新コミットは `4e69506`（push 済み）。復元モードの初期化が SSM Online より遅い場合の競合を修正した。boot-mode.service の同期 start を最大 180 秒待ってから、マウント・復元マーカー・コンテナ停止を検査する。SSM 文書の全体上限 1800 秒は維持し、初期化待機もこの時間に含める。
- Codex の指摘はこれまで 14 件。#12（caller identity による digest 不一致）は実際の plan の構造で再現しないことを確認し、根拠を返信してテストで固定した。#14 は `4e69506` で対処済み。最新コミットのレビュー完了・新しい指摘 0 件を確認した後、最後のスレッドも解決済みにした（スレッド 14 件すべて解決済み）。
- ローカル検証: bats 46 件（初期化遅延・失敗・待機上限の回帰 3 件を含む）、Python の CI 15 件と CD 34 件、ShellCheck、識別子検査、git diff --check が成功。追加した回帰 3 件が修正前に失敗することも確認済み。
- `4e69506` の GitHub CI 11 件はすべて成功（run `41294033988`）。Codex Review Summary の `code_review.commit_sha` が HEAD と一致し、`status=completed`、`has_any_findings=false`、`has_unresolved_findings=false` を確認した。bot の 👍 も確認済み（2026-11-01T09:41:04Z）。
- セキュリティへの影響: IAM・ネットワーク・暗号化の変更はない。初期化の失敗・時間切れでは S3 からの取得やワールド操作に進まない。ロールバックは当該修正を revert する PR と、既存の承認付き apply の手順による。

## 再開時の事前設定確認（値は取得しない）

- personal / 東京で AWS 認証に成功。
- 本人の「設定完了」を受け、master の必須チェック 11 件が登録済みであることを確認した。承認 1 件・Code Owner のレビューは必須、管理者には適用しない設定を維持。
- whitelist と discord-webhook は、東京リージョンの SSM に両方存在し、SecureString 型であることをメタデータで確認済み。パラメータの値は取得していない。
- 必須チェック名は fmt / validate / tflint / checkov / terraform-test / pytest / shellcheck / bats / identifier-check / gitleaks / plan。
- prod Environment は本人を reviewer とし、Prevent self-review は false、保護ブランチだけに限定されていることを確認済み。
- PR のレビュー対象 HEAD は 4e69506。本人の squash merge を確認済み（マージコミット 2fcb847、2026-11-01T09:57:22Z）。PR の本文は最新の検証結果と apply 前の SSM 登録順序に更新済み。
- Deploy run 41295324864 は本人承認後に apply ジョブと通知が失敗。管理 EC2 と prod state は未作成。残存していた運用ロックは解除済み。

## 次に行うこと

最新追記: f56f72aのCodexレビューはcompleted / has_any_findings=false / has_unresolved_findings=false。CI run 41306307597のtflintは一時的なGitHub APIレート制限で失敗したが、attempt 2では成功。残りのplan失敗は米国東部のCloudTrailでbudgets:ListTagsForResourceのAccessDeniedと確定した。f56f72aで修正済み。Q15で本人が最新bootstrap変更3件を適用（2026-11-01T12:35:33Z）。再planは追加0 / 変更0 / 削除0。CI run 41307007208のplanはattempt 2で成功し、f56f72aのCI 11件すべて成功、未解決スレッド0件。PRのplanは追加23 / 変更0 / 削除4（Lambda2関数とメール購読2件の再作成）。Q16で本人がマージ（2af7efa、2026-11-01T12:40:52Z）。Deploy run 41307645517はplan成功でprod承認待ち。master同一ソースの手元planも追加23 / 変更0 / 削除4で、ワールドEBSの置き換えなし。Q17で本人が承認し、run 41307645517はapply・スモークテストまで成功。EC2はrunning、Elastic IP一致、25565へのTCP接続成功、メール購読2件は確認待ちなし（2026-11-01T12:46:00Z）。接続先は.ci-private/prod-outputs.json（gitignore済み）に保存。Q18で本人がクライアントからの接続を確認し、walking skeletonの完了条件を満たした。成果物3件を作成済み。README / LICENSE / 構成図は作業ブランチ`docs/add-readme-license`で作成し未コミット。承認後にデプロイ記録とまとめて1つのPRにする。

1. 本人から「Codexのレビューがなくなるまで修正を続ける。」の指示があり、最新 HEAD のレビュー指摘 0 件・未解決スレッド 0 件・CI 11 件成功まで確認済み。以降コードを push した場合も、最新 HEAD を対象に同じ確認をする。
2. 事前設定の完了確認は済み。SSM は Name Equals を 1 件ずつ指定してメタデータを確認する（複数名をまとめた確認は失敗したため、1 件ずつ再確認済み）。
3. Q13 / Q14 / Q15の適用と今回のロック解除は完了。bootstrap差分0、最新CIのplan成功まで確認済み。ロック解除の再実行は不要。
4. `partial-deployment-recovery.md` の順に PR / CI / Codexレビューを確認する。初回用ロック解除スクリプトを今回に流用しない。prod は部分構築済みで、73aa5b3の手元planも追加23 / 削除4（tainted な Lambda とメール購読の再作成）。新しい Deploy で本人の承認を取り直す。以前の増枠申請は取り下げていないことを本人に伝える。
5. スモークテスト（mc-health-check）、メール購読の確認（2 通）、クライアントからの接続（walking skeleton の完了条件）。
6. 成果物（deployment-log.md、smoke-test-results.md、health-check-report.md）を作り、承認を求める。

## 注意

- ローカルの bats は `local/bats-host:1`（jq などを入れた手元のイメージ）で実行すると、パッケージのダウンロード待ちで止まらない。CI はそのまま `scripts/ci/check.py bats` で動く。
- Terraform は手元の版が古いので、`hashicorp/terraform:1.17.1` のコンテナで実行する。

## Sources

- https://github.com/YumaIshikawa18/game-server-infra/pull/3
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41293574348
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41294033988
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41295324864
- https://github.com/YumaIshikawa18/game-server-infra/pull/4
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41296445844
- https://github.com/YumaIshikawa18/game-server-infra/pull/4#issuecomment-6556570677
- https://github.com/YumaIshikawa18/game-server-infra/pull/3#issuecomment-6555521807
- https://github.com/YumaIshikawa18/game-server-infra/commit/4e69506b6da89d04d5c1b2ffe5e088d2979adc00
- https://www.freedesktop.org/software/systemd/man/latest/systemctl.html#--no-block
- https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-command-ssm-plugin-reference.html
