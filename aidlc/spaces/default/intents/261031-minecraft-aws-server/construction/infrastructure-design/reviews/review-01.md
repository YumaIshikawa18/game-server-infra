## Review

**Verdict:** NOT-READY
**Reviewer:** aidlc-architecture-reviewer-agent
**Date:** 2026-10-31T17:37:30Z
**Iteration:** 1
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Critical | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services > Amazon SNS（SSE `alias/aws/sns`）と AWS Budgets / Amazon CloudWatch の行 | 通知トピックを AWS マネージドキー `alias/aws/sns` で暗号化する設計です。このキーはキーポリシーを変更できないため、CloudWatch アラームと AWS Budgets はこのトピックに Publish できません（AWS 公式ドキュメントでは、暗号化トピックにアラームを送るにはカスタマーマネージドキーが必要とされています。実装前に要確認）。その結果、`mc-backup-failed`・`mc-disk-high`・`mc-backup-bucket-large` と予算 80% / 100% の通知が、黙って届かなくなるおそれがあります。月額 3,000 円という余裕の少ない予算（NFR1.1）の唯一の安全網である Budgets 通知（FR9.1）も含まれます。トピックポリシー（`cloudwatch.amazonaws.com` と `budgets.amazonaws.com` に Publish を許可）も、どの成果物にも書かれていません。 | SNS の暗号化方式を決め直してください。選択肢は、(a) カスタマーマネージドキーを使い、キーポリシーで CloudWatch・Budgets・EC2 ロール・Lambda ロールからの利用を許可する、(b) 暗号化を外す、のどちらかです。あわせてトピックポリシー（アラーム・Budgets からの Publish 許可）を infrastructure-specification に追記し、KMS 追加によるコストを見積もってください。 | New |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/monitoring-design.md > Alerts（`mc-backup-failed` ほか、予算の各行の Routes to 「Discord ＋ メール」）と infrastructure-specification.md > Amazon SNS（メール購読のフィルタ） | メール購読は、メッセージ属性 `severity` が warn / error のものだけを通すフィルタです。しかし CloudWatch アラームと Budgets が送る SNS メッセージには、カスタム属性 `severity` が付きません（本文も独自 JSON ではありません）。そのため、メール購読にはアラームと予算の通知が届かず、表の「Discord ＋ メール」と食い違います。「notifier Lambda が壊れてもメールには届く」という冗長化の前提（NFR4.11）は、アラームと予算の経路では成り立ちません。notifier が severity をどう決めるかも書かれていません。 | フィルタを `FilterPolicyScope` で本文に対して掛けるのか、アラームと予算にはフィルタを掛けず別の購読にするのか、アラーム・Budgets 用の別トピックを設けるのかを決め、表に反映してください。アラーム・Budgets 由来のメッセージの severity を、誰がどう決めるか（アラーム名や Budgets 通知種別との対応表）も記載してください。 | New |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 4. deploy.yml（apply の流れ）の手順 1〜2 | `prod` の承認（手順 1）が `terraform plan`（手順 2）より前にあります。承認者は、今回の run で実際に apply される差分を見ないまま承認することになります。PR 時点の plan とマージ後の plan の間には、他のマージやドリフトによる差が出得ます。さらに、置き換えの保護（手順 3）は承認後に動くため、承認者は EC2 の置き換えや EBS 等の削除を知らずに承認し得ます。チーム規約の「承認付き apply」の趣旨（NFR5.2 の最小権限での人手の判断）を満たしていません。 | plan ジョブを承認の前に置き、サマリー（件数とアドレスのみ）を Job Summary に出したうえで、承認後に保存済みの plan を apply する構成にしてください。push 時の plan ジョブで使う OIDC ロールとその trust（`ci-plan` に push 用の sub を足すか別ロールか）も、security-design §2 の追記事項として明記してください。 | New |
| R-04 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 2. 共通の方針「排他」 | `deploy` / `start` / `stop` / `restore` が同じ `concurrency` グループを共有しています。`prod` の承認待ちの deploy run がグループを占有すると、手動の `stop.yml`（課金の停止手段）が待たされるおそれがあります。また GitHub の concurrency は、実行中 1 件と待機 1 件までしか保持せず、それ以上の待機 run は `cancel-in-progress: false` でも取り消されます。 | apply ジョブだけに concurrency を掛ける（承認後に取得する）か、`stop.yml` を別グループにするかを決めて明記してください。待機 run が取り消される挙動も、運用手順（README）に書いてください。 | New |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services 全体 | この設計で追加された SNS の暗号化キー、アラーム数、CloudWatch Logs、S3 の `deploy/` 配布などを含めた月額の再計算がありません。上流の見積もり（約 2,600〜2,750 円、予算 3,000 円に対し余裕は約 250〜400 円）は余裕が小さく、変更の影響を確認できません。 | 追加分を含めた月額の見積もり表を、infrastructure-specification に追記するか、scalability-requirements の見積もりとの差分として記載してください。 | New |

### Validation Tool Results

| Tool | Result | Interpretation |
|---|---|---|
| aidlc engine sensor-traceability --stage infrastructure-design | pass: true、gaps / orphans / invalid_entries すべて空 | NFR の対応づけは構造上問題ありません。上記の指摘は、対応づけ先の設計内容そのものの妥当性に関するものです。 |

### Summary

NFR の対応づけは機械チェックを通っていますが、SNS を `alias/aws/sns` で暗号化する設計のままでは、CloudWatch アラームと Budgets の通知が届かないおそれがあります（Critical）。加えて、メールのフィルタ設計と、承認前に plan が見えない deploy 手順に Major が 2 件あり、実装前に決め直す必要があります。
