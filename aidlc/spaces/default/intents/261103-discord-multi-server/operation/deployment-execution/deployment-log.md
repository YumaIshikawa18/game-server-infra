# Deployment Log

**状態: 完了**

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/build-and-test/test-results.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/infrastructure-design/cicd-pipeline.md`

Deployment Pipeline と Environment Provisioning はこのプランの対象外のため、`cd-config`、`deployment-strategy`、`environment-inventory` はありません。既存の PR と Deploy の workflow を使い、対象は本番（`prod`）の 1 環境です。データベースの移行はありません。

## 実施したこと

| 時刻（UTC） | 内容 | 結果 |
|---|---|---|
| 2026-11-03 | PR #9 の必須チェック | 11 件すべて成功 |
| 2026-11-03 | PR #9 の `plan` | 追加 0、変更 3、削除 0。すべて配布ファイル |
| 2026-11-03T14:11:13Z | PR #9 のマージ（ご本人） | マージコミット `c07699c` |
| 2026-11-03 | `prod` の承認（ご本人）と Deploy | 成功 |
| 2026-11-03T14:23:29Z 頃 | 1 回目の Stop と Start（パラメータ未登録） | 成功。`players=1 ops=0` |
| 2026-11-04T07:29:21Z 頃 | 2 回目の Start（ご本人が登録済み。自動停止の後のため Stop なし） | 成功。`players=2 ops=1` |
| 2026-11-04T07:37:42Z 頃 | 3 回目の Stop と Start（ご本人がパラメータを削除） | 成功。`players=2 ops=0`、`ops.json` は 0 件 |
| 2026-11-04T07:44:26Z 頃 | 4 回目の Stop と Start（ご本人がパラメータを再登録） | 成功。`players=2 ops=1`、`ops.json` は 1 件で `level` 3 |

`players` が 1 から 2 に増えたのは、ご本人の追加です（`deployment-execution-questions.md` の Q10）。

## 手順の結果

`cicd-pipeline.md` のデプロイの手順に沿って進めました。

| # | 内容 | 結果 |
|---|---|---|
| 1 | マージと apply | 完了 |
| 2 | 未登録で Stop と Start、`ops=0`、接続 | `ops=0` は完了。接続は手順 7 で確認 |
| 3 | 一覧を登録して Stop と Start | 完了（自動停止の後のため Start のみ） |
| 4 | 起動ログが `ops=1` | 完了 |
| 5 | `ops.json` の確認 | 完了。手順 6 の後に確認し、4 回目の起動の直後にも確認 |
| 6 | ゲーム内の `/gamemode`、`/kick`、`/stop` | 完了（`/stop` は候補に出ないことで判断） |
| 7 | パラメータを削除して Stop と Start | 完了 |
| 8 | 再登録して Stop と Start | 完了 |
| 9 | 接続とワールドの確認 | 完了（ご本人） |

## 手順と異なる点

- Stop と Start は計画の 4 回ではなく、Stop 3 回と Start 4 回です。2 回目はサーバーが自動停止していたため、Stop が不要でした。
- `ops=0` での接続は、手順 2 ではなく手順 7 で確認しました。ご本人の回答によるものです（Q5）。
- 手順 5 の `ops.json` は、ご本人の依頼でこちらが SSM から確認しました。名前は出さず、件数、`level`、`uuid` が空かどうかだけを取り出しました。

## ロールバック

実行していません。手順は `cicd-pipeline.md` のロールバックと README にあります。権限だけを外すときは、パラメータを削除して次の起動を行います。この経路は手順 7 で実際に確認しました。

## 完了時の状態

- パラメータは登録済みで、オペレーターは 1 人です。
- サーバーは動作中です（2026-11-04T07:47Z に起動）。プレイヤーが 0 人の状態が 30 分続くと自動で停止します。
- このステージの記録は作業ブランチに未コミットです。PR #9 はマージ済みのため、記録を `master` に入れるには別の PR が必要です。
