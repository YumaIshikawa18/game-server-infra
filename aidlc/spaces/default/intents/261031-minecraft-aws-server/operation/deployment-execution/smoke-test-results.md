# スモークテスト結果

実施日は 2026-11-01 です。対象は Deploy run `41307645517` で作成した `prod` です。

| テスト | 方法 | 結果 |
|---|---|---|
| Minecraft のヘルスチェック | apply 後に Deploy が SSM 経由で実行 | 成功 |
| ポートへの接続 | 手元から TCP 25565 へ接続（12:46:00Z） | 成功 |
| **クライアントからの接続** | **本人が Minecraft クライアントで接続（Q18）** | **成功** |

クライアントからの接続は、チームで決めた walking skeleton の完了条件です。ポートへの TCP 接続だけでは完了とせず、本人の接続で完了を確認しました。

ヘルスチェックの成否は、Deploy の apply ジョブの成功と、インスタンスが `running` であることから判断しました。`scripts/cd/deploy.py` では、`running` のときにヘルスチェックが失敗すると apply ジョブも失敗します。

## Sources

- `deployment-execution-questions.md`（Q18）
- `../deployment-pipeline/deployment-strategy.md`
- `scripts/cd/deploy.py`
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41307645517

## Assumptions & Open Questions

None.
