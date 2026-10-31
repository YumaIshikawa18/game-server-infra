# Reliability Requirements

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`（NFR4, NFR9, FR1.3, FR4.x, FR5.x, FR6.x, FR8.1）、`nfr-requirements-questions.md`（Q3, Q5）。

## 可用性

| ID | 要件 | 目標 / 合否基準 | 出典 |
|---|---|---|---|
| NFR9.1 | 常時稼働の SLA は設けない | 遊ぶときだけ起動する前提（FR4, FR5） | NFR9 |
| NFR9.2 | 起動の成功率（目安） | 月 95% 以上を目安とし、測定の仕組みは作らない。失敗は個別に通知する（FR4.4） | NFR9, Q17 |
| NFR9.3 | 購入方式 | オンデマンドにする。スポットによる中断は発生させない | [Q3] |
| NFR9.4 | 単一 AZ | 1 AZ・1 台で構成する。AZ 障害時はバックアップから別 AZ に復元する手順（手動）で対応する | NFR9（導出） |

## データ保全（RPO / RTO）

| ID | 要件 | 目標 / 合否基準 | 出典 |
|---|---|---|---|
| NFR4.1 | RPO（稼働中の障害） | 最大 1 時間。毎時バックアップで担保する（FR6.1） | NFR4 |
| NFR4.2 | 遡れる範囲 | 停止時バックアップ 7 世代と、稼働中の短期 24 世代 | NFR4, FR6.1, FR6.2 |
| NFR4.3 | 保存先 | ワールドを圧縮（`tar.zst` 等）して S3 に保存する。短期枠と停止時枠でプレフィックスを分け、世代の削除はバックアップスクリプトが行う | [Q5] |
| NFR4.4 | 整合性 | 取得中は `save-off` → `save-all flush` → 取得 → `save-on` の順に行う（FR6.3）。アップロード後に、オブジェクトのチェックサムをローカルの値と照合する | FR6.3 |
| NFR4.5 | RTO（復元） | 復元ワークフロー（停止中のみ実行可能）を実行してから接続できるようになるまで 20 分以内（[assumption]） | FR6.5 |
| NFR4.6 | 誤削除の防止 | ワールド用 EBS、バックアップ用 S3、Elastic IP に `prevent_destroy` を付ける。S3 はバージョニングで、誤った上書きからも戻せるようにする | FR8.1, FR1.3 |
| NFR4.7 | 復元の検証 | 月 1 回（[assumption]）、または MOD やバージョンの変更前に、最新の停止時バックアップから復元できることを確認する手順を runbook に用意する | FR6.5（運用での担保） |

## 障害時の振る舞い

| ID | 状況 | 期待する振る舞い | 出典 |
|---|---|---|---|
| NFR4.8 | Minecraft の起動失敗 | start ワークフローが失敗し、Discord とメールに通知し、インスタンスを停止する | FR4.4 |
| NFR4.9 | サーバーの無応答 | 1 時間続いたら強制停止する。停止前のバックアップは試みるが、失敗しても停止は行う。ホスト自体が固まった場合は、外部の watchdog（NFR7.9a）が停止する。連続稼働が 12 時間を超えた場合も watchdog が停止する | FR5.2, FR6.4, NFR1 |
| NFR4.10 | バックアップの失敗 | 通知する。稼働は続け、停止時の失敗でもワールドの EBS は残す | FR6.4 |
| NFR4.11 | Discord への通知の失敗 | メール（SNS）には届く。Lambda は Webhook 呼び出しにタイムアウト（5 秒）を設け、リトライは最大 2 回（指数バックオフ）とする | FR8.2 |
| NFR4.12 | 処理の競合 | GitHub Actions の `concurrency`（グループ `minecraft-prod`、キャンセルなし）と、サーバー側のロックファイルで排他する。自動停止の処理中に start を受けたら完了を待つ。停止処理中は毎時バックアップをスキップする | FR4.3 |
| NFR4.13 | 置き換えを伴う apply | apply ワークフローは plan に EC2 の置き換えがあり、かつ稼働中であることを検知したら、先に stop 処理（保存・バックアップ・停止）を実行してから apply する | FR4.5 |

## ロールバック

- インフラ変更: 直前のコミットを revert する PR をマージし、承認付きの apply で戻します（team-practices の Deployment）。
- Minecraft / ローダー / MOD の更新でワールドが読めなくなった場合: バージョンを戻す PR を apply した後、更新前の停止時バックアップから復元します（FR6.5）。

## Sources

- `requirements.md` NFR4, NFR9, FR1.3, FR4.3〜FR4.5, FR5.2, FR6.1〜FR6.5, FR8.1, FR8.2
- `team-practices.md` Deployment
- `nfr-requirements-questions.md` [Q3] [Q5]

## Assumptions & Open Questions

- [assumption] 復元の RTO は 20 分以内とする。
- [assumption] 復元の検証は月 1 回、または変更前に行う。
- Open: AZ 障害時の手動復元手順の詳細は、operation フェーズの runbook で定める。
