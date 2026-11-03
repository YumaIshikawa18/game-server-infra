# Requirements

上流: `aidlc/spaces/default/intents/261103-discord-multi-server/ideation/intent-capture/intent-statement.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/ideation/approval-handoff/initiative-brief.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/ideation/approval-handoff/decision-log.md`、`aidlc/spaces/default/codekb/game-server-infra/business-overview.md`、`aidlc/spaces/default/codekb/game-server-infra/architecture.md`、`aidlc/spaces/default/codekb/game-server-infra/code-structure.md`

scope-document は、このプランでは作成していません。範囲は `initiative-brief.md` と `decision-log.md` の決定に従います。

## Intent Analysis

- **目的:** 今の Minecraft サーバーで、ご本人を指定してゲーム内のオペレーター権限（op）を付与し、取り消せるようにします（D-01、D-03、D-04）。
- **背景:** 今のプレイヤー管理はホワイトリストだけで、op を付与する仕組みはありません（`business-overview.md`）。
- **`intent-statement.md` との差:** 意図の記述には 2 台目の増設とその完了条件が含まれますが、Approval & Handoff で増設は別の作業に分けました（D-01、D-02）。この文書の要件は op 権限だけを対象にします。
- **種類と規模:** 既存の仕組みの拡張です。変更は `minecraft_server` モジュールのホストスクリプトと配布設定、テスト、README に収まる見込みです（`code-structure.md`）。

## Functional Requirements

### FR1. オペレーターの指定

| ID | 要件 | 出典 |
|---|---|---|
| FR1.1 | サーバーは起動のたびに、ホワイトリストと同じ接頭辞の下にある SecureString の秘匿パラメータからオペレーターの一覧を読むこと。パラメータ名は Infrastructure Design で確定する | D-05、Feasibility の Q5 |
| FR1.2 | 一覧は Minecraft のユーザー名をカンマで区切った形式とし、前後の空白を無視すること。今回の登録はご本人の 1 名だが、形式はホワイトリストに揃える | D-04、`prepare-env.sh` |
| FR1.3 | 一覧にあるプレイヤーに、権限レベル 3 を付与すること | 本ステージの Q1 |

**受け入れ基準**

- Given 一覧にご本人の名前を登録している、When Start workflow でサーバーを起動する、Then ご本人はゲーム内で `/gamemode` と `/kick` を実行できる。
- Given 同じ状態で、When ご本人が `/stop` を実行する、Then コマンドは権限不足で拒否され、サーバーは動き続ける。
- Given 一覧の名前の前後に空白がある、When サーバーを起動する、Then 空白を除いた名前で処理される。

### FR2. 権限の取り消し

| ID | 要件 | 出典 |
|---|---|---|
| FR2.1 | 次の起動で `ops.json` を一覧に同期し、一覧にない名前の権限をなくすこと。ゲーム内の `/op` で付けた権限も、同じ起動で対象になる | Initiative Brief の完了条件、C-T8、R6 |
| FR2.2 | パラメータが未登録のときは、次の起動で `ops.json` のオペレーターを 0 人にすること | 本ステージの Q3、Initiative Brief の完了条件 |

**受け入れ基準**

- Given ご本人に権限がある、When パラメータを削除して次の起動を行う、Then `ops.json` にオペレーターはおらず、ご本人の `/gamemode` は拒否される。
- Given 権限を取り消した状態で、When パラメータを再登録して次の起動を行う、Then ご本人は再び `/gamemode` を実行できる。
- Given 動作中のサーバーがある、When 一覧を変更する、Then 次の起動までは権限が変わらない。

### FR3. 入力の検査と失敗時の動作

| ID | 要件 | 出典 |
|---|---|---|
| FR3.1 | パラメータが未登録のときは、オペレーター 0 人として起動し、ログにだけ記録すること。Discord とメールには通知しない | 本ステージの Q3 |
| FR3.2 | 未登録以外の理由でパラメータを読めないときは、起動を中止して `start_failed` を通知すること | 本ステージの Q3、`architecture.md` の「失敗時は閉じます」 |
| FR3.3 | 一覧の形式が不正なときは、起動を中止して `start_failed` を通知すること。形式はホワイトリストと同じ（英数字と `_` の 3〜16 文字）とする | `prepare-env.sh`、Initiative Brief のリスク |
| FR3.4 | 一覧の名前がホワイトリストにないときは、起動を中止して `start_failed` を通知すること。通知の文面で、オペレーターの一覧とホワイトリストの不一致が原因と分かるようにする。比較では大文字と小文字を区別しない | 本ステージの Q2、Q7 |
| FR3.5 | 通知とログの文面に、プレイヤー名と一覧の値を含めないこと | D-05、C-R2 |

同じ名前が一覧に重複していても、エラーにはしません。

**受け入れ基準**

- Given パラメータが未登録である、When サーバーを起動する、Then 起動は成功し、ログにオペレーター 0 人と記録され、`start_failed` は通知されない。
- Given パラメータの読み取りが権限エラーまたは通信エラーで失敗する、When サーバーを起動する、Then 起動は中止され、`start_failed` が通知され、`secrets.env` は更新されない。
- Given 一覧に許可されていない文字がある（例: `name;x`）、When サーバーを起動する、Then 起動は中止され、`start_failed` が通知され、通知の文面にその値は含まれない。
- Given 一覧の名前がホワイトリストにない、When サーバーを起動する、Then 起動は中止され、`start_failed` が通知され、通知の文面から一覧とホワイトリストの不一致が原因と分かり、その名前は含まれない。
- Given 一覧の名前がホワイトリストの名前と大文字小文字だけ異なる、When サーバーを起動する、Then 起動は成功する。

### FR4. 反映の時期

| ID | 要件 | 出典 |
|---|---|---|
| FR4.1 | 一覧の変更はご本人が手元で行い、PR とデプロイなしで次の起動から反映すること。仕組みの追加そのものは PR とデプロイで反映する | D-05 |
| FR4.2 | ワールドの復元後は、次の通常の起動で一覧に同期すること。古いバックアップに含まれる `ops.json` の権限を残さない | `code-quality-assessment.md` の「復元との関係」 |

**受け入れ基準**

- Given 仕組みをデプロイ済みである、When ご本人が手元でパラメータを変更して次の起動を行う、Then PR とデプロイなしで変更が反映される。
- Given `ops.json` の内容が一覧と異なるバックアップを復元した、When 次の通常の起動を行う、Then `ops.json` は一覧と一致する。

### FR5. 手順書

| ID | 要件 | 出典 |
|---|---|---|
| FR5.1 | README に、一覧の登録、変更、取り消し（パラメータの削除）、反映の確認の手順を載せること。反映の確認には、起動ログのオペレーター人数とゲーム内の確認を含める。オペレーターの名前をホワイトリストから外すときは、先にオペレーターの一覧から外す順序を書く。手順に実際の名前や識別子を書かない | D-05、C-R1、C-R2、本ステージの Q7、Q9 |
| FR5.2 | ロールバック手順を載せること。仕組みを外す前にパラメータを削除して次の起動を行い、権限を 0 人にしてから revert する順序とする | team.md の Deployment、operation.md |

**受け入れ基準**

- Given README の手順に従う、When ご本人が登録から取り消しまでを実行する、Then 手順にない AWS 操作を必要とせずに完了できる。
- Given リポジトリの追跡ファイル全体を検査する、When `identifier-check` と `gitleaks` を実行する、Then どちらも成功する。

### FR6. テスト

| ID | 要件 | 出典 |
|---|---|---|
| FR6.1 | `prepare-env.sh` のテストを追加し、正常、未登録、読み取り失敗、形式不正、ホワイトリスト外の各場合を検証すること。既存のホワイトリストの検査（読み取り失敗、形式不正）も対象とする | D-06、`code-quality-assessment.md` の負債 1 |
| FR6.2 | `tests/host/helpers.bash` の SSM スタブを、パラメータ名ごとに異なる値を返せるようにすること | `code-quality-assessment.md` のテストの欠落 |
| FR6.3 | plan モードの `terraform test` で、配布する設定に同期の設定と権限レベル 3 が含まれ、一覧の値が含まれないことを検証すること | D-06、team.md の Testing Posture |

**受け入れ基準**

- Given 追加したテストがある、When `bats` を実行する、Then 上記の各場合がすべて成功し、スクリプトの判定を壊すと少なくとも 1 件が失敗する。
- Given 配布する設定から同期の設定を外す、When `terraform test` を実行する、Then テストが失敗する。

## Non-Functional Requirements

| ID | 分類 | 要件 | 確認方法 | 出典 |
|---|---|---|---|---|
| NFR1 | セキュリティ | オペレーターの名前が、リポジトリ、Terraform の state と plan、Actions のログ、PR コメント、通知に 0 件であること | NFR 向けのテスト（`terraform test`、`bats`）、`identifier-check`、`gitleaks` | D-05、C-R1、C-R2 |
| NFR2 | セキュリティ | 一覧をコンテナへ渡すファイルは、今の `secrets.env` と同じくパーミッション 0600 で、一時ファイルと `mv` で書くこと | `bats` | `prepare-env.sh`、`code-quality-assessment.md` |
| NFR3 | セキュリティ | 権限を持つのは、起動時点で一覧にある名前だけであること。起動後に `/op` で付けた権限は次の起動までに限る | ご本人の権限はゲーム内、対象外の人は `ops.json` の中身で確認（本ステージの Q5）。`ops.json` の確認は、起動直後、`/op` を使う前に行う | Initiative Brief の完了条件、Q5、Q8 |
| NFR4 | 互換性 | パラメータが未登録の状態でデプロイしても、起動、接続、ホワイトリスト、ワールドの動作が変わらないこと | デプロイ後の Start とクライアントからの接続 | Initiative Brief の完了条件 |
| NFR5 | 可観測性 | 起動ごとに、オペレーターの人数（0 以上の整数）をスクリプトのログに記録すること | `bats` | `prepare-env.sh` の `players=` の形式 |
| NFR6 | 費用 | 課金されるリソースを新たに作らないこと。plan に追加されるリソースが配布ファイル以外にないこと | PR の plan の件数とアドレス | C-O2、Initiative Brief の範囲 |
| NFR7 | 品質 | すべての必須チェックが成功し、全モジュールに plan モードのテストがあること | PR の必須チェック | team.md の Testing Posture |
| NFR8 | デプロイ | 誰も遊んでいない時間に適用し、デプロイ後に実際の Start で起動処理を確認すること。Deploy のスモークテストは配布したスクリプトを実行しないため、これだけでは完了としない | Deployment Execution の記録 | D-07、`code-quality-assessment.md` の負債 2、team.md の Deployment |

## 完了条件

Initiative Brief の完了条件を、本ステージの Q5 の回答に合わせて次のとおりとします。

- 指定した人（ご本人）が権限を持つことを、ゲーム内で確認できること。
- 対象外の人が権限を持たないことを、起動直後、`/op` を使う前の `ops.json` の中身で確認できること。
- 権限を取り消すと、次の起動以降は権限がなくなること。
- 今のサーバーに Minecraft クライアントから接続でき、ワールドが保たれていること。

## Constraints

- インフラは Terraform で定義し、変更は PR を通じて `master` に取り込みます（project.md の Mandated）。
- リポジトリは public です。名前と識別子をコード、ログ、PR コメントに出しません（project.md の Forbidden、C-R1、C-R2）。
- 変更は、誰も遊んでいない時間に適用します（D-07、C-O6）。
- 運用はご本人だけで行います（C-O1）。
- 予算は月 3,000 円のままです（C-O2、Initiative Brief の範囲）。

## Assumptions

| ID | 前提 | 理由 | 確認する時期 |
|---|---|---|---|
| A-1 | ご本人の名前はホワイトリストに登録済みです | FR3.4 の検査を通すために必要です。未登録なら起動が中止され、通知で分かります | 登録時 |
| A-2 | 手動で付けた権限はありません | 本ステージの Q4 の回答です。同期で失われるものはありません | 確定 |
| A-3 | `SYNCHRONIZE` は `OPS` の一覧に `ops.json` を同期します | [公式ドキュメント](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/)の記載です。実機では未確認です | Deployment Execution |
| A-4 | 秘匿パラメータの値は空にできません | 推測です。FR2.2 の削除による 0 人の表現は、これに関わらず成り立ちます | Code Generation |
| A-5 | 既存の IAM の読み取り権限（接頭辞以下）で新しいパラメータを読めます | `iam.tf` の記載からの判断です | Infrastructure Design |
| A-6 | 名前の解決に失敗したときの動作は、ホワイトリストと同じ外部サービスに依存します | 公式ドキュメントに動作の記載はありません。新しい依存先は増えないため、要件は追加しません | Deployment Execution |

## Out of Scope

- 2 台目のサーバーの作成と、「サーバーは 1 台だけ」という前提の解消（D-01、D-02）
- 予算の変更、今のワールドの引き継ぎ、Discord から操作する機能（Initiative Brief の範囲）
- 変更の即時反映（D-05）
- 人ごとに異なる権限レベルと `bypassesPlayerLimit` の設定（対象はご本人だけです）
- 起動中のゲーム内 `/op` の禁止（次の起動で消えるため、NFR3 の範囲で許容します）
- Deploy のスモークテストの改善（NFR8 の実 Start で補います）と、`code-quality-assessment.md` のその他の負債
- 実 apply を伴う統合テスト（team.md の Testing Posture）

## Open Questions

| ID | 内容 | 影響 | 確認する時期 |
|---|---|---|---|
| OQ1 | `SYNCHRONIZE` で `OPS` が未設定のときの動作は、公式ドキュメントに記載がありません。`ops.json` が残る場合は、Infrastructure Design で FR2.2 を満たす代替手段を決めます（本ステージの Q6） | FR2.2 の実現方法 | Infrastructure Design（イメージの動作の確認）、Deployment Execution（実機） |
| OQ2 | 新規の項目に `OP_PERMISSION_LEVEL` が適用されるかは、公式ドキュメントに明記がありません（推測）。既存の項目のレベルは保持されます。適用されない場合は、Infrastructure Design で FR1.3 を満たす代替手段を決めます（本ステージの Q6） | FR1.3 の実現方法 | Infrastructure Design（イメージの動作の確認）、Deployment Execution（実機） |
| OQ3 | オペレーターがホワイトリストを迂回できるかは、26.3 では未確認です（推測）。FR3.4 により、結論に関わらず一覧はホワイトリストの範囲に収まります | なし（記録のみ） | 確認は必須としません |
| OQ4 | 環境変数の変更で `docker compose up` がコンテナを作り直す前提は未確認です（推測）。FR2 と FR4 の受け入れ基準で確認します | FR2、FR4 の実現方法 | Deployment Execution |
