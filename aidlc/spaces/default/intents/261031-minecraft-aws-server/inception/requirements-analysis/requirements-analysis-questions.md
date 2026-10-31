# Requirements Analysis — 質問

Minecraft サーバーそのものに求めることを決めるための質問です。進め方（PR・CI・OIDC・state など）は Practices Discovery で決定済みのため、ここでは聞きません。

## Q1. [プロダクトマネージャー] Minecraft のエディションとバージョン

MOD 対応の方式やサーバーソフトの選択がこれで決まります。

A. Java Edition、最新リリース版に追従（MOD の対応状況を見て更新）
B. Java Edition、特定バージョンに固定（MOD の都合で、例: 1.20.1 など。バージョンを書いてください）
C. Bedrock Edition（統合版）も接続できるようにしたい
X. Other (please specify)

[Answer]: A

## Q2. [プロダクトマネージャー] MOD ローダー

「MOD にも対応したい」の中身です。使いたい MOD によってローダーが決まります。

A. Forge
B. NeoForge
C. Fabric
D. まだ決めていない。ローダーを差し替えられる構成にしておきたい（例: 設定値で Vanilla / Forge / NeoForge / Fabric を切り替え）
X. Other (please specify)

[Answer]: D

## Q3. [プロダクトマネージャー] MOD・設定ファイルの管理方法

サーバーに入れる MOD の一覧や `server.properties` などをどう管理・配布するかです。public リポジトリのため、ワールドデータや秘匿情報はリポジトリに置かない前提です。

A. MOD の一覧（名前・バージョン・ダウンロード URL）と設定ファイルをリポジトリで管理し、デプロイ時にサーバーへ反映（推奨: PR で MOD 追加をレビューできる）
B. CurseForge / Modrinth の modpack を指定して丸ごと導入
C. MOD の jar を S3 に手動で置き、サーバー起動時に同期
X. Other (please specify)

[Answer]: A

## Q4. [プロダクトマネージャー] 同時接続人数と使い方

インスタンスのサイズとコストの目安になります。

A. 自分＋友人で 2〜5 人程度、遊ぶときだけ
B. 5〜10 人程度、週に数回
C. 10 人以上、常時誰かがいる
X. Other (please specify)

[Answer]: A

## Q5. [プロダクトマネージャー] 稼働時間（常時稼働か、使うときだけ起動か）

EC2 のコストの大半は稼働時間で決まります。

A. 使うときだけ起動。手動で起動・停止できればよい（例: GitHub Actions の手動実行で start / stop）
B. A に加えて、誰も接続していない状態が一定時間続いたら自動停止
C. 常時稼働（24 時間 365 日）
X. Other (please specify)

[Answer]: B

## Q6. [プロダクトマネージャー] 月額コストの上限

AWS Budgets で超過アラートを出す基準にもします。

A. 月 1,000 円程度まで
B. 月 3,000 円程度まで
C. 月 5,000〜10,000 円程度まで
X. Other (please specify)

[Answer]: B

## Q7. [プロダクトマネージャー] ワールドデータのバックアップ

ワールドが消えると取り返しがつかないため、要件として決めておきたいです。

A. 定期バックアップ（例: 1 日 1 回、7 世代保持）＋停止時にもバックアップ（推奨）
B. 停止時のみバックアップ
C. バックアップは不要（ディスクのスナップショットのみで十分）
X. Other (please specify)

[Answer]: A

## Q8. [プロダクトマネージャー] 接続先アドレスと参加制限

友人に伝える接続先と、誰でも入れないようにする方法です。public リポジトリのため、IP やドメインはコードに書かない前提です。

A. 固定 IP（Elastic IP）で接続、ホワイトリスト（whitelist）で参加者を制限
B. 独自ドメイン（Route 53 等）で接続、ホワイトリストで参加者を制限
C. 起動のたびに変わる IP で十分（起動時に IP を通知してもらう）、ホワイトリストで制限
X. Other (please specify)

[Answer]: A

## Q9. [プロダクトマネージャー] 稼働中のバックアップ間隔（Q5・Q7 の確認）

Q5 で「使うときだけ起動＋無人時に自動停止」、Q7 で「定期＋停止時」を選んでいただきました。停止中はワールドが変わらないため、「1 日 1 回」の定期取得は稼働中にだけ意味があります。稼働中の定期バックアップをどの間隔にしますか？（保持は 7 世代の想定です）

A. 稼働中は 1 時間ごと＋停止時、直近 7 世代を保持
B. 稼働中は 6 時間ごと＋停止時、直近 7 世代を保持
C. 稼働中の定期取得はせず、停止時（自動停止を含む）だけ取得、直近 7 世代を保持
X. Other (please specify)

[Answer]: X. 提案の形で、稼働中1時間ごと＋停止時7世代で（稼働中の 1 時間ごとの取得は停止時の 7 世代とは別枠で短期保持。短期枠の保持数は [assumption] 直近 24 世代）

## Q10. [運用エンジニア] 無人で動く処理の結果をどこで知るか（レビュー指摘 R-01）

自動停止・毎時バックアップ・停止時バックアップはサーバー上で動くため、GitHub Actions の Job Summary には出ません。失敗や実行結果をどう知りますか？

A. CloudWatch のメトリクス＋アラームで、失敗時にメール通知（SNS）。成功の履歴は CloudWatch Logs で確認（推奨）
B. 定期実行の確認用 workflow が状態とバックアップ結果を Job Summary にまとめる（失敗時は workflow 失敗で GitHub から通知）
C. Discord の Webhook に結果を投稿
X. Other (please specify)

[Answer]: X. アラーム→SNS→Lambda→Discord、成功通知もDiscord、メール保険あり

## Q11. [運用エンジニア] 自動停止の処理中に start が来たら（レビュー指摘 R-03 a）

A. 自動停止（バックアップ→停止）が終わるのを待ってから起動する（推奨）
B. start を失敗させ「停止処理中」と表示する（少し待ってやり直す）
X. Other (please specify)

[Answer]: A

## Q12. [運用エンジニア] 稼働中にインスタンスの置き換えが必要な apply が来たら（レビュー指摘 R-03 b）

AMI 更新などでインスタンスが作り直される変更の扱いです。何もしないと最大 1 時間分のプレイが失われ得ます。

A. apply の前に自動で保存＋バックアップ＋停止してから置き換える（推奨）
B. 稼働中は置き換えを伴う apply を拒否する（先に stop してから apply）
C. 特に対策しない（最大 1 時間分の損失を許容）
X. Other (please specify)

[Answer]: A

## Q13. [運用エンジニア] バックアップからの復元はいつ実行できるか（レビュー指摘 R-03 c）

A. 停止中のみ実行できる（推奨）
B. 稼働中でも実行でき、自動で停止→復元→起動する
X. Other (please specify)

[Answer]: A

## Q14. [プロダクトマネージャー] 「最新版に追従」の意味（レビュー指摘 R-04）

起動のたびに最新を取りに行くと、勝手にバージョンが上がって MOD が動かなくなる恐れがあります。

A. バージョンは常にリポジトリに具体値で固定し、新バージョンが出たら PR で上げる（推奨）
B. 起動のたびに最新リリースを自動で取得する
X. Other (please specify)

[Answer]: A

## Q15. [プロダクトマネージャー] 友人の PC への MOD 配布（レビュー指摘 R-04）

MOD 入りサーバーには、クライアント側にも同じ MOD・ローダーが必要です（サーバー専用 MOD を除く）。

A. 範囲外。友人は各自でリポジトリの MOD 一覧を見て入れる
B. リポジトリの MOD 一覧からクライアント向けの導入手順（README）を用意する
C. クライアント用の MOD 一式を配布する仕組みも作る（S3 の署名付き URL 等）
X. Other (please specify)

[Answer]: B

## Q16. [プロダクトマネージャー] 仮置きの数値（レビュー指摘 R-05）

次の値を仮置きしています: 無人で自動停止まで 30 分 / 応答なしで強制停止まで 2 時間 / 月の稼働 40 時間程度（コスト見積もりの前提）/ 起動から接続可能まで 10 分以内 / MOD は最大 50 個程度。

A. すべてこのままでよい
B. いくつか変えたい（どれをどう変えるか書いてください）
X. Other (please specify)

[Answer]: B. 応答がない場合の強制停止まで 1 時間に変更、それ以外はそのまま（サマリー確認時の変更）

## Q17. [品質エンジニア] 性能・成功率の目標の扱い（レビュー指摘 R-06）

「5 人で TPS 18 以上」「起動成功率 95%」は、測る仕組みを作るとその分の手間とコストがかかります。あわせて、whitelist を確実に効かせるため `online-mode=true`（正規アカウント検証）を必須にします。

A. TPS と成功率は「目安」とし、測定の仕組みは作らない。`online-mode=true` は必須（推奨）
B. TPS はサーバーログ／RCON で定期取得して CloudWatch に送り、成功率は workflow の履歴で測る。`online-mode=true` は必須
X. Other (please specify)

[Answer]: A

## Consolidated Summary Confirmation

Does this all look correct before I generate the requirements artifact?

- Looks correct
- Request changes

[Answer]: Looks correct

## Requested Changes Feedback

[Answer]: 応答がない場合の強制停止まで1時間でそれ以外はOK
