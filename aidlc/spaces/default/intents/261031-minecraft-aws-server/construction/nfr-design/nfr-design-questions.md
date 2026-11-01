# NFR Design — 質問

NFR Requirements で決めた要件を、どう実現するかを決めるための質問です。要件の段階で決まっていることは、ここでは聞きません。

## Q1. [開発者] MOD の取得と検証の方法

チェックサムを検証してから配置する要件（FR3.2 / NFR5.13）を、どう実現しますか？

A. 自作の検証スクリプト（起動前の systemd ユニット）で、リポジトリの MOD 一覧からダウンロードし、sha256 を照合してから `mods/` に置く。itzg イメージは配置済みの MOD をそのまま読むだけにする（推奨: 検証の仕組みが自分の管理下にあり、テストも書ける）
B. itzg イメージの `MODS_FILE`（URL 一覧）で取得し、起動後に検証スクリプトでハッシュを照合する（取得はイメージ任せにできるが、照合は事後になる）
C. itzg イメージの Modrinth 連携（プロジェクト ID とバージョン ID を指定）を使う。Modrinth 以外で配布される MOD は扱えない
X. Other (please specify)

[Answer]: A

## Q2. [アーキテクト] ネットワーク構成

A. 専用の VPC を作り、パブリックサブネット 1 つに置く。NAT ゲートウェイは置かない（NAT は月 5,000 円以上かかるため）。IPv4 のみ（推奨）
B. アカウントの既定 VPC を使う（作るものは少ないが、他の用途と混ざる。コードで管理しにくい）
X. Other (please specify)

[Answer]: A

## Q3. [開発者] サーバー側スクリプトの言語

自動停止の監視、バックアップ、停止処理、MOD 検証などのスクリプトです。

A. Bash と systemd（unit / timer）。依存が少なく、AMI にそのまま入っている（推奨。ただし ShellCheck を CI に加える）
B. Python（Amazon Linux 2023 に標準で入っている）。複雑な処理は書きやすく、pytest でテストできる
X. Other (please specify)

[Answer]: A

## Q4. [リリースエンジニア] start ワークフローが「接続可能になった」と判断する方法

A. SSM Run Command でサーバー上の確認スクリプトを繰り返し実行する。server list ping が成功するまで待ち、10 分でタイムアウトする（推奨: 結果がすぐ分かり、Elastic IP をログに出さずに済む）
B. CloudWatch の `ServerUp` メトリクスが 1 になるまで待つ（メトリクスの反映に 1〜2 分の遅れがある）
X. Other (please specify)

[Answer]: A

## Consolidated Summary Confirmation

Does this all look correct before I generate the artifact?

- Looks correct
- Request changes

[Answer]: Looks correct
