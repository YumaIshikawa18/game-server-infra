## Review

**Verdict:** READY
**Reviewer:** aidlc-architecture-reviewer-agent
**Date:** 2026-10-31T17:40:14Z
**Iteration:** 2
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Critical | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services > Amazon SNS（SSE `alias/aws/sns`）と AWS Budgets / Amazon CloudWatch の行 | 通知トピックを AWS マネージドキー `alias/aws/sns` で暗号化する設計です。このキーはキーポリシーを変更できないため、CloudWatch アラームと AWS Budgets はこのトピックに Publish できません（AWS 公式ドキュメントでは、暗号化トピックにアラームを送るにはカスタマーマネージドキーが必要とされています。実装前に要確認）。その結果、`mc-backup-failed`・`mc-disk-high`・`mc-backup-bucket-large` と予算 80% / 100% の通知が、黙って届かなくなるおそれがあります。月額 3,000 円という余裕の少ない予算（NFR1.1）の唯一の安全網である Budgets 通知（FR9.1）も含まれます。トピックポリシー（`cloudwatch.amazonaws.com` と `budgets.amazonaws.com` に Publish を許可）も、どの成果物にも書かれていません。 | SNS の暗号化方式を決め直してください。選択肢は、(a) カスタマーマネージドキーを使い、キーポリシーで CloudWatch・Budgets・EC2 ロール・Lambda ロールからの利用を許可する、(b) 暗号化を外す、のどちらかです。あわせてトピックポリシー（アラーム・Budgets からの Publish 許可）を infrastructure-specification に追記し、KMS 追加によるコストを見積もってください。 | Resolved (reviewer) |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/monitoring-design.md > Alerts（`mc-backup-failed` ほか、予算の各行の Routes to 「Discord ＋ メール」）と infrastructure-specification.md > Amazon SNS（メール購読のフィルタ） | メール購読は、メッセージ属性 `severity` が warn / error のものだけを通すフィルタです。しかし CloudWatch アラームと Budgets が送る SNS メッセージには、カスタム属性 `severity` が付きません（本文も独自 JSON ではありません）。そのため、メール購読にはアラームと予算の通知が届かず、表の「Discord ＋ メール」と食い違います。「notifier Lambda が壊れてもメールには届く」という冗長化の前提（NFR4.11）は、アラームと予算の経路では成り立ちません。notifier が severity をどう決めるかも書かれていません。 | フィルタを `FilterPolicyScope` で本文に対して掛けるのか、アラームと予算にはフィルタを掛けず別の購読にするのか、アラーム・Budgets 用の別トピックを設けるのかを決め、表に反映してください。アラーム・Budgets 由来のメッセージの severity を、誰がどう決めるか（アラーム名や Budgets 通知種別との対応表）も記載してください。 | Resolved (reviewer) |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 4. deploy.yml（apply の流れ）の手順 1〜2 | `prod` の承認（手順 1）が `terraform plan`（手順 2）より前にあります。承認者は、今回の run で実際に apply される差分を見ないまま承認することになります。PR 時点の plan とマージ後の plan の間には、他のマージやドリフトによる差が出得ます。さらに、置き換えの保護（手順 3）は承認後に動くため、承認者は EC2 の置き換えや EBS 等の削除を知らずに承認し得ます。チーム規約の「承認付き apply」の趣旨（NFR5.2 の最小権限での人手の判断）を満たしていません。 | plan ジョブを承認の前に置き、サマリー（件数とアドレスのみ）を Job Summary に出したうえで、承認後に保存済みの plan を apply する構成にしてください。push 時の plan ジョブで使う OIDC ロールとその trust（`ci-plan` に push 用の sub を足すか別ロールか）も、security-design §2 の追記事項として明記してください。 | Resolved (reviewer) |
| R-04 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 2. 共通の方針「排他」 | `deploy` / `start` / `stop` / `restore` が同じ `concurrency` グループを共有しています。`prod` の承認待ちの deploy run がグループを占有すると、手動の `stop.yml`（課金の停止手段）が待たされるおそれがあります。また GitHub の concurrency は、実行中 1 件と待機 1 件までしか保持せず、それ以上の待機 run は `cancel-in-progress: false` でも取り消されます。 | apply ジョブだけに concurrency を掛ける（承認後に取得する）か、`stop.yml` を別グループにするかを決めて明記してください。待機 run が取り消される挙動も、運用手順（README）に書いてください。 | Resolved (reviewer) |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services 全体 | この設計で追加された SNS の暗号化キー、アラーム数、CloudWatch Logs、S3 の `deploy/` 配布などを含めた月額の再計算がありません。上流の見積もり（約 2,600〜2,750 円、予算 3,000 円に対し余裕は約 250〜400 円）は余裕が小さく、変更の影響を確認できません。 | 追加分を含めた月額の見積もり表を、infrastructure-specification に追記するか、scalability-requirements の見積もりとの差分として記載してください。 | Resolved (reviewer) |
| R-06 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > §2 共通の方針 > 排他 | apply ジョブの concurrency は「承認後に取得」と書かれていますが、GitHub Actions がジョブ単位の concurrency を環境承認の前後どちらで評価するかは、この設計では裏づけられていません。承認前に取得される実装だと、承認待ちの apply が `minecraft-prod` を占有し、stop.yml が待たされる元の問題が残ると思われます（要確認）。 | 公式ドキュメントで挙動を確認し、承認前に取得されるなら、stop.yml を別グループにするか、承認待ちを concurrency の外に出す構成にします。確認できない間は、この前提を README の注意書きにも残します。 | New |
| R-07 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > 月額コストの再計算 | 「CloudWatch アラーム 3 個」の行は、上流の見積もりでは「約 100 円に含む」とされつつ、差分として約 45 円が再度加算されています。合計の下限（約 2,550 円）も項目の足し算（約 2,535 円）とずれています。二重計上かどうかが読み取れません。 | 上流の約 100 円の内訳にアラームが含まれるなら、差分は 0 円と書くか、含まれないなら「含む」の記載を外します。合計も項目の足し算に合わせます。 | New |

> R-01 Reviewer note: SNS は両トピックとも SSE なしに決め直され、CMK が要る理由と月 $1 のコストが理由として書かれました。`alerts` のトピックポリシーは `cloudwatch.amazonaws.com` と `budgets.amazonaws.com` を `aws:SourceAccount` 条件で許可し、`events` は 4 つのロールに限っています。CKV_AWS_26 は理由付きで抑止され、承認前に本人へ確認する旨も Assumptions にあります。

> R-02 Reviewer note: トピックを `events`（属性 `severity` の購読フィルタをメールに適用）と `alerts`（フィルタなし）に分割しました。monitoring-design.md の「通知の経路と severity の決め方」で、アラームは名前、Budgets は閾値から notifier が severity を決めると明記されており、「Discord ＋ メール」と矛盾しません。形の判別不能なメッセージも warn として落とさない扱いです。

> R-03 Reviewer note: plan を承認前の独立ジョブに置き、Job Summary に件数・アドレス・置き換え警告を出します。承認後に ci-apply で同一コミットを再 plan し、`resource_changes` の（アドレス, actions）の sha256 が一致しなければ失敗させます。plan ファイルを artifact にしない理由（public リポジトリでは誰でもダウンロードでき、値が平文で入る）は妥当です。承認者が見る情報（アドレスと actions）と照合対象が同じなので、承認した内容と違う変更を適用しない、という意図は満たされています。push 時の `ci-plan` の trust 追加も明記されています。

> R-04 Reviewer note: concurrency は AWS を変更するジョブだけに掛ける方針になり、承認待ちの deploy に stop.yml が巻き込まれない設計になりました。待機 1 件までで 3 件目に取り消される挙動と再実行手順を README に書く旨もあります。ただし、承認待ちが concurrency を占有するかどうかについては下の新規指摘を参照してください。

> R-05 Reviewer note: 「月額コストの再計算」表が追加され、約 2,550〜2,800 円（予算 3,000 円以内）と示されました。

### Validation Tool Results

| Tool | Result | Interpretation |
|---|---|---|
| sensor-traceability | 未実行（artifact の読み取りレビューのみ） | 構造検査はこの review では行っていません。上記は内容の整合の確認です。 |

### Summary

iteration 1 の指摘 R-01〜R-05 はすべて解消されており、承認前 plan とダイジェスト照合の方式も R-03 の意図を満たします。残るのは concurrency の評価タイミングの確認とコスト表の二重計上という Minor 2 件のみで、実装の判断を妨げません。
