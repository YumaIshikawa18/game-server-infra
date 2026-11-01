# Requirements — MOD 対応 Minecraft サーバー on AWS

## 1. Intent analysis

- **やりたいこと**: 個人の AWS アカウント（`aws login --profile personal`）上に、自分と友人 2〜5 人が遊ぶ Java Edition の Minecraft サーバーを建てる。MOD を入れて遊べるようにする。[desc] [Q1] [Q4]
- **進め方の前提**: インフラは Terraform でゼロから作り、GitHub Actions の CI/CD と、保護された `master` への PR で変更を入れる（`team-practices.md` で確定済み）。[desc] [memory:M1]
- **成功の姿**: 次の 5 つを満たすこと。[Q5] [Q6] [Q7] [Q8] [Q10]
  - 遊びたいときに自分で起動でき、友人が固定の接続先から入れる。
  - 停止を忘れても、無駄な課金が続かない。
  - ワールドを失わない。
  - 起きたことが Discord で分かる。
  - 月 3,000 円程度に収まる。
- **種類 / 規模 / 複雑さ**: 新規構築（Greenfield）のインフラ。環境は prod の 1 つで、複雑さは Standard。

## 2. Functional requirements

### FR1 サーバーの提供（Walking skeleton）
- **FR1.1** EC2 上で Minecraft Java Edition サーバーを起動し、TCP 25565 で待ち受けること。[desc] [Q1]
  - AC1.1.1 Given `envs/prod` が apply 済みで、サーバーが起動している。When 同じバージョンの Minecraft クライアントから接続先アドレスに接続する。Then ワールドに参加できる。
  - AC1.1.2 Given サーバーが起動処理中である。When 接続を試みる。Then 接続は拒否されるかタイムアウトする。起動完了後に再試行すれば成功する。
- **FR1.2** サーバーは Minecraft の EULA に同意した状態で起動すること。同意は設定値として明示すること。[assumption]
  - AC1.2.1 Given 新しいインスタンスで初めて起動する。When サーバープロセスが開始する。Then EULA 未同意で止まることなく起動が完了する。
- **FR1.3** ワールドデータは、インスタンスを作り直しても消えない永続ストレージに置くこと。[Q7]
  - AC1.3.1 Given ワールドで建築した後に、インスタンスを置き換える apply をした。When 再起動して接続する。Then 建築物が残っている。
  - AC1.3.2 Given ワールドデータがまだない（初回起動）。When 起動する。Then 新しいワールドが生成され、起動が完了する。
- **FR1.4** `server.properties` の `online-mode` は必ず `true` とすること。[Q17]
  - AC1.4.1 Given 設定ファイルで `online-mode=false` を指定した。When CI のテストを実行する。Then 失敗し、マージできない。
  - AC1.4.2 Given 正規アカウントでないクライアントがある。When 接続する。Then 認証エラーで拒否される。

### FR2 バージョンと MOD ローダー
- **FR2.1** Minecraft のバージョンは、リポジトリ内の設定値に具体的なバージョン番号（例: `1.21.x`）で固定すること。`latest` のような実行時に解決される指定は使わないこと。新しいバージョンへの更新は、その値を変える PR で行うこと。[Q1] [Q14]
  - AC2.1.1 Given バージョンの設定値を変更する PR がマージされ、apply が承認された。When サーバーが再起動する。Then 指定したバージョンで起動する。
  - AC2.1.2 Given 新しい Minecraft バージョンが公開された。When 設定値を変えずにサーバーを再起動する。Then 以前と同じバージョンで起動する。
  - AC2.1.3 Given バージョンに `latest` などの固定でない値を指定した。When `terraform plan` を実行する。Then 変数バリデーションで失敗する。
- **FR2.2** MOD ローダーを設定値で `vanilla` / `forge` / `neoforge` / `fabric` から選べること。ローダーのバージョンも、FR2.1 と同様に具体値で固定すること。[Q2] [Q14]
  - AC2.2.1 Given ローダーに `fabric` を指定した。When 起動する。Then Fabric サーバーとして起動し、ログに Fabric のロードが記録される。
  - AC2.2.2 Given 対応外の値（例: `quilt`）を指定した。When `terraform plan` を実行する。Then 変数バリデーションで失敗し、許可される値が表示される。
  - AC2.2.3 Given 指定したローダーが、指定した Minecraft バージョンに対応していない。When 起動する。Then 起動失敗が FR4.4 のとおり報告される。前のワールドデータは壊れない。

### FR3 MOD・設定ファイルの管理
- **FR3.1** サーバーに入れる MOD の一覧をリポジトリ内のファイルで管理すること。各項目は名前・バージョン・ダウンロード URL・チェックサム、およびサーバー専用かクライアントにも必要かの区分を持つこと。[Q3] [Q15]
  - AC3.1.1 Given MOD を 1 件追加する PR がマージされ、apply が承認された。When サーバーが再起動する。Then その MOD が導入された状態で起動する。
  - AC3.1.2 Given 一覧から MOD を 1 件削除した。When 反映する。Then サーバーからその MOD が取り除かれる。
- **FR3.2** MOD の取得時にチェックサムを検証すること。ダウンロード失敗やチェックサム不一致があれば、その MOD を導入せずに起動を中止し、失敗した MOD 名をログと通知（FR8.2）に出すこと。[assumption]
  - AC3.2.1 Given 一覧の URL が 404 を返す。When 反映する。Then 起動は中止され、該当 MOD 名と理由が通知される。
  - AC3.2.2 Given チェックサムが一致しない。When 反映する。Then その jar は配置されない。
- **FR3.3** `server.properties` などのサーバー設定ファイルをリポジトリで管理し、デプロイ時に反映すること。秘匿値（RCON パスワード等）はリポジトリに書かず、実行時に秘匿値ストアから注入すること。[Q3] [memory:M1]
  - AC3.3.1 Given `server.properties` の `difficulty` を変更する PR が反映された。When 再起動する。Then 新しい難易度で起動する。
  - AC3.3.2 Given リポジトリの全ファイルを対象にする。When 秘匿値（パスワード、アカウント ID、ARN、Webhook URL）を検索する。Then 1 件も見つからない。
- **FR3.4** ワールドデータはリポジトリに置かないこと。[Q3]
  - AC3.4.1 Given `.gitignore` とリポジトリの内容を確認する。When ワールドのディレクトリ（`world/` 等）や `.mca` / `level.dat` を検索する。Then 追跡対象に 1 件もない。
- **FR3.5** MOD 一覧から、友人がクライアント側で導入するための手順書（README）を用意すること。手順書には、クライアントに必要な MOD（サーバー専用を除く）とローダー・バージョンを載せること。[Q15]
  - AC3.5.1 Given MOD 一覧にクライアント必須の MOD が 3 件、サーバー専用が 1 件ある。When 手順書を確認する。Then クライアント必須の 3 件と、ローダー・Minecraft のバージョンが記載されている。
  - AC3.5.2 Given MOD 一覧を変更する PR を作った。When CI を実行する。Then 手順書の MOD 一覧が一覧ファイルと食い違っていれば失敗する。

### FR4 起動・停止の操作
- **FR4.1** GitHub Actions の手動実行（workflow_dispatch）でサーバーを起動できること。[Q5]
  - AC4.1.1 Given サーバーが停止している。When start ワークフローを実行する。Then インスタンスが起動し、Minecraft が接続を受け付けた時点でワークフローが成功する。
  - AC4.1.2 Given サーバーがすでに起動している。When start を実行する。Then 何も変えずに成功し、すでに起動中であることを Job Summary に出す。
- **FR4.2** GitHub Actions の手動実行でサーバーを停止できること。停止の前にワールドを保存し、バックアップを取ること（FR6.2）。[Q5] [Q7]
  - AC4.2.1 Given サーバーが起動している。When stop を実行する。Then ワールドの保存とバックアップの取得を終えてから、インスタンスが停止する。
  - AC4.2.2 Given サーバーがすでに停止している。When stop を実行する。Then 何も変えずに成功する。
- **FR4.3** start / stop / apply / restore は同時に走らないこと。サーバー上で自動停止の処理中（バックアップ→停止）に start を受けた場合は、自動停止の完了を待ってから起動すること。[Q11] [assumption]
  - AC4.3.1 Given start の実行中である。When stop を実行する。Then stop は start の完了を待ってから実行される。
  - AC4.3.2 Given 自動停止のバックアップ取得中である。When start を実行する。Then 自動停止が完了してインスタンスが停止した後に起動処理が始まり、最終的に接続できる。自動停止の完了を待つ時間は NFR3 の 10 分に含めない。（承認前の確認での回答）
  - AC4.3.3 Given 停止処理（手動停止・自動停止・置き換え前の停止）が始まった。When 毎時バックアップの時刻になる。Then 毎時バックアップはスキップされ、停止時バックアップ（FR6.2）だけが取得される。（承認前の確認での回答）
- **FR4.4** start の途中で Minecraft サーバーが起動に失敗した場合、start ワークフローを失敗として終え、失敗を通知すること（FR8.2）。インスタンスは課金を止めるため停止すること。[assumption]
  - AC4.4.1 Given MOD の不整合で Minecraft が起動しない。When start を実行する。Then 10 分以内（NFR3）にワークフローが失敗で終わり、Discord に失敗が通知され、インスタンスは停止している。
- **FR4.5** 稼働中にインスタンスの置き換えを伴う apply を実行する場合は、置き換えの前に自動で保存・バックアップ・停止を行うこと。[Q12]
  - AC4.5.1 Given サーバーが稼働中で、plan にインスタンスの置き換えが含まれる。When apply が承認されて実行される。Then 置き換えより前に停止時バックアップ（FR6.2）が取得され、インスタンスが停止している。
  - AC4.5.2 Given サーバーが停止中で、plan にインスタンスの置き換えが含まれる。When apply を実行する。Then 追加のバックアップなしで置き換えが行われる。

### FR5 無人時の自動停止
- **FR5.1** 接続プレイヤーが 0 人の状態が 30 分（設定値で変更可）続いたら、サーバーを自動で停止すること。停止の前にワールドを保存し、バックアップを取ること。[Q5] [Q16]
  - AC5.1.1 Given 最後のプレイヤーが切断した。When 30 分間誰も接続しない。Then バックアップを取ったうえでインスタンスが停止し、Discord に自動停止が通知される。
  - AC5.1.2 Given 0 人になってから 20 分後に誰かが接続した。When その後も接続が続く。Then 停止しない（タイマーはリセットされる）。
  - AC5.1.3 Given 起動直後で、まだ誰も接続していない。When 30 分経つ。Then 停止する。
- **FR5.2** 人数を確認できない場合（サーバー無応答など）は、すぐには停止しないこと。無応答が 1 時間（設定値で変更可）続いた場合は、課金を止めるために停止し、通知すること。[Q16]
  - AC5.2.1 Given サーバーが人数確認に応答しない。When 無応答が 59 分続く。Then 停止しない。
  - AC5.2.2 Given サーバーが人数確認に応答しない。When 無応答が 1 時間続く。Then インスタンスが停止し、Discord に「無応答による強制停止」と通知される。
  - AC5.2.3 Given 無応答が 40 分続いた後に応答が戻り、プレイヤーが 1 人いる。When その後も接続が続く。Then 停止しない。

### FR6 ワールドのバックアップと復元
- **FR6.1** 稼働中は 1 時間ごとにワールドのバックアップを取り、短期枠として直近 24 世代を保持すること。[Q9] [assumption]（保持数）
  - AC6.1.1 Given 3 時間稼働した。When バックアップを一覧する。Then 稼働中の定期バックアップが 3 件ある。
  - AC6.1.2 Given 短期枠に 24 世代ある。When 25 件目を取得する。Then 短期枠の最も古い 1 件が削除され、停止時枠には影響しない。
- **FR6.2** 停止時（手動停止・自動停止・置き換え前の停止）にワールドのバックアップを取り、停止時枠として直近 7 世代を保持すること。[Q7] [Q9] [Q12]
  - AC6.2.1 Given 停止時枠に 7 世代ある。When 停止して 8 件目を取得する。Then 停止時枠の最も古い 1 件が削除される。
- **FR6.3** バックアップでは、書き込み中の不完全な状態を取らないこと。取得中はワールドへの書き込みを止め（`save-off` + `save-all flush` 相当）、取得後に再開すること。[assumption]
  - AC6.3.1 Given プレイヤーが建築中である。When 定期バックアップを取得し、そのバックアップから復元する。Then ワールドは破損なく読み込め、取得時点までの建築が残っている。
  - AC6.3.2 Given バックアップ取得中である。When 取得が終わる。Then 自動保存が再開されている（`save-on` 相当）。
- **FR6.4** バックアップに失敗した場合は、失敗を通知すること（FR8.2）。停止時の取得に失敗した場合でも停止は行い、ワールドの永続ストレージ（FR1.3）は削除しないこと。[assumption]
  - AC6.4.1 Given 定期バックアップの保存先に書き込めない。When 定期取得の時刻になる。Then Discord とメールに失敗が通知され、サーバーは稼働を続ける。
  - AC6.4.2 Given 停止時バックアップが失敗する。When stop を実行する。Then インスタンスは停止し、ワールドの永続ストレージは残り、失敗が通知される。
- **FR6.5** 任意のバックアップからワールドを復元できる手段（GitHub Actions の手動ワークフロー）を用意すること。復元はサーバーの停止中にのみ実行できること。[Q7] [Q13]
  - AC6.5.1 Given サーバーが停止中で、2 世代前のバックアップを指定した。When 復元を実行して起動する。Then その時点のワールド状態で接続できる。
  - AC6.5.2 Given サーバーが稼働中である。When 復元を実行する。Then 何も変更せずに失敗し、「停止してから実行してください」と表示される。

### FR7 デプロイ（CI/CD）
- **FR7.1** PR で fmt / validate / tflint / Checkov / `terraform test` / plan を実行し、結果をサマリーのみで PR に出すこと（`team-practices.md` の Testing Posture / Deployment）。[memory:M1]
  - AC7.1.1 Given `terraform fmt` に違反するファイルを含む PR がある。When CI を実行する。Then fmt のチェックが失敗し、マージできない。
  - AC7.1.2 Given 正常な PR がある。When CI を実行する。Then すべてのチェックが成功し、PR には追加・変更・削除の件数とリソースアドレスのサマリーだけが投稿される。
  - AC7.1.3 Given plan に Elastic IP やアカウント ID を含む値がある。When サマリーが投稿される。Then それらの値は PR コメントにも Actions ログにも出ていない（マスクされている）。
- **FR7.2** `master` へのマージ後、GitHub Environments `prod` の手動承認を経て apply すること。[memory:M1]
  - AC7.2.1 Given PR が `master` にマージされた。When deploy ワークフローが走る。Then 承認待ちで止まり、承認されるまで apply されない。
  - AC7.2.2 Given 承認待ちの deploy がある。When 承認を却下する。Then apply は行われない。
- **FR7.3** apply 後にスモークテストとして、サーバーポートへの接続確認を自動で行うこと。サーバーが停止中の場合は「停止中のため確認を省略」と明示すること。[memory:M1] [assumption]
  - AC7.3.1 Given 稼働中のサーバーに apply した。When スモークテストが走る。Then 25565 への接続が成功すれば成功とする。失敗した場合はワークフローが失敗し、Discord に通知される。
  - AC7.3.2 Given 停止中のサーバーに apply した。When スモークテストが走る。Then 「停止中のため確認を省略」と Job Summary に出て、成功扱いになる。
- **FR7.4** state 用 S3 バケットなどを作る `bootstrap/` は、手元から 1 回だけ apply できること（CI の対象外）。[memory:M1]
  - AC7.4.1 Given 空の AWS アカウントがある。When 手元で `--profile personal` を指定して `bootstrap/` を apply する。Then state 用バケットと OIDC 用の設定が作られ、以後 `envs/prod` の CI がその state を使える。
  - AC7.4.2 Given すでに `bootstrap/` が apply 済みである。When もう一度 apply する。Then 差分なしで終わる。

### FR8 接続先・参加制限・通知
- **FR8.1** 接続先は Elastic IP（固定 IP）とすること。IP アドレスはコード・ログ・PR コメントに出さないこと。友人への共有は、本人が Discord に手動でピン留めして行う。Elastic IP は誤って解放されないようにすること（インスタンスの置き換えや通常の apply では、同じ IP を維持する）。[Q8] [memory:M1]
  - AC8.1.1 Given 停止してから再度起動した。When 同じアドレスに接続する。Then 接続できる。
  - AC8.1.2 Given インスタンスを置き換える apply をした。When 起動後に同じアドレスに接続する。Then 接続できる。
  - AC8.1.3 Given Elastic IP を削除する変更を含む plan がある。When apply しようとする。Then 削除は拒否される（`prevent_destroy` 等で保護）。
- **FR8.2** 次のイベントを Discord に投稿すること。経路は CloudWatch アラーム / イベント → SNS → Lambda → Discord Webhook とする。同じ SNS トピックにメールを登録し、Discord に届かない場合の保険にすること。[Q10]
  - 成功: 起動完了、手動停止、自動停止（停止の通知に停止時バックアップの結果を含める）。毎時バックアップの成功は投稿しない。
  - 失敗: 起動失敗、バックアップ失敗、MOD 取得失敗、無応答による強制停止、スモークテスト失敗
  - AC8.2.1 Given サーバーが自動停止した。When 停止が完了する。Then Discord に「自動停止」とバックアップ結果が投稿される。
  - AC8.2.2 Given 定期バックアップが失敗した。When CloudWatch アラームが ALARM になる。Then Discord とメールの両方に失敗が通知される。
  - AC8.2.3 Given Discord の Webhook が無効（削除済みなど）になっている。When 失敗イベントが起きる。Then メールには通知が届き、Lambda のエラーが CloudWatch Logs に記録される。
  - AC8.2.4 Given いずれかのイベントが Discord に投稿された。When 投稿本文を確認する。Then Elastic IP、アカウント ID、ARN、インスタンス ID が含まれていない。（承認前の確認での回答）
- **FR8.3** ホワイトリスト（whitelist）を有効にし、許可したプレイヤーだけが参加できること（`online-mode=true` が前提。FR1.4）。[Q8] [Q17]
  - AC8.3.1 Given whitelist にないプレイヤーがいる。When 接続する。Then 「ホワイトリストにない」旨で拒否される。
  - AC8.3.2 Given whitelist にプレイヤーを追加して反映した。When そのプレイヤーが接続する。Then 参加できる。
- **FR8.4** whitelist の中身（プレイヤー名 / UUID）、Discord の Webhook URL、通知先メールアドレスは public リポジトリに置かず、秘匿値ストア（SSM Parameter Store SecureString / Secrets Manager）または GitHub Secrets から注入すること。[Q10] [assumption]
  - AC8.4.1 Given リポジトリの全ファイルを対象にする。When whitelist のプレイヤー名・Webhook URL・メールアドレスを検索する。Then 1 件も見つからない。
  - AC8.4.2 Given 秘匿値ストアの whitelist を更新した。When サーバーを再起動する。Then 新しい whitelist が反映されている。

### FR9 コスト管理
- **FR9.1** AWS Budgets で月 3,000 円相当の予算を設定し、実績または予測が 80% と 100% を超えたら通知すること。通知は FR8.2 と同じ経路（Discord とメール）を使う。[Q6] [Q10] [assumption]（閾値）
  - AC9.1.1 Given 予算の閾値を超えた（テストでは閾値を下げて確認する）。When Budgets が評価する。Then Discord とメールに通知が届く。
- **FR9.2** 予算額・通知先はリポジトリに書かず、変数として GitHub Secrets 等から渡すこと。[memory:M1]
  - AC9.2.1 Given リポジトリの全ファイルを対象にする。When 通知先メールアドレスを検索する。Then 見つからない。

## 3. Non-functional requirements

- **NFR1 コスト**: 月 3,000 円程度を上限とする。
  - 前提: 2〜5 人、月 40 時間稼働、リージョンは東京 `ap-northeast-1`。
  - 対象: EC2、EBS、Elastic IP（停止中も課金）、S3、スナップショット、CloudWatch、Lambda、SNS。
  - 合否基準: nfr-requirements ステージで、この前提による月額見積もりが 3,000 円以下になること。[Q4] [Q6] [Q16]
- **NFR2 性能（目安）**: 同時 5 人が MOD 最大 50 個程度の状態で遊べ、サーバー TPS が平常時 18 以上となることを目安とする。測定の仕組みは作らず、インスタンスタイプは設計で決める。[Q4] [Q16] [Q17]
- **NFR3 起動時間**: start ワークフローを実行してから接続できるようになるまで、10 分以内であること。合否は start ワークフローの所要時間で判定する。[Q16]
- **NFR4 データ保全**: 稼働中の障害で失うプレイ時間は最大 1 時間（RPO）とする。停止時のバックアップから、直近 7 セッション分まで遡れること。[Q7] [Q9]
- **NFR5 セキュリティ**:
  - 受信ポートは 25565/TCP のみとし、SSH（22）は公開しない。管理は SSM Session Manager を想定する。[assumption]
  - RCON は外部に公開しない。
  - EBS とバックアップの保存先を暗号化する。
  - GitHub Actions からの認証は OIDC のみとする。
  - `online-mode=true` と whitelist を有効にする。[memory:M1] [Q17]
- **NFR6 秘匿性（public リポジトリ）**: 次の値は、コード・Actions ログ・PR コメント・Discord 通知本文のいずれにも出さないこと。[memory:M1] [Q10]
  - アカウント ID
  - IAM ロール名・ARN
  - state バケット名
  - Elastic IP
  - whitelist
  - Discord Webhook URL
  - 通知先メールアドレス
- **NFR7 可観測性**: サーバーの稼働状態と、直近のバックアップ結果を Discord の通知履歴と CloudWatch で確認できること。最低限、次の 2 つの指標を持つこと（operation フェーズのガードレール）。[Q10]
  - ヘルス指標: ポート疎通または稼働状態
  - エラー指標: バックアップ失敗回数
- **NFR8 品質ゲート**: 全モジュールに plan モードの `terraform test` を最低 1 つ置き、fmt / validate / tflint / Checkov をすべて通過すること（`team-practices.md` の Testing Posture）。[memory:M1]
- **NFR9 可用性（目安）**: 遊ぶときだけ使う個人用途のため、常時稼働の SLA は設けない。起動ワークフローの成功率は月 95% 以上を目安とし、測定の仕組みは作らない。[Q17]

## 4. Constraints

- Terraform で構築し、GitHub Actions で CI/CD を行う。保護された `master` へは、PR 経由（squash merge）でのみ変更を入れる。[desc]
- デプロイ先は `--profile personal` の AWS アカウントで、環境は prod の 1 つ。[desc] [memory:M1]
- 別リポジトリの過去のコードは流用しない。[desc]
- リポジトリは public。識別子と秘匿値は、GitHub Secrets（CI）、秘匿値ストア、または gitignore 済みのローカルファイルに置く。[memory:M1]
- リポジトリ構成は `bootstrap/` + `envs/prod/` + `modules/<name>/`。`.terraform.lock.hcl` はコミットする。[memory:M1]

## 5. Out of scope

- Bedrock Edition（統合版）からの接続 [Q1]
- 複数環境（dev / staging）[memory:M1]
- 独自ドメインでの接続 [Q8]
- 常時稼働（24/365）[Q5]
- 友人が自分でサーバーを起動できる仕組み（Discord ボットからの起動など）。起動・停止は本人が GitHub Actions で行う。[Q5]
- CurseForge / Modrinth の modpack を丸ごと導入する方式 [Q3]
- クライアント用 MOD 一式の配布の仕組み（友人には手順書 FR3.5 のみを提供する）[Q15]
- 実 apply を伴う統合テスト [memory:M1]
- TPS と起動成功率を測定する仕組み [Q17]

## Sources

- `Initial description:` 本人の依頼文（`project-description.json`）を [desc] で参照する。
- `Workflow-selected scope:` [scope] infra
- [Q1]〜[Q17]: `requirements-analysis-questions.md` の回答（Q10〜Q17 はレビュー指摘への追加質問）
- [memory:M1]: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/practices-discovery/team-practices.md`、および確定した rules（`aidlc/spaces/default/memory/team.md` / `project.md`）

## Assumptions & Open Questions

- [assumption] Minecraft の EULA に同意して運用する（FR1.2）。
- [assumption] MOD の取得時にチェックサムを検証し、失敗したら起動を中止する（FR3.2）。
- [assumption] start / stop / apply / restore の排他は、GitHub Actions の concurrency と、サーバー側の処理中フラグで行う（FR4.3）。
- [assumption] 起動に失敗したらインスタンスを停止する（FR4.4）。
- [assumption] 稼働中の短期バックアップは 24 世代を保持する（FR6.1）。
- [assumption] バックアップ中は `save-off` / `save-all flush` でワールドを静止させる（FR6.3）。
- [assumption] 停止時のバックアップに失敗しても、永続ストレージは残す（FR6.4）。
- [assumption] 秘匿値は SSM Parameter Store SecureString または Secrets Manager に置く（FR8.4）。
- [assumption] Budgets は 80% と 100% で通知する（FR9.1）。
- [assumption] 管理用の接続は SSM Session Manager を使い、SSH は公開しない（NFR5）。
- [assumption] スモークテストは、停止中なら省略する（FR7.3）。
- Open: インスタンスタイプ、オンデマンドか Spot か、バックアップの方式（S3 への圧縮アーカイブか EBS スナップショットか）は、nfr-requirements とインフラ設計で決める。

上の [assumption] は、後から本人が訂正できる既定値として置いている。
