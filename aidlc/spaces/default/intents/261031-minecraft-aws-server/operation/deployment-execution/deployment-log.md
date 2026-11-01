# デプロイ実行ログ

対象環境は `prod` です（`../environment-provisioning/environment-inventory.md`）。手順は `../deployment-pipeline/cd-config.md` と `../deployment-pipeline/deployment-strategy.md` に従いました。`infra` スコープのため Build and Test は対象外で、検証は必須チェック 11 件で行いました。

## 結果

| 項目 | 内容 |
|---|---|
| 成功した Deploy | run `41307645517` |
| 対象コミット | `2af7efa`（PR #5 の squash merge） |
| plan | 2026-11-01T12:40:58Z 開始、12:41:32Z 成功 |
| 承認 | 本人が `prod` を承認（Q17） |
| apply とスモークテスト | 2026-11-01T12:42:18Z 開始、12:45:14Z 成功 |
| 適用内容 | 追加 23 / 変更 0 / 削除 4 |
| 適用後の plan | 追加 0 / 変更 0 / 削除 0 |

削除 4 件は Lambda 2 関数とメール購読 2 件の作り直しです。ワールド用 EBS の削除や置き換えはありません。データベースの移行はありません（RDB を使いません）。

## 成功までの経過

| Deploy / PR | 結果 | 原因と対応 | 記録 |
|---|---|---|---|
| PR #3 / run `41295324864` | apply 前に失敗 | plan の比較と運用ロックの解除を修正（PR #4） | `initial-deployment-failure.md` |
| PR #4 / run `41296893187` | 部分作成後に失敗 | EC2、S3、SNS、SSM、Lambda の権限と設定を修正（PR #5）。Lambda は共有枠を使う構成に変更 | `partial-deployment-recovery.md` |
| PR #5 / run `41307645517` | 成功 | ― | 本ファイル |

PR #5 の CI では、作成済みリソースの refresh に必要な読み取り権限の不足が順に見つかりました。bootstrap の変更は本人がそのつど適用し、再 plan の差分 0 件を確認しました（Q11、Q13、Q14、Q15）。

## ロールバック

戻す場合は `../deployment-pipeline/rollback-runbook.md` に従い、revert PR と新しい承認付き apply を使います。state の巻き戻しや、リソースの直接削除は行いません。

## Sources

- `../deployment-pipeline/cd-config.md`
- `../deployment-pipeline/deployment-strategy.md`
- `../deployment-pipeline/rollback-runbook.md`
- `../environment-provisioning/environment-inventory.md`
- `deployment-execution-questions.md`（Q11 から Q18）
- https://github.com/YumaIshikawa18/game-server-infra/pull/5
- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41307645517

## Assumptions & Open Questions

- 以前に申請した Lambda 同時実行数の上限引き上げは、その後に承認され、上限は 1,000 になりました。今の構成は共有枠を使い、予約枠を指定していないので、構成と費用は変わりません。
