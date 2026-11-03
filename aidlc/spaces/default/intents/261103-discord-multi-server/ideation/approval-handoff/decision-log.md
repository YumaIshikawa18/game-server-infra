# Decision Log

Ideation フェーズの決定を記録します。上流は `ideation/intent-capture/intent-statement.md`、`ideation/intent-capture/stakeholder-map.md`、`ideation/feasibility/feasibility-assessment.md`、`ideation/feasibility/constraint-register.md` です。

| ID | 決定 | 理由 | 出典 |
|---|---|---|---|
| D-01 | この作業はオペレーター権限（今のサーバー）で完了とする | ご本人の判断です | Approval & Handoff の Q1、Q5 |
| D-02 | 増設は保留とし、判断後に別の作業として始める | ご本人の判断です | Approval & Handoff の Q1、Q5 |
| D-03 | 管理者権限はゲーム内のオペレーター権限を指す | ご本人の回答です | Intent Capture の Q5 |
| D-04 | オペレーターはご本人だけで、Minecraft のユーザー名で指定する | ご本人の回答です | Intent Capture の Q13 |
| D-05 | ユーザー名はホワイトリストと同じ秘匿パラメータに置き、変更は手元で行い、次の起動で反映する。仕組みの追加は PR とデプロイで行う | 公開リポジトリに名前を出さないためです。Intent Capture の Q8 より優先します | Feasibility の Q5 |
| D-06 | テストはチームの基準に加え、追加する動作についても書く | ご本人の回答です | Intent Capture の Q15 |
| D-07 | 今のサーバーの停止を伴う変更は、誰も遊んでいない時間に行う | ご本人の回答です | Feasibility の Q4 |

## 増設を再開するときの方針

| ID | 決定 | 出典 |
|---|---|---|
| D-08 | サーバーはすべて別々にする | Intent Capture の Q3 |
| D-09 | 同じ AWS アカウントで接頭辞を分ける方式を推奨とする（別の作業で最終判断） | Feasibility の評価 |
| D-10 | 今と同じ性能で、合計の費用増を許容する。新しいサーバーは月 20 時間以下、5 人程度の想定 | Feasibility の Q1、Q2 |
| D-11 | 先に今のサーバー向けの変更をデプロイして確認し、その後で 2 台目を作る | Approval & Handoff の Q2 |
| D-12 | webhook は向こうの主催者や管理者に作ってもらい、届く前に構築を進める | Feasibility の Q3、Approval & Handoff の Q3 |
| D-13 | オペレーター権限はサーバーごとに指定する | Intent Capture の Q12 |
| D-14 | 実費の分担は、ご本人が利用規約を確認するまで受け取らない | Approval & Handoff の Q4 |
| D-15 | 今のワールドは引き継がず、Discord から操作する機能も追加しない | Intent Capture の Q7 |

## 未解決

| ID | 内容 | 担当 |
|---|---|---|
| O-01 | 実費の分担が Minecraft の利用規約に沿うかの確認 | ご本人（増設の再開前） |
| O-02 | 増設時の月額の予算額 | ご本人（増設の再開時） |
