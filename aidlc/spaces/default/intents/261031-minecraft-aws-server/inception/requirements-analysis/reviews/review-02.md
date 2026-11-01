## Review

**Verdict:** READY
**Reviewer:** aidlc-product-lead-agent
**Date:** 2026-10-31T16:50:19Z
**Iteration:** 1
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > FR8.2, FR6.4, FR5.1, NFR7 | FR8.2 は結果の確認手段を「GitHub Actions の Job Summary」に限っています。しかし自動停止（FR5.1）と稼働中の毎時バックアップ（FR6.1）はインスタンス上で動き、workflow は走りません。そのため、自動停止の実行結果とバックアップ失敗（FR6.4 が FR8.2 に通知を委ねている）は Job Summary に出ません。NFR7 の「直近のバックアップ結果を確認できる」も、手段が定まらず検証できません。 | 無人で動く処理（自動停止・毎時バックアップ・停止時バックアップ）の結果を、誰がどこで確認するかを決めてください。例: 定期的な確認用 workflow が結果を Job Summary に出す、CloudWatch メトリクスとアラームを使う、などです。FR6.4 の失敗通知にも受け入れ基準（AC）を付け、NFR7 の確認手段を具体化してください。 | Resolved (reviewer) |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > FR3.4, FR5.2, FR6.3, FR6.4, FR7.1, FR7.2, FR7.4, FR8.2, FR8.4, FR9.2 | これらの要件には Given/When/Then の AC がありません。特に FR5.2（人数が確認できない場合の誤停止の防止と、2 時間の強制停止）、FR6.4（停止時のバックアップ失敗）、FR8.4（whitelist の注入）は、QA がテストを書けません。phase ルール「各要件に合否基準」と「AC は Given/When/Then」を満たしていません。 | 各要件に AC を追加してください。FR5.2 は「無応答 1 時間 59 分では停止せず、2 時間で停止する」、FR6.4 は「バックアップ失敗時も停止してワールドの永続ストレージが残り、通知が出る」、FR8.4 は「whitelist がリポジトリに存在しない」のように書きます。FR7.x は workflow の分岐ごとに書いてください。 | Resolved (reviewer) |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > FR4.1, FR4.3, FR5.1, FR1.3, FR6.5 | 競合と中断の隅の扱いが決まっていません。(a) FR4.3 は GitHub Actions の concurrency だけを排他の対象にしており、インスタンス側の自動停止やバックアップとは競合します。たとえば自動停止のバックアップ中に start が実行された場合です。(b) AC1.3.1 のようにインスタンスを置き換える apply の前に、ワールドを保存してバックアップする要件がありません。稼働中の置き換えでは最大 1 時間分を失い得ます。(c) FR6.5 の復元を、稼働中のサーバーに対して実行してよいかが不明です。(d) start の途中で Minecraft の起動に失敗した場合の AC がありません。 | 次の振る舞いを AC として決めてください。(a) 自動停止中に start が来たとき。(b) 稼働中に置き換えが入る apply の前に、保存とバックアップを取るか、稼働中の置き換えを拒否するか。(c) 復元は停止中のみ許可するか。(d) 起動失敗時に start workflow が失敗として報告されること。 | Resolved (reviewer) |
| R-04 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > FR2.1, FR2.2, Assumptions & Open Questions（最後の Open 項目） | FR2.1 の「既定は最新リリース版」は、実行時に最新へ解決されるのか、PR でバージョンを固定するのかが曖昧です。前者だと、再起動や置き換えのたびに Minecraft のバージョンが勝手に変わり、MOD やローダーとの互換性が崩れてワールドが壊れる恐れがあります（AC2.2.3 は事後の検知のみ）。また、MOD のサーバー側導入とクライアント側（友人の PC）への配布の違いは、Open のまま未解決です。ローダーを使う運用では、友人が接続できるかどうかに直結します。 | 「既定の最新」を、明示的に固定されたバージョン値として commit する方針にするか、再解決を許すかを決めて AC に反映してください。クライアント側 MOD の配布は、範囲内か範囲外かをここで確定し、範囲外なら Out of scope に移してください（本人への確認が必要です）。 | Resolved (reviewer) |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements-analysis-questions.md > Consolidated Summary Confirmation, requirements.md > Assumptions & Open Questions | 約 12 件の [assumption] は、本人の確認が Q&A に記録されていません（Q9 の 24 世代のみ本人が明記）。確認画面は成果物の生成前に済んでおり、30 分 / 2 時間 / 40 時間 / 10 分 / 95% などの数値は、本人が見る前に確定値として書かれています。 | ゲートで、[assumption] を一覧にして本人に確認してもらってください。特に FR5.1 / FR5.2 / NFR1 / NFR3 の数値は影響が大きいため、承認時に確認します。 | Resolved (reviewer) |
| R-06 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > NFR1, NFR2, NFR9, FR8.3 | NFR1 の 3,000 円以下は、見積もりを後続ステージに送っているため、現時点では合否を判定できません。NFR2 の TPS と NFR9 の起動成功率 95% も、測定方法（誰が、どこで測るか）がありません。FR8.3 は whitelist の前提となる `online-mode`（正規アカウントの検証）が未記載で、無効のままだと名前の偽装で whitelist をすり抜けられます。 | NFR1 には、前提（稼働時間・リージョン・インスタンスタイプ）を置いた見積もりを nfr-requirements の合否基準として明記してください。NFR2 と NFR9 には測定方法を書くか、目安として扱うことを明記してください。FR8.3 には `online-mode` を有効にする要件を足してください。 | Resolved (reviewer) |
| R-07 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > FR4.3, FR6.1, FR4.2, NFR3 | 排他の対象が start / stop / apply / restore に限られ、毎時バックアップ（FR6.1）と手動 stop の停止時バックアップ（FR4.2）が同時に走る場合の扱いがありません。また AC4.3.2 は自動停止の完了を待ってから start するため、待ち時間が NFR3 の 10 分に含まれるのか書かれていません。 | 毎時バックアップと停止時バックアップが重なった場合の振る舞い（後者を待たせる、前者をスキップする等）を 1 つ AC にする。NFR3 の 10 分が、待機時間を含むか除くかを明記する。いずれも設計で決める旨の assumption でも構いません。 | New |
| R-08 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md > NFR6, FR8.2 | NFR6 の秘匿対象は「コード・Actions ログ・PR コメント」だけです。Discord に投稿する通知の本文が、Elastic IP・ARN・アカウント ID を含まないことは要件にありません。Discord は外部サービスで、チャンネルの閲覧者も本人以外になり得ます。 | FR8.2 に、通知本文には Elastic IP、アカウント ID、ARN を含めない旨の AC を 1 つ足す。または Discord を秘匿範囲外とする判断を assumption として明記する。 | New |

> R-01 Reviewer note: FR8.2 が CloudWatch → SNS → Lambda → Discord とメール保険に変わり、無人処理の成功・失敗の通知先が決まりました。FR6.4 に AC6.4.1 / AC6.4.2 が付き、NFR7 も「Discord の通知履歴と CloudWatch」と具体化されています。

> R-02 Reviewer note: FR3.4、FR5.2、FR6.3、FR6.4、FR7.1〜7.4、FR8.2、FR8.4、FR9.2 のすべてに Given/When/Then の AC があります。FR5.2 は 59 分 / 1 時間 / 40 分の境界まで書かれ、QA がテストを書ける水準です。

> R-03 Reviewer note: (a) AC4.3.2、(b) FR4.5、(c) AC6.5.2、(d) FR4.4 と AC4.4.1 で、競合・中断の振る舞いが AC として決まりました。

> R-04 Reviewer note: FR2.1 が具体バージョン固定と、`latest` を拒否する AC2.1.3 を定めています。クライアント側の配布は FR3.5（手順書のみ）に確定し、範囲外の線引きも Out of scope にあります。

> R-05 Reviewer note: Q16 で 30 分 / 40 時間 / 10 分 / 50 個を本人が確認し、強制停止は 1 時間に変更されました。95% は Q17 で目安扱いに確定しています。残る [assumption] は、Consolidated Summary Confirmation で「Looks correct」が得られ、訂正可能な既定値として明示されています。

> R-06 Reviewer note: NFR1 に前提と合否基準が入りました。NFR2 / NFR9 は目安扱いで、測定の仕組みは作らない旨が明記されています。FR8.3 と FR1.4 に `online-mode` が入りました。

### Summary

前回の Major 4 件（R-01〜R-04）と Minor 2 件（R-05, R-06）は、追加質問 Q10〜Q17 の回答を AC と NFR に反映した形で解消されています。開発側が追加の確認なしに設計へ進めると判断し、READY とします。新規の指摘は Minor 2 件で、いずれも設計段階で決められる範囲です。
