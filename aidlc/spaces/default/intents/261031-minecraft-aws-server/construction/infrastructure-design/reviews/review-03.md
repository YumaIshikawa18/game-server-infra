## Review

**Verdict:** READY
**Reviewer:** aidlc-architecture-reviewer-agent
**Date:** 2026-10-31T17:44:28Z
**Iteration:** 3
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Critical | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services > Amazon SNS（SSE `alias/aws/sns`）と AWS Budgets / Amazon CloudWatch の行 | 通知トピックを AWS マネージドキー `alias/aws/sns` で暗号化する設計です。このキーはキーポリシーを変更できないため、CloudWatch アラームと AWS Budgets はこのトピックに Publish できません（AWS 公式ドキュメントでは、暗号化トピックにアラームを送るにはカスタマーマネージドキーが必要とされています。実装前に要確認）。その結果、`mc-backup-failed`・`mc-disk-high`・`mc-backup-bucket-large` と予算 80% / 100% の通知が、黙って届かなくなるおそれがあります。月額 3,000 円という余裕の少ない予算（NFR1.1）の唯一の安全網である Budgets 通知（FR9.1）も含まれます。トピックポリシー（`cloudwatch.amazonaws.com` と `budgets.amazonaws.com` に Publish を許可）も、どの成果物にも書かれていません。 | SNS の暗号化方式を決め直してください。選択肢は、(a) カスタマーマネージドキーを使い、キーポリシーで CloudWatch・Budgets・EC2 ロール・Lambda ロールからの利用を許可する、(b) 暗号化を外す、のどちらかです。あわせてトピックポリシー（アラーム・Budgets からの Publish 許可）を infrastructure-specification に追記し、KMS 追加によるコストを見積もってください。 | Resolved (reviewer) |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/monitoring-design.md > Alerts（`mc-backup-failed` ほか、予算の各行の Routes to 「Discord ＋ メール」）と infrastructure-specification.md > Amazon SNS（メール購読のフィルタ） | メール購読は、メッセージ属性 `severity` が warn / error のものだけを通すフィルタです。しかし CloudWatch アラームと Budgets が送る SNS メッセージには、カスタム属性 `severity` が付きません（本文も独自 JSON ではありません）。そのため、メール購読にはアラームと予算の通知が届かず、表の「Discord ＋ メール」と食い違います。「notifier Lambda が壊れてもメールには届く」という冗長化の前提（NFR4.11）は、アラームと予算の経路では成り立ちません。notifier が severity をどう決めるかも書かれていません。 | フィルタを `FilterPolicyScope` で本文に対して掛けるのか、アラームと予算にはフィルタを掛けず別の購読にするのか、アラーム・Budgets 用の別トピックを設けるのかを決め、表に反映してください。アラーム・Budgets 由来のメッセージの severity を、誰がどう決めるか（アラーム名や Budgets 通知種別との対応表）も記載してください。 | Resolved (reviewer) |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 4. deploy.yml（apply の流れ）の手順 1〜2 | `prod` の承認（手順 1）が `terraform plan`（手順 2）より前にあります。承認者は、今回の run で実際に apply される差分を見ないまま承認することになります。PR 時点の plan とマージ後の plan の間には、他のマージやドリフトによる差が出得ます。さらに、置き換えの保護（手順 3）は承認後に動くため、承認者は EC2 の置き換えや EBS 等の削除を知らずに承認し得ます。チーム規約の「承認付き apply」の趣旨（NFR5.2 の最小権限での人手の判断）を満たしていません。 | plan ジョブを承認の前に置き、サマリー（件数とアドレスのみ）を Job Summary に出したうえで、承認後に保存済みの plan を apply する構成にしてください。push 時の plan ジョブで使う OIDC ロールとその trust（`ci-plan` に push 用の sub を足すか別ロールか）も、security-design §2 の追記事項として明記してください。 | Resolved (reviewer) |
| R-04 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > 2. 共通の方針「排他」 | `deploy` / `start` / `stop` / `restore` が同じ `concurrency` グループを共有しています。`prod` の承認待ちの deploy run がグループを占有すると、手動の `stop.yml`（課金の停止手段）が待たされるおそれがあります。また GitHub の concurrency は、実行中 1 件と待機 1 件までしか保持せず、それ以上の待機 run は `cancel-in-progress: false` でも取り消されます。 | apply ジョブだけに concurrency を掛ける（承認後に取得する）か、`stop.yml` を別グループにするかを決めて明記してください。待機 run が取り消される挙動も、運用手順（README）に書いてください。 | Resolved (reviewer) |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > Infrastructure Services 全体 | この設計で追加された SNS の暗号化キー、アラーム数、CloudWatch Logs、S3 の `deploy/` 配布などを含めた月額の再計算がありません。上流の見積もり（約 2,600〜2,750 円、予算 3,000 円に対し余裕は約 250〜400 円）は余裕が小さく、変更の影響を確認できません。 | 追加分を含めた月額の見積もり表を、infrastructure-specification に追記するか、scalability-requirements の見積もりとの差分として記載してください。 | Resolved (reviewer) |
| R-06 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/cicd-pipeline.md > §2 共通の方針 > 排他 | apply ジョブの concurrency は「承認後に取得」と書かれていますが、GitHub Actions がジョブ単位の concurrency を環境承認の前後どちらで評価するかは、この設計では裏づけられていません。承認前に取得される実装だと、承認待ちの apply が `minecraft-prod` を占有し、stop.yml が待たされる元の問題が残ると思われます（要確認）。 | 公式ドキュメントで挙動を確認し、承認前に取得されるなら、stop.yml を別グループにするか、承認待ちを concurrency の外に出す構成にします。確認できない間は、この前提を README の注意書きにも残します。 | Resolved (reviewer) |
| R-07 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > 月額コストの再計算 | 「CloudWatch アラーム 3 個」の行は、上流の見積もりでは「約 100 円に含む」とされつつ、差分として約 45 円が再度加算されています。合計の下限（約 2,550 円）も項目の足し算（約 2,535 円）とずれています。二重計上かどうかが読み取れません。 | 上流の約 100 円の内訳にアラームが含まれるなら、差分は 0 円と書くか、含まれないなら「含む」の記載を外します。合計も項目の足し算に合わせます。 | Resolved (reviewer) |
| R-08 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > 月額コストの再計算（表の冒頭） | 表の見出し行が 2 本重なっています（「この設計での差分」と「この設計での月額」）。区切り行が 2 回あり、Markdown では 2 本目の見出しがデータ行として描画されます。 | 見出し行と区切り行を 1 組に整理し、列名を「この設計での月額」に統一してください。 | New |
| R-09 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/infrastructure-design/infrastructure-specification.md > 月額コストの再計算 > カスタムメトリクス 7 本 | $0.30 × 7 × 40/730 × 150 円 は約 17 円で、表の「約 10 円」と合いません。差は小さく、合計範囲の余裕（190 円以上）には影響しませんが、CloudWatch Agent の disk メトリクスはディメンションの組ごとに別メトリクスになる可能性があります（要確認）。 | 金額を約 17 円に直すか、算出の前提を注記してください。合計は下限約 2,542 円、上限約 2,817 円となり、予算内に収まります。 | New |

> R-06 Reviewer note: cicd-pipeline.md §2 で start/stop/restore を `minecraft-ops`、deploy の apply を `minecraft-prod` に分離しました。concurrency を承認の前後どちらで取得しても stop が承認待ちの deploy に待たされない構成で、懸念は解消しています。3 件目で待機中 run が取り消される挙動と再実行手順も README に書く方針です。

> R-07 Reviewer note: アラーム費は 3 行（アラーム 3 個 約 45 円、メトリクス 7 本、Logs）に分解され、二重計上は解消しました。合計も足し算（下限 2,480+45+10+0=2,535、上限 2,630+45+10+115+10=2,810）と一致し、余裕 190〜465 円も整合しています。

### Validation Tool Results

| Tool | Result | Interpretation |
|---|---|---|
| sensor-traceability (infrastructure-design) | PASS: gaps 0、orphans 0、invalid 0 | トレーサビリティに問題はありません。 |

### Summary

前回の Minor 2 件（concurrency の分離とコスト表の二重計上）は解消しており、SNS 非暗号化の判断も理由付きで記載されています。残るのはコスト表の体裁とメトリクス費の端数のみで、いずれもブロックしません。
