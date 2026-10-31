# Construction → Operation Verification

## 適用範囲

infra 計画では units-generation / code-generation / build-and-test が SKIP。Unit DAG はなく、cross-unit-traceability.md や Unit ごとの code-generation/traceability.json は生成されない設計である。それらの欠落を「実装・テスト済み」と読み替えない。

## 確認結果

| 対象 | 結果 | 根拠 |
|---|---|---|
| NFR Requirements → NFR Design → Infrastructure Design | 設計上の対応表あり | 各段階の traceability.json。infrastructure-design は 35 個の upstream ID に対応を記載 |
| CI の品質基準 | 設定済み | ci-pipeline/ci-config.md、quality-gates.md、.github/workflows/pr.yml |
| fork PR のマージ防止 | 上流の矛盾を解消 | ci-pipeline Q1。skip を失敗に変更 |
| bootstrap の検査対象 | 上流の矛盾を解消 | ci-pipeline Q2。静的検査とモックテストを含める |
| CI 自体のテスト | ローカル成功 | tests/ci の 15 件、構文・workflow 構成検証 |
| 全 Unit のビルド・テスト | N/A | Unit を生成しない計画 |
| AWS インフラの実装・実 plan | 未実行 | 本体はまだ存在しない。Environment Provisioning で作成して検証する |

## 判定

CI 設定とインフラ設計の引き継ぎは可能。本番デプロイ可能という判定ではない。後続で本体・テスト・バックエンド・認証設定を用意し、実 CI を全件通すまで実行検証は未完了とする。

人による承認は CI Pipeline の承認で確認する。ここで自動承認や、未実行のビルド・テストの成功を記録しない。
