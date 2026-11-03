# CI/CD Pipeline

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/inception/requirements-analysis/requirements.md`、`infrastructure-specification.md`

パイプラインの変更はありません。既存の PR と Deploy の workflow で反映します。`bootstrap/` の変更もありません。

## ステージとゲート

| ステージ | 実行するもの | この変更で確認すること | ゲート |
|---|---|---|---|
| PR | 既存の必須チェック（`fmt`、`validate`、`tflint`、`checkov`、`terraform-test`、`bats`、`pytest`、`shellcheck`、`gitleaks`、`identifier-check`、`plan` など） | 追加した `bats` と `terraform test` が通ること。`plan` の追加が配布ファイル以外にないこと（NFR6） | すべて成功（NFR7） |
| Deploy | 承認後の plan の照合と apply | インスタンスの置き換えがないこと | `prod` の手動承認 |
| Deploy のスモークテスト | ホストが動作中ならヘルス確認 | 配布したスクリプトは実行されないため、完了の根拠にしない（NFR8） | 既存どおり |
| 実 Start | Start workflow | 下の確認手順 | ご本人の確認 |

## デプロイの手順

誰も遊んでいない時間に行います（D-07）。

1. PR をマージし、`prod` を承認して apply します。動作中のサーバーには次の起動まで反映されません。
2. この時点ではパラメータを登録せず、Stop と Start を行います。起動ログが `ops=0` で、接続できることを確認します（NFR4）。
3. 手元で `<param_prefix>/ops` に SecureString を登録し、Stop と Start を行います。
4. 起動ログが `ops=1` であることを確認します（FR5.1）。
5. 起動直後、`/op` を使う前に `ops.json` の中身を確認します。ご本人だけがレベル 3 で載っていることを確かめます（NFR3、FR1.3）。
6. ゲーム内で `/gamemode` と `/kick` が使えること、`/stop` が拒否されることを確認します（FR1）。
7. パラメータを削除して Stop と Start を行い、`ops=0`、`ops.json` が `[]`、`/gamemode` の拒否を確認します（FR2）。
8. パラメータを再登録して Stop と Start を行い、権限が戻ることを確認します。
9. クライアントから接続し、ワールドが保たれていることを確認します（NFR4）。

手順 2、3、7、8 で Stop と Start が 4 回必要です。Stop のたびにバックアップが走ります。

`secrets.env` の変更でコンテナが作り直されること（OQ4）は、手順 4〜8 で権限が変わることで確認します。

## ロールバック

| 状況 | 手順 |
|---|---|
| 権限だけを外す | パラメータを削除し、次の起動を行います。`ops.json` は `[]` になります |
| 起動が失敗する（一覧の問題） | 通知の文面に従って一覧を直すか、パラメータを削除して、もう一度 Start します |
| 起動が失敗する（配布したスクリプトの問題） | revert の PR をマージし、承認付きの apply を行います。この場合は `ops.json` が残るため、Start の後で内容を確認します。権限を外すには、コンテナを止めた状態で Session Manager から `ops.json` を `[]` に書き換えてから、もう一度 Start します |
| 仕組みを外す（正常時） | 先にパラメータを削除して起動し、`ops.json` が `[]` になったことを確認してから、revert の PR をマージします（FR5.2） |

revert の後は `OPS` が未設定になり、イメージは `ops.json` を変更しません。順序を守らないと権限が残ります。ワールドのデータは変更しないため、バックアップからの復元は通常は不要です。

## イメージの更新

イメージの digest を更新するときは、`ops.json` のレベルが 3 のままであることを次の起動で確認します。種の形式はイメージの内部の動作に依存し、CI では検知しないためです（`infrastructure-specification.md`）。README の手順にも載せます。

## Secrets の管理

| 値 | 置き場所 | CI での扱い |
|---|---|---|
| オペレーターの一覧 | SSM SecureString（手元で登録） | CI は読みません。Terraform の state と plan にも入りません（NFR1） |
| パラメータ名 | `terraform output`（`sensitive`） | 公開ログに出しません |

GitHub Secrets の追加はありません。
