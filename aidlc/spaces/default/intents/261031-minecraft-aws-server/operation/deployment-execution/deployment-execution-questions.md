# Deployment Execution — 質問

上流: `../deployment-pipeline/cd-config.md`、`../deployment-pipeline/deployment-strategy.md`、`../deployment-pipeline/rollback-runbook.md`、`../environment-provisioning/environment-inventory.md`。infra スコープのため Build and Test の結果はなく、検証は Environment Provisioning の必須チェック 11 件と実環境の plan で代える。

## デプロイ前の確認（2026-11-01、読み取りのみ）

| 項目 | 状態 |
|---|---|
| AWS の認証（personal、東京） | 成功。アカウント `********1714` |
| PR #3 の必須チェック 11 件（最新コミット `83cca79`） | すべて成功 |
| bootstrap と実環境の差分 | 0 件 |
| GitHub の Secrets 9 件・Variables 2 件・Environments `prod` / `ops` | 設定済み |
| master の Branch protection の必須チェック | **未登録**（0 件） |
| master の承認ルール | 承認 1 件と Code Owner のレビューが必須。管理者には適用しない（バイパス可） |
| SSM の whitelist | **未登録** |
| SSM の Discord Webhook | 未登録 |
| データベースの移行 | なし（RDB を使わない） |
| 依存サービス | AWS のマネージドサービスだけ（初回なので、既存の稼働中サービスはない） |

## Q1. [リリースエンジニア] master の保護とセルフマージの方法

team.md では「必須チェックがすべて成功していれば、自分の PR をセルフマージしてよい」としている。今の master は承認 1 件と Code Owner のレビューが必須で、Code Owner は本人だけなので、自分では承認できない。管理者のバイパスでマージはできるが、バイパスは必須チェックも含めてすべてのルールを飛ばすため、チェックの強制にならない。

A. 承認数を 0 にして Code Owner のレビューを外し、必須チェック 11 件を登録して「管理者にも適用」をオンにする（推奨: team.md の取り決めどおり、チェックの成功だけがマージの条件になり、本人も飛ばせない）
B. 承認のルールは残し、必須チェック 11 件を登録して、マージは管理者のバイパスで行う（今の設定に近いが、バイパス時はチェックも強制されない）
X. Other (please specify)

[Answer]: X. 自分が管理者なので、セルフマージできる理解。（本人の言葉）→ 承認のルールは変えず、管理者のバイパスでセルフマージする。バイパスでは必須チェックも強制されないため、マージ前にチェックの全成功を目で確認する。必須チェック 11 件は結果を表示するために登録する

## Q2. [リリースエンジニア] Discord への通知

通知はメール（events の warn / error、alerts のすべて）と Discord の 2 経路の設計。Discord の Webhook が未登録のままだと、通知のたびに notifier Lambda が失敗する（メールには届く）。

A. apply の前に Discord の Webhook を SSM に登録する（推奨: 設計どおり両方に届く）
B. 当面はメールだけにする。Webhook が未登録のときは、notifier を失敗させずに「Discord は未設定」と記録して終わるよう、マージ前に変更する
X. Other (please specify)

[Answer]: A. apply の前に Discord の Webhook を SSM に登録する

## Q3. [リリースエンジニア] prod を承認するタイミング

apply すると EC2 がすぐに起動する。誰も接続しないまま 30 分たつと自動で停止する（バックアップ付き）。walking skeleton の完了条件は、Minecraft クライアントから接続できること。

A. マージ後、30 分以内にクライアントから接続できるときに prod を承認する（推奨: 起動したまま接続を確認でき、確認後は自動停止に任せられる）
B. 都合のよいときに承認する。自動停止したあとで、接続できるときに start ワークフローで起動して確認する
X. Other (please specify)

[Answer]: A. マージ後、30 分以内にクライアントから接続できるときに prod を承認する

## Q4. [リリースエンジニア] Codex のレビューとマージの順序

PR #3 には、push のたびに Codex のレビューが付き、これまでに 11 件の指摘を確認・修正した。最新コミット `83cca79` へのレビューは、まだ確認していない。

A. 最新コミットへの Codex のレビューを確認し、指摘があれば同じように確かめて直してからマージする（推奨: これまでの指摘の多くは実際の不具合だった）
B. 必須チェックが成功しているので、レビューを待たずにマージする
X. Other (please specify)

[Answer]: A. 最新コミットへの Codex のレビューを確認し、指摘があれば直してからマージする

## Sources

- `../deployment-pipeline/cd-config.md`、`deployment-strategy.md`、`rollback-runbook.md`
- `../environment-provisioning/environment-inventory.md`、`validation-report.md`
- team.md の Way of Working（セルフマージの条件）と Walking Skeleton（完了条件）
- GitHub API の読み取り（Branch protection、Secrets と Variables の名前のみ）、SSM の読み取り（パラメータの有無のみ）
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches

## Consolidated Summary Confirmation

- master の承認ルールは変えず、管理者としてセルフマージする。マージ前に PR の必須チェック 11 件の全成功を確認する（バイパスはチェックも飛ばすため）。必須チェック 11 件は Branch protection に登録する。（Q1）
- apply の前に、whitelist と Discord の Webhook を SSM SecureString に登録する。（Q2）
- 最新コミットへの Codex のレビューを確認し、指摘があれば確かめて直してからマージする。（Q4）
- マージ後に deploy.yml の plan サマリーを確認し、30 分以内にクライアントから接続できるときに prod を承認する。（Q3）
- apply 後に、スモークテスト（mc-health-check）、メール購読の確認、クライアントからの接続（walking skeleton の完了条件）を確認する。失敗したら rollback-runbook.md に従う。
- データベースの移行はない。

この内容でデプロイを進めてよいですか？

- Looks correct
- Request changes

[Answer]: Looks correct

## Q5. [運用担当] デプロイ前の設定作業の完了確認

Q1・Q2 の方針は確認済み。再開時の読み取り確認では、master の必須チェック 11 件と SSM の whitelist / discord-webhook がまだ未登録だった。前回の方針を変更する質問ではなく、本人が行う設定作業の進捗確認。

A. 設定を完了したので、値を取得せずに登録状況を再確認する
B. 登録手順の説明が必要
X. Other (please specify)

[Answer]: X. Codexのレビューがなくなるまで修正を続ける。（本人の言葉。設定完了の回答ではなく、レビュー指摘への対応を先に続ける指示）

追記: 本人から「設定完了」の回答（message 895abec5）。master の必須チェック 11 件と、whitelist / discord-webhook の存在・SecureString 型を読み取りで確認した。パラメータの値は取得していない。

## Q6. [リリースエンジニア] PR #3 のマージ完了確認

事前設定・最新コミットの CI 11 件成功・Codex の指摘 0 件を確認済み。Q1 と確認済みのデプロイ方針に従い、本人が PR #3 を管理者として squash merge する。マージ後の Deploy の plan サマリーを確認し、prod の承認は別に本人が行う。

A. PR #3 のマージが完了した
B. マージ操作でエラー・不明点がある
X. Other (please specify)

[Answer]: A. PR #3 のマージが完了した（本人の回答「1」、message c3377592）。マージコミット 2fcb847、2026-11-01T09:57:22Z を GitHub で確認。

## Q7. [リリースエンジニア] prod の承認結果

Deploy run 41295324864 はマージコミット 2fcb847 を対象に plan が成功し、prod の本人承認待ち。本人が Summary の plan 件数・対象を確認する。PR の確認済み plan は追加 81 / 変更 0 / 削除 0。今回の Deploy の件数は API で取得できていないため、PR の件数を今回の結果として扱わない。クライアント接続を確認できるときに Review deployments から prod を選び、Approve and deploy を行う。

A. plan を確認し、prod を承認した
B. plan が想定と異なる、または承認操作に不明点がある
X. Other (please specify)

[Answer]: A. plan を確認し、prod を承認した（本人の回答「1」、message eaa9b3b0）。承認後の apply ジョブは失敗。原因の再現と修正は initial-deployment-failure.md に記録。

## Q8. [運用担当] bootstrap の権限反映と初回の残存ロック解除

PR #4（f7b8532）は CI 11 件成功、最新コミットの Codex レビュー指摘 0 件・未解決スレッド 0 件。本人がローカルから適用する bootstrap の plan は追加 0 / 変更 2 / 削除 0 で、apply / ops に専用ロック 1 キーの GetObject を追加する。レビュー済み plan と現在のソースの一致も確認済み。

初回失敗 run 専用の解除スクリプトは --check が成功。失敗 run 終了、進行中の Deploy / Start / Stop / Restore なし、管理 EC2・prod state・state ロックなし、対象ロック所有者一致を確認する。--release でも毎回同じ検査を行い、最後に ETag の一致条件付きで対象ロックだけを解除する。無条件削除はしない。まだ解除は実行していない。

本人が次の 2 コマンドを順に実行する。

```bash
python3 -m scripts.local.terraform apply
python3 aidlc/spaces/default/intents/261031-minecraft-aws-server/.aidlc-engine/initial-deploy-unlock.py --release
```

A. 2 コマンドとも完了した
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. 2 コマンドとも完了した（本人が両コマンドを実行し Exit code 0、その後「1」、message afaa4a71）。bootstrap の再 plan は追加 0 / 変更 0 / 削除 0、運用ロックは head-object の 404 で不在を確認した。

## Q9. [リリースエンジニア] 修正 PR のマージと新しい Deploy の承認

PR #4 の最新コミット f7b8532 は CI 11 件成功・Codex の指摘 0 件。bootstrap の反映と残存ロック解除も完了。本人が PR #4 を squash merge し、そのマージから始まる新しい Deploy の Summary を確認してから prod を承認する。PR で確認した想定は追加 81 / 変更 0 / 削除 0。古い失敗 run の承認は使い回さない。

A. PR #4 をマージし、新しい Deploy の plan を確認して prod を承認した
B. マージ・plan・承認でエラーや不明点がある
X. Other (please specify)

[Answer]: A. PR #4 をマージし、新しい Deploy の plan を確認して prod を承認した（本人の回答「1」、message 53b9aac0）。マージコミット 909a373、Deploy run 41296893187 を確認。plan 成功後の apply はリソース作成中に失敗し、失敗通知は成功した。部分的に作成されたリソースと state、運用ロックを保持して復旧準備を進める。

## Q10. [運用担当] Lambda 同時実行上限の引き上げ申請

東京リージョンの Lambda 上限は10、未予約枠も10で、watchdog / notifier の予約同時実行数1の設定が拒否された。設計の制限を維持するため、Service Quotas の Concurrent executions（L-B99A9384）を1,000へ引き上げ申請する。申請に対するAWSの承認・反映は別途必要で、完了時期は未確定。予約枠の設定自体には追加料金は発生しない。権限・SSM の修正と検証は準備済みで、詳細は partial-deployment-recovery.md。

A. Codex が personal / 東京で上限1,000への引き上げを申請する（推奨: 現在の予約同時実行数1を維持して復旧できる）
B. 本人が AWS コンソールから同じ上限引き上げを申請する
X. Other (please specify)

[Answer]: A. Codex が personal / 東京で上限1,000への引き上げを申請する（本人の回答「1」、message 1b7a54a9）。

申請結果: 2026-11-01T11:47:17Zに受付。PENDINGからCASE_OPENEDへ進行した。上限の反映は未確認で、予約同時実行数1の設定は維持している。

## Q11. [運用担当] bootstrap の権限修正5件の適用結果

Lambdaの上限引き上げはAWSの審査待ち。並行して、既決の本人によるローカルbootstrap適用を行う。2026-11-01T11:48:42Z時点で生成し直したplanは追加0 / 変更5 / 削除0。変更対象はapplyのcompute / storage / services / readsとplanのinline policy。EC2の親リソース認可、バックアップバケットのタグ権限、SNS購読の認可を修正する。Access Analyzerでポリシー文書9件にエラーなし。既存警告2件は維持。対象外のリソースを許可しないIAMシミュレーション33件も成功済み。詳細はpartial-deployment-recovery.md。

適用用コマンドは保存済みplanとソース・アカウントの一致を検査し、識別子を出力しない。本人がプロジェクトルートから実行する。

```bash
python3 -m scripts.local.terraform apply
```

A. コマンドの適用が完了した
B. 実行時のエラーや不明点がある
X. Other (please specify)

[Answer]: A. コマンドの適用が完了した（本人が実行しExit code 0、その後「1」、message 5c221b33）。

## Q12. [運用担当] Lambda の予約同時実行数を使うか

本人から「では上げる必要無かったのではと思った。」と質問があった。予約同時実行数1は要件ファイルにはなく、infrastructure-specification.mdで採用した設計値である。watchdogは5分ごと・実行上限30秒、notifierはSNS通知をDiscordへ送る処理で、ワールドを書き換えない。上限1,000は処理量から必要とされた値ではない。

共有枠へ変更すれば上限引き上げをデプロイ条件から外せるが、各関数を同時1実行に制限する設定はなくなる。複数の通知が並行してDiscordへ送られ得る。現行コードには429の再試行があるが、全体の送信直列化はしない。変更する場合は2モジュール、Terraformテスト、設計・復旧記録とCheckovの同時実行制限チェックへの対応を見直し、最新HEADのCI・レビューを確認する。申請の取り消し可否は別途確認する。

A. 予約枠を使わず、現在の上限10の共有枠を使う構成へ変更する
B. 各関数の予約同時実行数1を維持し、申請した上限引き上げを待つ
X. Other (please specify)

[Answer]: A. 予約枠を使わず、現在の上限10の共有枠を使う構成へ変更する（本人の回答「1」、message 5507c16f）。

実装結果: PR #5の73aa5b3で2関数の予約枠を外し、設計・テストとCKV_AWS_115の個別例外を更新。最新HEADのCodexレビューはcompleted / 指摘なし。以前の上限1,000への申請はCASE_OPENEDのままで、取り下げやAWSサポートへの連絡は行っていない。

## Q13. [運用担当] 追加読み取り権限の適用と今回の残存ロック解除

旧CI run 41303713973のplan失敗は、作成済みリソースのs3:ListTagsForResourceとlambda:ListVersionsByFunctionの読み取り不足とCloudTrailで確認した。修正は対象のバックアップバケットとプロジェクト関数に限定し、bootstrapのplanは追加0 / 変更3 / 削除0（applyのreads / storage、planのinline policy）。Access Analyzerにエラーなし、IAMシミュレーション43件成功。保存済みplanとソースの一致も確認済み。本人が最初のコマンドで適用する。

2番目のコマンドはrun 41296893187専用。失敗runの終了・他の運用不在・管理EC2不在・ワールドEBS未接続・進行中SSM不在・部分state存在・stateロック不在・運用ロック所有者一致を再検査し、ETagが一致する専用ロックだけを解除する。--checkは成功し、AWSをmockした安全条件のテストも成功。今回の解除は未実行。実行中は新しいDeploy / Start / Stop / Restoreや手元のprod変更を開始しない。

本人がプロジェクトルートで順に実行する。

```bash
python3 -m scripts.local.terraform apply
python3 aidlc/spaces/default/intents/261031-minecraft-aws-server/.aidlc-engine/partial-deploy-unlock.py --release
```

A. 2コマンドとも完了した
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. 2コマンドとも完了した（本人が両コマンドを実行しExit code 0、その後「1」、message d2f7fff8）。

確認結果: bootstrap再planは差分0件、運用ロックはhead-object 404で不在、部分stateは保持。CI run 41304519371 attempt 2では次のLambda署名設定参照がAccessDeniedになったため、Q14の修正を追加した。

## Q14. [運用担当] Lambda 署名設定の読み取り権限の適用結果

CloudTrailでci-planのlambda:GetFunctionCodeSigningConfigが拒否されていた。AWS provider 6.71.0のLambda読み取り全体を公式実装で確認し、署名を使っていないzip関数でも最後にこのAPIを呼ぶことを確認した。PR #5の37ed02aでplan / applyの対象関数だけにこの読み取りを追加し、署名設定を変更する権限は加えていない。

bootstrapの保存済みplanは追加0 / 変更2 / 削除0（applyのreads、planのinline policy）。修正前のテスト失敗と修正後11件成功、IAMシミュレーション47件成功、Access Analyzerのエラー0件を確認。保存済みplanとソースの一致も確認した。最新HEADのCodexレビューはcompleted / has_any_findings=false / has_unresolved_findings=false。

本人がプロジェクトルートで次を実行する。運用ロックは解除済みなので、解除スクリプトの再実行は不要。

```bash
python3 -m scripts.local.terraform apply
```

A. 適用が完了した
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. 適用が完了した（本人がコマンドを実行しExit code 0、その後「1」、message 7b64b8aa）。

確認結果: bootstrapの再planは差分0件、運用ロックは不在。その後のCI plan失敗は、Budgetsのタグ読み取りの拒否として米国東部のCloudTrailに記録されていた。Q15の修正を追加した。

## Q15. [運用担当] Budgets タグ読み取りと SG ルール作成の権限修正を適用する

PR #5のf56f72aで、次の2点をまとめて修正した。

- planで既存の予算を読むためのbudgets:ListTagsForResource。対象はプロジェクトの予算だけ。東京側ではなく米国東部のCloudTrailでAccessDeniedを確認した。
- 次のapplyで作るタグ付きSGルールの認可。現在のロールで作成時CreateTagsが拒否されることをシミュレーションで確認した。親SGの既存Projectタグ、新しいルールのRequestTagを分離し、CreateTagsは同じProjectのingress / egress作成時だけに限定した。ポートやネットワーク設定は変更しない。

保存済みbootstrap planは追加0 / 変更3 / 削除0（applyのcompute / reads、planのinline policy）。保存済みplanとソースの一致、Terraformテスト12件、Python CI23件 / CD38件、IAMシミュレーション70件成功を確認。Access Analyzerはエラー0・既存警告2件。最新HEADのCodexレビューはcompleted / has_any_findings=false / has_unresolved_findings=false。

本人がプロジェクトルートで次を実行する。運用ロックは解除済みなので、解除スクリプトの再実行は不要。

```bash
python3 -m scripts.local.terraform apply
```

A. 適用が完了した
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. 適用が完了した（本人が「python3 -m scripts.local.terraform applyを打ったところ」と回答、message cc28675a。21:35:33 JSTに出力ファイルが更新され、保存済みplanの削除まで進み、失敗時の診断ログなしを確認）。

確認結果: bootstrap再planは差分0件。CI run 41307007208のplanはattempt 2で成功し、f56f72aのCI 11件すべて成功。Codexレビューはcompleted / has_any_findings=false / has_unresolved_findings=false、未解決スレッド0件。

## Q16. [運用担当] PR #5 をマージする

PR #5（f56f72a）の必須チェック11件の成功、Codexレビューの指摘なし、未解決スレッド0件を確認した。PRのprod planは追加23 / 変更0 / 削除4で、削除4件はLambda2関数とメール購読2件の再作成。Q1のとおり、本人が管理者としてsquash mergeする。prodの承認はまだ行わず、新しいDeployのplanを確認した後に依頼する。

A. マージした
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. マージした（本人の回答「マージした」、message 3a3f123d）。

確認結果: PR #5はマージ済み（2af7efa）。Deploy run 41307645517のplanは成功し、prod承認待ち。

## Q17. [運用担当] prod の Deploy を承認する

masterと同一ソースの手元planは追加23 / 変更0 / 削除4。削除4件はLambda2関数とメール購読2件の再作成で、ワールドEBSの置き換えはない。Q3のとおり、30分以内にクライアントから接続できるときに本人が承認する。

- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41307645517

A. 承認した
B. エラー・不明点がある
X. Other (please specify)

[Answer]: A. 承認した（本人の回答、message dffe5be8）。

確認結果: Deploy run 41307645517はapply・スモークテストまで成功。EC2はrunning、Elastic IP一致、25565へのTCP接続成功。メール購読2件は確認待ちなし。

## Q18. [運用担当] Minecraft クライアントから接続する

walking skeletonの完了条件はクライアントからの接続で、TCP接続の成功だけでは完了としない。接続先は値を公開しないよう、本人が手元の非公開ファイルから確認する。

A. 接続できた
B. 接続できない・不明点がある
X. Other (please specify)

[Answer]: A. 接続できた（本人の回答「1 で接続できた。」、message c4d9dd1d）。
