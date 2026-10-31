# Performance Requirements

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`（NFR2, NFR3）、`nfr-requirements-questions.md`（Q1〜Q4）。
infra スコープのため functional-design は実行しておらず、`functional-spec` / `rules` はありません。そのため、本書は requirements.md から直接導いています。

## 性能目標

| ID | 要件 | 目標値 | 合否の判定方法 | 出典 |
|---|---|---|---|---|
| NFR2.1 | 同時接続人数 | 5 人が同時に参加できる | 5 アカウントで接続し、全員がワールドに入れる（手動確認） | NFR2, [Q4] |
| NFR2.2 | サーバー TPS（目安） | 平常時 18 以上 | 目安扱い。`/forge tps` やログの "Can't keep up" 警告で体感確認し、測定基盤は作らない | NFR2, Q17 |
| NFR2.3 | MOD 規模 | 最大 50 個程度で起動・プレイできる | 50 個程度の構成で起動が完了する | NFR2, Q16 |
| NFR2.4 | メモリ割り当て | インスタンスタイプを変数で選べる。既定は 16 GB 相当（`m7g.xlarge` 想定）。JVM ヒープはインスタンスメモリの約 75%（既定 12 GB）を上限にし、変数で上書きできる | `terraform test`（plan モード）で、既定のインスタンスタイプとヒープ値を検証する | [Q1] |
| NFR2.5 | CPU アーキテクチャ | `cpu_architecture` 変数（`arm64` / `x86_64`）で選ぶ。既定は `arm64`（Graviton）。AMI はこの変数に合う SSM パラメータから取得する | `terraform test` で、既定が arm64 であること、および `instance_type` と `cpu_architecture` の組み合わせが不整合なら plan が失敗することを検証する | [Q2] |
| NFR3.1 | 起動時間 | start ワークフローの開始から接続可能になるまで 10 分以内。自動停止の完了待ちの時間は含めない | start ワークフローの所要時間（Job Summary に記録） | NFR3, Q16 |
| NFR3.2 | 起動時間の内訳の目安 | インスタンス起動 2 分以内、コンテナイメージと MOD の取得 3 分以内、ワールド読み込み 5 分以内 | 起動完了の通知に所要時間を載せる | NFR3（導出） |

## 前提とリソース制約

- インスタンスタイプは `instance_type` 変数で切り替えます。変数バリデーションで許可するのは、メモリ 8 GB 以上の汎用・メモリ最適化タイプです（許可リストで管理します。例: arm64 なら `m7g.large` / `m7g.xlarge` / `r7g.large`、x86_64 なら `m7i.large` / `m7i.xlarge`）。[Q1] [Q2]
- ARM ではネイティブライブラリを含む一部の MOD が動かない場合があります。その場合は FR3.2（起動中止と通知）と FR4.4（起動失敗）で検知し、`cpu_architecture = "x86_64"` と x86 のインスタンスタイプに変える PR で切り替えます（インスタンスは置き換わり、FR4.5 の手順でワールドは保持されます）。
- EBS は gp3 を使い、ベースライン（3,000 IOPS / 125 MB/s）で足りる想定です。ワールド読み込みが遅い場合は IOPS を変数で上げられるようにします。
- 起動時間を短くするため、コンテナイメージはタグではなく digest で固定します。MOD はチェックサム付きで取得し、取得済みで一致するものは再取得しません。

## Sources

- [desc] / `requirements.md` NFR2, NFR3、Q16, Q17
- `nfr-requirements-questions.md` [Q1] [Q2] [Q4]

## Assumptions & Open Questions

- [assumption] JVM ヒープはインスタンスメモリの約 75% とする。
- [assumption] 起動時間の内訳（2 分 / 3 分 / 5 分）は目安であり、合否は NFR3.1 の合計で判定する。
- Open: 16 GB で足りない MOD 構成になった場合の上位タイプ（`m7g.2xlarge` など）は、予算（NFR1）と相談して決める。
