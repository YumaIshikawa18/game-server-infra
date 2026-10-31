# Scalability Requirements

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`（NFR1, NFR2）、`nfr-requirements-questions.md`（Q1〜Q3）。

このシステムは 1 台のサーバーで 2〜5 人が遊ぶ前提のため、水平スケールは行いません。ここで扱うのは「縦に上げ下げできること」と「データの増加に耐えること」です。

| ID | 要件 | 目標 / 合否基準 | 出典 |
|---|---|---|---|
| NFR2.6 | 縦のスケール | `instance_type` 変数を変えて apply するだけで、インスタンスサイズを上下できる。ワールドは別の EBS に置き、置き換え後も残る（FR1.3, FR4.5） | [Q1], FR1.3 |
| NFR2.7 | 人数の上限 | `max-players` を設定ファイルで管理する。既定は 10、想定は 5 人 | NFR2 |
| NFR2.8 | ワールドの増加 | ワールド用 EBS は既定 30 GB の gp3 とし、変数で拡張できる。使用率が 80% を超えたら警告を通知する（observability-requirements.md の NFR7.6） | NFR2（導出） |
| NFR2.9 | バックアップの増加 | 1 世代あたりのサイズを通知とメトリクスに載せる。バケット全体（旧バージョンを含む）が 80 GB を超えたら、コスト警告を通知する | NFR1, FR6 |
| NFR1.1 | コストの上限 | 月額見積もり（下表）が 3,000 円以下であること。Budgets の 80% / 100% 通知（FR9.1）で実績を監視する | NFR1 |

## 月額コスト見積もり（東京、オンデマンド、月 40 時間）

金額は 2026 年時点の概算で、要確認です。1 USD = 150 円で換算しています。

| 項目 | 前提 | 月額（概算） |
|---|---|---|
| EC2 `m7g.xlarge`（16 GB, 既定） | 約 $0.21/h × 40 h | 約 1,260 円 |
| Elastic IP（パブリック IPv4） | $0.005/h × 730 h（停止中も課金） | 約 550 円 |
| EBS gp3（ルート 8 GB + ワールド 30 GB） | 約 $0.096/GB-月 × 38 GB | 約 550 円 |
| S3（バックアップ） | 現行は 1 世代 1 GB × 31 世代 ≒ 31 GB。旧バージョンは 7 日分で、稼働中の毎時取得で入れ替わる世代を最大 +40 GB と見込む。合計で最大約 70 GB、Standard | 約 120〜270 円 |
| CloudWatch（アラーム 5〜8 個、ログ少量） | 約 $0.10/アラーム | 約 100 円 |
| Lambda / SNS / SSM / Budgets | 無料枠の範囲 | 約 0〜10 円 |
| データ転送（アウト） | 月 100 GB までの無料枠内の想定 | 0 円 |
| **合計** | | **約 2,600〜2,750 円** |

- 予算 3,000 円に対して、余裕は約 250〜400 円です。16 GB を既定にしたこと（[Q1]）と、停止中も Elastic IP に課金されること（FR8.1）の影響が大きくなっています。
- 稼働が月 60 時間を超えると、3,000 円を超える見込みです。その場合は Budgets の通知（FR9.1）で気づけます。
- `instance_type` を `m7g.large`（8 GB）にすると、合計は約 1,950 円になる見込みです。

## Sources

- `requirements.md` NFR1, NFR2, FR1.3, FR4.5, FR6, FR9.1
- `nfr-requirements-questions.md` [Q1] [Q2] [Q3]

## Assumptions & Open Questions

- [assumption] ワールドの 1 世代は圧縮後 1 GB 程度とする。MOD の構成によって大きく変わるため、運用開始後にメトリクスで見直す。
- [assumption] データ転送は無料枠内に収まる（5 人 × 40 時間の Minecraft 通信）。
- Open: 単価は着工前に AWS Pricing Calculator で再確認する。
