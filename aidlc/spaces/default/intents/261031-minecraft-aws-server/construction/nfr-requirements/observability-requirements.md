# Observability Requirements

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`（NFR7, FR8.2, FR5.x, FR6.x, FR9.1）、`nfr-requirements-questions.md`。

## 通知の経路

CloudWatch アラーム / EventBridge イベント / サーバー側スクリプト → SNS トピック → Lambda → Discord Webhook の順に流します。メールは同じ SNS トピックの購読者として届けます。Webhook URL は SSM SecureString から読みます（FR8.2, NFR6.3）。

## メトリクス

| ID | メトリクス | 送信元 | 用途 | 出典 |
|---|---|---|---|---|
| NFR7.1 | `ServerUp`（0/1、1 分ごと） | サーバー側スクリプトが Minecraft の server list ping（25565）を送り、5 秒以内に正常な応答があれば 1、なければ 0 を送る。ポートが開いているだけでは 1 にしない | ヘルス指標（operation ガードレールの必須項目）。FR5.2 の「無応答」は、この値が 0 の状態と同じ意味とする | NFR7, FR5.2 |
| NFR7.2 | `PlayersOnline`（人数、1 分ごと） | 同じ server list ping の応答に含まれる人数 | 自動停止の判定（FR5.1）。無応答のときは値を送らない | FR5.1, FR5.2 |
| NFR7.3 | `BackupFailures`（回数） | バックアップスクリプト | エラー指標（operation ガードレールの必須項目） | NFR7, FR6.4 |
| NFR7.4 | `BackupSizeBytes` / `BackupDurationSeconds` | バックアップスクリプト | 容量とコストの監視（NFR2.9） | NFR1 |
| NFR7.5 | `StartupDurationSeconds` | start ワークフロー（Job Summary と起動完了通知に載せる） | NFR3.1 の判定 | NFR3 |
| NFR7.6 | ワールド用ディスクの使用率（%） | CloudWatch Agent | 容量の警告（NFR2.8） | NFR2 |

## アラームと通知

| ID | アラーム / イベント | 条件 | 通知先 | 出典 |
|---|---|---|---|---|
| NFR7.7 | バックアップ失敗 | `BackupFailures` ≥ 1（5 分間） | Discord（🔴）+ メール | FR6.4, FR8.2 |
| NFR7.8 | 起動失敗 | start ワークフローの失敗、またはサーバー側の起動失敗イベント | Discord（🔴）+ メール | FR4.4 |
| NFR7.9 | 無応答による強制停止（サーバー内から） | `ServerUp` = 0 が 60 分続いたら、サーバー側スクリプトが自分自身を停止する | Discord（🔴）+ メール | FR5.2 |
| NFR7.9a | 無応答による強制停止（ホストの外から） | ホストが固まりスクリプトが動かない場合への備え。EventBridge スケジュール（5 分ごと）で動く Lambda「watchdog」が、次の 3 条件のいずれかを満たしたら、インスタンスを外から停止して通知する。<br>(a) インスタンスが `running` で、`ServerUp` の欠測（または 0）が 60 分続いている<br>(b) EC2 の `StatusCheckFailed` が 15 分続いている<br>(c) 連続稼働が上限（既定 12 時間、変数で変更可）を超えた<br>欠測は「稼働中なら異常」として扱う。<br>合否基準（Lambda の単体テスト）:<br>・(a) 欠測 59 分では停止せず、60 分で停止する<br>・(b) 失敗 14 分では停止せず、15 分で停止する<br>・(c) 11 時間 59 分では停止せず、12 時間で停止する<br>・タグ `mc:stopping=true` があれば停止を見送る<br>・停止中のインスタンスには何もしない | Discord（🔴）+ メール | FR5.2, NFR1 |
| NFR7.10 | 起動完了 / 手動停止 / 自動停止 | サーバー側スクリプトと start / stop ワークフローが SNS に送る | Discord（🟢 / 🔵 / 🟡）のみ | FR8.2 |
| NFR7.11 | ディスク使用率 | 80% 以上が 15 分続く | Discord（🟡）+ メール | NFR2.8 |
| NFR7.12 | 予算 | Budgets の 80% / 100%（実績と予測） | Discord（🟡 / 🔴）+ メール | FR9.1 |
| NFR7.13 | スモークテスト失敗 | apply 後の 25565 疎通確認の失敗 | Discord（🔴）+ メール | FR7.3 |

- 停止中は `ServerUp` を送りません。そのため、`ServerUp` に CloudWatch アラームを直接かけて「データなし＝正常」とする方式は採りません。稼働中の欠測は、watchdog（NFR7.9a）が EC2 の状態と組み合わせて判定します。
- watchdog は、停止処理（手動停止・自動停止）の実行中は、ロックファイルの代わりに EC2 のタグ（`mc:stopping=true`）を見て強制停止を見送ります。このタグは、サーバー側の停止スクリプトが停止処理の開始時に付け、起動時に外します（NFR5.4b）。外から停止するときは、バックアップが取れないことを通知に書きます（ワールドの EBS は残ります）。
- アラームの閾値は SLO 違反よりも手前に置きます。たとえば RPO 1 時間に対し、バックアップ失敗は 1 回目で通知します（operation ガードレール）。

## ログ

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR7.14 | Minecraft のサーバーログ、バックアップスクリプト、自動停止スクリプトのログを CloudWatch Logs に送る。保持期間は 14 日（[assumption]） | ロググループに `retention_in_days = 14` が設定されている（テストで検証） | NFR7 |
| NFR7.15 | Lambda（通知）のログは保持期間 14 日とし、Webhook の失敗をエラーとして記録する | AC8.2.3 | FR8.2 |
| NFR7.16 | ログと通知に秘匿値を出さない（NFR6.4, NFR6.5）。サーバーログに含まれるプレイヤー名は保持期間内のみ残す | NFR6 | NFR6 |

## 確認手段（NFR7 の合否）

- サーバーの稼働状態: Discord の起動・停止通知と、CloudWatch の `ServerUp` で確認します。
- 直近のバックアップ結果: 停止通知に載る停止時バックアップの結果、失敗時の通知、CloudWatch の `BackupFailures` / `BackupSizeBytes` で確認します。
- ダッシュボードは作りません（[assumption]）。必要になったら CloudWatch ダッシュボードを追加します。

## Sources

- `requirements.md` NFR3, NFR7, FR4.4, FR5.1, FR5.2, FR6.4, FR7.3, FR8.2, FR9.1
- operation フェーズのガードレール（ヘルス指標とエラー指標を最低 1 つずつ持つこと、アラームを SLO 違反の手前に置くこと）

## Assumptions & Open Questions

- [assumption] ログの保持期間は 14 日とする。
- watchdog による連続稼働の上限は 12 時間とする（承認前の確認で本人が決定）。
- [assumption] watchdog の Lambda と EventBridge スケジュールのコストは、無料枠内（月 8,640 回）に収まる。
- [assumption] CloudWatch ダッシュボードは作らない。
- Open: 人数の取得方法（server list ping か RCON の `list` か）は NFR Design で決める。
