# トレーシングの設定

**X-Ray などの分散トレーシングは使いません。** `../../construction/infrastructure-design/monitoring-design.md` の決定どおりです。

## 理由

- サービス間の呼び出しが少なく、調べたいのは主に 1 台のホストの動作です。
- Minecraft サーバー本体は計装できません。
- 1 回の稼働は `session_id` で追跡できます（`../../construction/nfr-design/observability-design.md` §4）。

## 代わりの追跡方法

起動から停止までの 1 回の稼働には、起動時に生成する `session_id` が付きます。調べ方は `log-queries.md` の「1 回の稼働を追う」にあります。

## 見直す条件

複数のサービスをまたぐ処理が増え、ログだけでは遅延や失敗の場所を特定できなくなったときに検討します。

## Sources

- `../../construction/infrastructure-design/monitoring-design.md` Logs & Tracing
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../../construction/nfr-design/observability-design.md` §4
- `../../construction/nfr-design/performance-design.md`
- `../../construction/nfr-design/reliability-design.md`
- `../../construction/nfr-design/security-design.md`
- `observability-setup-questions.md`

## Assumptions & Open Questions

None.
