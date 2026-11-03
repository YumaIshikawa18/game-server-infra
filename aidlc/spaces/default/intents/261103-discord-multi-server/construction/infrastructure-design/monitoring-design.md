# Monitoring Design

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/inception/requirements-analysis/requirements.md`

新しいメトリクス、アラーム、ダッシュボードは追加しません（NFR6）。起動の失敗は既存の `start_failed` と Start workflow の仕組みで検知し、人数はログで確認します。

## Metrics & KPIs

| Metric | Source | Threshold | Why it matters |
|---|---|---|---|
| オペレーターの人数（`event=env_prepared` の `ops=`） | スクリプトのログ（`/var/log/minecraft/scripts.log`、CloudWatch Logs に転送） | 期待する人数との一致（今回は 1。取り消し後は 0） | パラメータ名の誤りで 0 人になっていないかを確認します（FR5.1、NFR5） |

## Alerts

| Alert | Condition | Severity | Routes to |
|---|---|---|---|
| `start_failed`（読み取り失敗） | 未登録以外の理由で `<param_prefix>/ops` を読めない | error | SNS `events` → Discord、メール |
| `start_failed`（形式不正） | 一覧の形式が不正 | error | 同上 |
| `start_failed`（ホワイトリストとの不一致） | 一覧の名前がホワイトリストにない | error | 同上 |
| `start_failed`（書き込み失敗） | `ops.json` の種または `secrets.env` を書けない、または置き換えられない | error | 同上 |
| Start workflow の失敗（既存） | 名前を解決できずコンテナが起動しない場合など、ヘルス確認が時間切れになる | error | 既存の `start-failed` の停止と通知 |

未登録（0 人）は通知しません（FR3.1）。文面にプレイヤー名を含めません（FR3.5）。

## SLIs / SLOs

この変更のために新しい SLO は定めません。身内向けの単一サーバーで、既存の監視の範囲で運用します。

| SLI | SLO target | Measurement window |
|---|---|---|
| 該当なし（新しいサービスや常駐のコンポーネントを追加しません） | 該当なし | 該当なし |

## Logs & Tracing

- ログには人数だけを書き、名前と `aws` のエラー出力は書きません（NFR1）。
- 既存の形式 `log <level> event=... key=value` に合わせ、失敗のイベントは `ops_unavailable`、`ops_invalid`、`ops_not_whitelisted`、`ops_seed_failed` とします。
- トレースとダッシュボードの変更はありません。
