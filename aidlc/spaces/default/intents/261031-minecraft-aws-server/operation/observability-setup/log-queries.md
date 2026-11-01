# ログの調査用クエリ

CloudWatch Logs Insights で使うクエリです。保存済みクエリにはせず、ここからコピーして使います（Q2）。

## ロググループ

いずれも保持期間は 14 日です。`<prefix>` は非公開の接頭辞で、値は `bootstrap/generated.auto.tfvars.json` にあります。

| ロググループ | 内容 |
|---|---|
| `/<prefix>/server` | Minecraft コンテナのログ。プレイヤー名を含みます |
| `/<prefix>/scripts` | ホスト上のスクリプトのログ（`key=value` 形式） |
| `/<prefix>/notifier` | 通知 Lambda のログ |
| `/<prefix>/watchdog` | 強制停止 Lambda のログ |

調査結果を Issue や PR に貼るときは、プレイヤー名や識別子を含めないでください（`../../construction/nfr-design/security-design.md` §4）。

## `/<prefix>/scripts` で使うクエリ

### 1 回の稼働を追う

`<session-id>` には、通知や他のログにある `session_id` の値を入れます。

```sql
fields @timestamp, @message
| filter @message like "session_id=<session-id>"
| sort @timestamp asc
```

### 自動停止の理由を調べる

```sql
fields @timestamp, @message
| filter @message like "event=auto_stop" or @message like "event=stop_scheduled"
| sort @timestamp desc
| limit 50
```

### バックアップの失敗を調べる

```sql
fields @timestamp, @message
| filter @message like /event=(backup_failed|backup_discard_failed|backup_skipped|trim_failed|save_failed)/
| sort @timestamp desc
| limit 50
```

### 起動時の失敗を調べる

```sql
fields @timestamp, @message
| filter @message like /event=(whitelist_invalid|whitelist_unavailable|mods_config_invalid|mod_download_failed|mod_checksum_mismatch|mod_cache_failed)/
| sort @timestamp desc
| limit 50
```

### 復元の拒否を調べる

```sql
fields @timestamp, @message
| filter @message like /event=(restore_applied|restore_rejected)/
| sort @timestamp desc
| limit 50
```

### 通知やメトリクスの送信失敗を調べる

```sql
fields @timestamp, @message
| filter @message like /event=(notify_failed|metric_failed)/
| sort @timestamp desc
| limit 50
```

## `/<prefix>/watchdog` で使うクエリ

### 強制停止した実行を調べる

```sql
fields @timestamp, @message
| filter @message like "watchdog_checked" and @message not like '"stopped": []'
| sort @timestamp desc
| limit 50
```

## `/<prefix>/notifier` で使うクエリ

### Lambda のエラーを調べる

```sql
fields @timestamp, @message
| filter @message like /ERROR|Task timed out/
| sort @timestamp desc
| limit 50
```

## Sources

- `../../construction/nfr-design/observability-design.md` §4
- `../../construction/nfr-design/security-design.md` §4
- `../../construction/nfr-design/reliability-design.md`
- `../../construction/nfr-design/performance-design.md`
- `../../construction/infrastructure-design/monitoring-design.md`
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `modules/minecraft_server/files/bin/`
- `lambda/watchdog/watchdog.py`
- `observability-setup-questions.md`（Q2）

## Assumptions & Open Questions

- 実際のロググループ名は `/<prefix>/...` です。`monitoring-design.md` の `/minecraft/prod/...` は実装と異なります（`alarms.md` の「設計との差異」を参照）。
- クエリの構文は CloudWatch Logs Insights の仕様に基づいて書いたもので、実行して確認したのは自動停止の確認に使うものだけです。
