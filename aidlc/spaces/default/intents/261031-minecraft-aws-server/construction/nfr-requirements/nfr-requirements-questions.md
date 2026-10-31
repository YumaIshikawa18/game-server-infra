# NFR Requirements — 質問

要件（`requirements.md`）で決めた数値目標を、技術選定とコストに落とすための質問です。金額は東京リージョンの 2026 年時点の概算で、要確認です（為替は 1 USD = 150 円で換算）。月 40 時間稼働の前提で計算しています。

## Q1. [アーキテクト] サーバーのメモリ（インスタンスサイズ）

MOD を最大 50 個程度入れ、5 人で遊ぶ前提です。MOD 入りサーバーはメモリ消費が大きくなります。

A. 8 GB（例: m7g.large / t3.large 相当）。稼働 40 時間で月 600〜700 円前後（推奨: 50 MOD・5 人なら多くの場合これで足ります）
B. 16 GB（例: m7g.xlarge 相当）。月 1,200〜1,400 円前後（大型 MOD パックも視野に入れる場合）
C. 4 GB（例: t4g.medium 相当）。月 300 円前後（MOD を少なめにする場合）
X. Other (please specify)

[Answer]: X. 選べるようにしたい。デフォルトはBのイメージ。（インスタンスタイプを設定値で選べるようにし、既定は 16 GB 相当）

## Q2. [アーキテクト] CPU アーキテクチャ

A. ARM（Graviton）。同等性能で x86 より 1〜2 割安い。Java サーバーは問題なく動きますが、ネイティブライブラリを含む一部の MOD は動かない可能性があります（推奨）
B. x86（Intel / AMD）。MOD の互換性を最優先にする
X. Other (please specify)

[Answer]: A

## Q3. [アーキテクト] 購入方式

A. オンデマンド。遊んでいる途中で止められることはない（推奨: 月 40 時間なら差額は月数百円程度）
B. スポットインスタンス。6〜7 割安くなるが、AWS の都合で 2 分前の予告で中断されることがある（その場合の損失は直近の毎時バックアップまで）
X. Other (please specify)

[Answer]: A

## Q4. [開発者] サーバーの動かし方（MOD ローダー切り替えの実現方法）

ローダー（vanilla / forge / neoforge / fabric）とバージョンを設定値で切り替える要件（FR2.1, FR2.2）の実現方法です。

A. Docker 上で、広く使われている公開イメージ `itzg/minecraft-server` を使う。ローダーとバージョンは環境変数で切り替え、MOD の取得もイメージの機能を使える（推奨: 切り替えの仕組みを自作しなくてよい）
B. Docker を使わず、systemd と自作スクリプトでサーバー jar とローダーを導入する（依存が少ないが、切り替えの仕組みを自作する）
X. Other (please specify)

[Answer]: A

## Q5. [運用エンジニア] バックアップの保存先

A. ワールドを圧縮して S3 に保存し、世代の削除はスクリプトで行う（推奨: ワールド単位で扱えて復元が簡単。月数十円程度）
B. EBS スナップショット（ディスク丸ごと）。Data Lifecycle Manager で世代管理する（ディスク全体の復元になる）
X. Other (please specify)

[Answer]: A

## Q6. [アーキテクト] リージョン

A. 東京（ap-northeast-1）（推奨: 遅延が最小で、サービスも揃っている）
B. 大阪（ap-northeast-3）（料金はほぼ同じで、一部サービスが少ない）
X. Other (please specify)

[Answer]: A

## Consolidated Summary Confirmation

Does this all look correct before I generate the artifact?

- Looks correct
- Request changes

[Answer]: Looks correct
