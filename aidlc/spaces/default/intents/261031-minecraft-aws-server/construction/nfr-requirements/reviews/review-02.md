## Review

**Verdict:** READY
**Reviewer:** aidlc-architecture-reviewer-agent
**Date:** 2026-10-31T17:10:38Z
**Iteration:** 2
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.2（および tech-stack-decisions.md > 選定一覧「起動・停止・復元の操作」） | NFR5.2 は IAM ロールを「plan 用」と「apply / 操作用」の 2 つにし、後者の trust を `environment:prod` に限定しています。一方 tech-stack-decisions.md は start / stop / restore の `workflow_dispatch` が「OIDC の操作用ロール」で EC2 と SSM Run Command を呼ぶとしています。GitHub の Environment `prod` には手動承認があるため（requirements.md FR7.2）、この 2 つを同時に満たすと、start / stop / restore のたびに承認待ちが入ります。承認待ちの時間は start ワークフローの所要時間に含まれ、NFR3.1（10 分以内、判定は start ワークフローの所要時間）を満たせなくなります。また、terraform apply と start / stop が同じロールに同居すると、日常操作に apply 相当の強い権限を渡すことになります。 | ロールを 3 つに分けるか、操作用ロールの trust 条件を別に定めてください。(1) plan 用、(2) apply 用（`environment:prod`、承認あり）、(3) 運用操作用（start / stop / restore。EC2 の起動・停止と SSM Run Command だけを許可し、承認なしの別 Environment または別の sub 条件にする）。どのワークフローがどのロールを使うかを表にして追記し、NFR3.1 の計測が承認待ちを含まないことも明記してください。 | Resolved (reviewer) |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.2 / NFR5.4 / NFR5.11（apply 用ロールの権限） | apply 用ロールは、このリポジトリで最も強い権限（EC2、IAM、S3、SNS、Lambda、Budgets、CloudWatch、SSM などを作成・変更）を持つのに、要件は trust policy の `sub` / `aud` の制限だけです。NFR5.4 の「ワイルドカードを使わない」は EC2 インスタンスロール向けで、apply 用ロールの権限範囲、IAM 昇格の防止（permissions boundary や `iam:PassRole` の対象制限）、このロールを bootstrap と envs/prod のどちらで作るか（自分で自分の権限を広げられないか）が定義されていません。開発者は権限範囲を推測して決めるしかありません。 | apply 用ロールの要件を追加してください。(1) 操作できるサービスとリソースの範囲（名前プレフィックスやタグ条件）、(2) permissions boundary の有無と、`iam:CreateRole` / `iam:PassRole` の対象制限、(3) ロールと OIDC プロバイダーは bootstrap（手元で 1 回だけ apply）で作り、CI からは変更できないこと。合否基準は `terraform test` と Checkov で検証できる形にしてください。 | Resolved (reviewer) |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/observability-requirements.md > 「アラームと通知」の注記（`notBreaching`）、NFR7.1、NFR7.9（および reliability-requirements.md > NFR4.9） | 停止中は `ServerUp` を送らないため欠測を `notBreaching`（正常扱い）にする、と定めています。この設定では、稼働中にサーバー側スクリプト自体が止まる、またはホストが固まって `ServerUp` が一切送られなくなっても、NFR7.9（`ServerUp` = 0 が 60 分続き、インスタンスが稼働中）のアラームは発火しません。「インスタンスが稼働中」という条件を組み込む手段（複合アラームや EC2 の状態メトリクス）も定義されていません。自動停止はサーバー側の systemd timer（NFR5.4 の自己停止権限）に頼っているため、ホストが無応答だと誰も止められません。さらに `ServerUp` は 25565 の疎通確認、FR5.2 の無応答は人数確認の無応答で、監視する信号が違います。Minecraft の主スレッドが固まってもポートが開いたままなら `ServerUp` = 1 になります。停止を忘れても課金が続かない、という成功基準（月 3,000 円）に対する抜け穴です。 | ホストの外側から止める経路を要件に加えてください。例えば (1) 稼働中だけ有効な複合アラーム（EC2 の稼働状態と欠測を組み合わせ、欠測は breaching 扱い）、(2) EC2 の StatusCheckFailed や最大連続稼働時間（例: 12 時間）を超えたら EventBridge と Lambda で強制停止する上限、のいずれか。`ServerUp` の定義（ポート疎通か、ping 応答か）を FR5.2 の無応答の定義と揃え、合否基準（何分で誰が止めるか）を書いてください。 | Resolved (reviewer) |
| R-04 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/performance-requirements.md > 「前提とリソース制約」（x86 への切り替え）、tech-stack-decisions.md > 判断 3 | ARM で動かない MOD があるときは `instance_type` を x86 に変える、と書いています。しかし同じ文書で、`instance_type` の変数バリデーションは Graviton（`*g.*`）だけを許可し、NFR2.5 は arm64 を `terraform test` で検証し、AMI も arm64 の SSM パラメータに固定しています。この定義のままでは、逃げ道が動きません。 | アーキテクチャ（arm64 / x86_64）を変数にして、AMI とインスタンスタイプの組み合わせを検証する要件にしてください。または、x86 への切り替えは要件変更として扱う、と書き直してください。 | Resolved (reviewer) |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.2 と NFR5.11 | plan 用ロールを「読み取り中心」とし、state へのアクセスは 2 つのロールに限定しています。しかし、Terraform の S3 ネイティブロック（`use_lockfile = true`）は plan でもロックファイルの書き込みと削除を行います。plan 用ロールに、ロックファイルに限った書き込み権限が必要です。 | plan 用ロールに必要な最小権限を明記してください。state の読み取り、ロックファイル（`*.tflock`）の Put / Delete、読み取り専用の describe 系。state 本体への書き込みは含めません。 | Resolved (reviewer) |
| R-06 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.10 | バケットのライフサイクルで「古いバージョンは一定日数後に削除」とあり、日数が決まっていません。バックアップは毎時の削除で削除マーカーと旧バージョンが増えます。scalability-requirements.md のコスト見積もり（1 世代 1 GB × 31 世代）にも旧バージョン分が入っていません。 | 旧バージョンの保持日数（例: 7 日）を数値で決め、見積もりに旧バージョン分を加えて NFR2.9 の 50 GB 警告と整合させてください。 | Resolved (reviewer) |
| R-07 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR6.1（Open: gitleaks） | public リポジトリで最も重い制約（識別子を一切出さない）の合否基準が、「リポジトリ全体の検索で 0 件」という手動確認にとどまり、CI での自動検査は Open のままです。gitleaks は一般的なシークレットを探すもので、12 桁のアカウント ID や IAM ロール名の形式は検出しません。 | 自動検査の方式を決めてください。例えば、`arn:aws:` や 12 桁の数字、`sts.amazonaws.com` 以外の識別子のパターンをブロックするスクリプトを CI の必須チェックに加える。必須チェックに加える場合は、`team.md` の必須チェック一覧と Branch protection の登録にも反映してください。 | Resolved (reviewer) |
| R-08 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/tech-stack-decisions.md > 品質ゲート NFR8.3（pytest） | Lambda の pytest が NFR8.3 の合否基準に入っていますが、NFR8.2 の「マージ必須チェック」（Branch protection に登録するもの）と `team.md` の必須チェック一覧に pytest が含まれていません。pytest が失敗しても、マージできてしまう恐れがあります。 | pytest（必要なら gitleaks や上記の識別子チェックも）を必須ステータスチェックに加える、と NFR8.2 に明記してください。 | Resolved (reviewer) |
| R-09 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR6.1 識別子チェックのパターン | 許可リストは `0.0.0.0/0` と `noreply@` 系だけです。一方で `arn:aws:` を含む行は一律に失敗します。NFR5.6 が要求する `AmazonSSMManagedInstanceCore` の付与は、通常 `arn:aws:iam::aws:policy/...` の形で書くため、この文字列でチェックが失敗します（アカウント ID は含まれないのに失敗する）。VPC・サブネットの CIDR（IPv4 の文字列）も同様に失敗します。このまま実装すると必須チェックが最初の PR から通りません。 | 許可リストを明記してください。たとえば、AWS 管理ポリシー ARN（`arn:aws:iam::aws:policy/`）、`data.aws_partition` や `data.aws_caller_identity` の参照、RFC1918 のプライベート CIDR を許可します。「アカウント ID を含む ARN」に絞る案も検討してください。 | New |
| R-10 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.4 / NFR5.2b と observability-requirements.md > NFR7.9a | 最小権限が定義されているのは EC2 のインスタンスプロファイルと CI の 3 ロールだけです。watchdog Lambda（`ec2:StopInstances`、`cloudwatch:GetMetricData`、タグ参照、SNS 発行）と通知 Lambda の実行ロールには、権限範囲も検証方法もありません。NFR7.9a の 3 条件にも、アラーム表に合否基準の列がありません。外から停止できる権限を持つロールなので、検証可能な形にする必要があります。 | NFR5.4 に Lambda 実行ロールを加えてください。watchdog はタグで限定した対象インスタンスの停止のみとします。NFR7.9a の発火条件それぞれに、`terraform test` または Lambda 単体テストでの合否基準を書いてください。 | New |
| R-11 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/security-requirements.md > NFR5.2b と NFR5.2d | apply 用ロールは「名前プレフィックス付きのロールだけ」を作成でき、bootstrap のロールには Deny を付ける設計です。しかし、bootstrap 側のロール名が同じプレフィックスを共有するのかどうかが決まっていません。共有すると、プレフィックス許可と ARN Deny が競合し、どちらが優先されるか読み取れません。 | bootstrap のロールと envs/prod のロールの命名規則（別プレフィックス）を定め、Deny が bootstrap だけに当たることをテストで検証してください。 | New |

> R-01 Reviewer note: security-requirements.md で NFR5.2 を plan / apply / 運用操作の 3 ロールに分け、「ロールとワークフローの対応」表を追加しています。start / stop / restore は承認なしの `ops` Environment（`master` のみ）で動き、「start には承認が入らないため NFR3.1 に承認待ちは含まれない」と明記されました。tech-stack-decisions.md の「起動・停止・復元の操作」とも一致しています。

> R-02 Reviewer note: NFR5.2b で apply 用ロールのサービス範囲、名前プレフィックス、permissions boundary 必須、PassRole の制限を定めています。NFR5.2d で OIDC プロバイダー・3 ロール・boundary を bootstrap に置き、apply 用ロールに bootstrap ARN への `iam:*` Deny を付けています。いずれも bootstrap の `terraform test` で検証する形です。

> R-03 Reviewer note: NFR7.9a で EventBridge + Lambda の watchdog を追加しました（無応答 60 分、`StatusCheckFailed` 15 分、連続稼働上限 12 時間）。欠測は稼働中なら異常として扱います。NFR7.1 は `ServerUp` を server list ping の応答有無とし、FR5.2 の無応答と同じ意味に揃えました。NFR4.9 も整合しています。

> R-04 Reviewer note: NFR2.5 の `cpu_architecture` 変数と、AMI を同変数で選ぶ設計に変わりました。`instance_type` との不整合は plan が失敗することを `terraform test` で検証します。切り替え手順も performance-requirements.md に記載されています。

> R-05 Reviewer note: NFR5.2a に plan 用ロールの最小権限が明記されました（state 読み取り、`*.tflock` への Put/Delete、読み取り専用の Describe/Get/List 系）。

> R-06 Reviewer note: NFR5.10 で旧バージョンの保持を 7 日と決め、`noncurrent_days = 7` のテストも定めています。scalability-requirements.md の見積もり（最大約 70 GB）と NFR2.9 の 80 GB 閾値も整合しています。

> R-07 Reviewer note: NFR6.1 に「識別子チェック」のパターンを定義し、gitleaks と合わせて必須チェックにしました。ただし、このパターンが実コードに当たる点は下の新規指摘で扱います。

> R-08 Reviewer note: NFR8.2 で pytest・識別子チェック・gitleaks を含む 9 つを必須チェックとし、`team.md` への追加分であることを明記しました。承認前の本人確認が assumption として記録されています。

### Validation Tool Results

| Tool | Result | Interpretation |
|---|---|---|
| なし（stage 定義に validation tool の宣言なし） | N/A | 手作業で NFR ID の相互参照（NFR5.2a〜d、NFR7.9a）を確認しました。traceability.json の NFR1〜NFR9 は成果物に実在し、細分 ID（NFR5.2a〜d、NFR7.9a）は親 ID の NFR5 / NFR7 に含まれます。traceability.json の target 欄に細分 ID は列挙されていませんが、親 ID の網羅は取れています。 |

### Summary

iteration 1 の Major 3 件（R-01〜R-03）と Minor 5 件はすべて実質的に直っており、ロール分離、IAM 昇格防止、外部 watchdog の設計は実装に着手できる水準です。新規の指摘は Minor 3 件のみで、READY としますが、識別子チェックの許可リストは Construction の初回 PR で CI が落ちるため、早めに確定してください。
