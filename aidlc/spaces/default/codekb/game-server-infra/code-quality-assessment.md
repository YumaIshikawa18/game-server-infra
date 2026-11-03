# Code Quality Assessment

本書はコードを読んだ結果です。テストやチェックは実行していないため、通過状況は未確認です。

## 総合評価

| 観点 | 評価 | 根拠 |
|---|---|---|
| 命名 | good | リソース、変数、関数、イベント名が役割を表しています |
| 関数の大きさ | good | 多くは短い関数です。`stop.sh` の `main` はやや長めです（約 60 行） |
| エラー処理 | good | 境界ごとに明示的に判定します。`set -e` が効かない箇所も説明と判定があります（`backup-lib.sh:29-31`） |
| テストの存在 | fair | 全体は厚いものの、`prepare-env.sh` など重要な箇所に欠落があります |
| 重複 | fair | SSM パラメータの接頭辞、Terraform の版、mask 処理に重複があります |
| 不要コード | good | TODO などはありません。未使用の出力だけが少数あります |
| セキュリティ | good | 識別子の非公開、最小権限、入力検査が一貫しています |
| ドキュメント | good | README と「なぜ」を説明するコメントが充実しています |

## テスト

| 種類 | 場所 | 件数の目安 | 実行 |
|---|---|---|---|
| `terraform test`（plan のみ、ネットワーク遮断） | `bootstrap/`、`envs/prod/`、`modules/*/` の `tests/` | 42 run | `terraform-test` |
| bats | `tests/host/` | 46 | `bats` |
| pytest | `lambda/*/tests/` | 18（パラメータ展開前） | `pytest` |
| unittest | `tests/ci/`、`tests/cd/` | 67 | `identifier-check` |

- 行カバレッジは測定していません。team.md の基準（全モジュールに plan テスト、必須チェック通過）に置き換えられています。`check.py` が plan 以外のテストと、テストのないモジュールを拒否します。
- 実 apply を伴う統合テストはありません。デプロイ後のスモークテストで補います。

### テストの欠落

| 対象 | 状況 | 影響 |
|---|---|---|
| `files/bin/prepare-env.sh` | テストなし。`tests/host/helpers.bash:54` の `STUB_WHITELIST` は未使用です | 起動を止める検査と、秘匿値ファイルの生成が検証されていません。**今回の作業に直結します** |
| `tests/host/helpers.bash` の SSM スタブ | パラメータ名を区別せず同じ値を返します | 2 つ目のパラメータを扱うテストにはスタブの修正が必要です |
| `files/bin/boot-mode.sh` | テストなし | 復元モード判定は `restore.bats` のスタブ越しにしか触れません |
| `files/bin/health-check.sh` | テストなし | 小さなスクリプトです |
| `scripts/local/*` | テストなし | 手元で本人が実行します |
| `user_data.sh.tftpl`、systemd の順序 | テストなし | 実機でしか確認できません |
| ゲーム内の権限や接続 | 自動テストなし | team.md の方針どおりクライアントからの確認です |

## 静的チェック

| チェック | 設定 |
|---|---|
| `fmt`、`validate` | `terraform`、全ルートとモジュール |
| `tflint` | `.tflint.hcl` |
| `checkov` | `bootstrap`、`envs`、`modules`、`.github`。skip には理由あり |
| `shellcheck` | `-S style`、`.shellcheckrc`。対象は `files/bin/*.sh` のみで `user_data.sh.tftpl` は対象外 |
| `gitleaks` | Git 全履歴 |
| `identifier-check` | 追跡ファイル全体のアカウント ID、Webhook、メール、グローバル IPv4 |

Python のリンターとフォーマッターはありません。

## 技術的負債

| # | 内容 | 場所 | 重要度 |
|---|---|---|---|
| 1 | `prepare-env.sh` にテストがありません | `tests/host/` | 高（今回の作業） |
| 2 | Deploy のスモークテストは配布したスクリプトを実行しません。起動処理の不具合は次の Start まで表に出ません | `scripts/cd/deploy.py:117-128`、`modules/minecraft_server/deploy.tf:1-2` | 中（今回の作業） |
| 3 | Compose のコメントと Dependabot の設定が一致しません。イメージの digest は自動更新されません | `docker/compose.yml:1`、`.github/dependabot.yml` | 中 |
| 4 | Dependabot の PR は `plan` を通らない設計で、本人が開き直す必要があります | `.github/workflows/pr.yml:48-53` | 低（意図的） |
| 5 | `identifier-check` が単体テストも実行します。名前と内容が一致せず、失敗の原因が読み取りにくくなります | `scripts/ci/check.py:68-70` | 低 |
| 6 | Terraform イメージの版を直書きしており、`.tool-versions` と二重管理です | `scripts/local/terraform.py:27` | 低 |
| 7 | SSM の接頭辞を 2 か所で組み立てています | `modules/minecraft_server/main.tf:22`、`envs/prod/main.tf:36` | 低 |
| 8 | 未使用の出力があります（`role_name`、`bucket_arn`、`vpc_id`） | 各 `outputs.tf` | 低 |
| 9 | `.gitignore` に他言語のテンプレートの名残があります | `.gitignore:1-33` | 低 |
| 10 | mask の処理が 2 つあります | `scripts/ci/plan.py:106-114`、`scripts/cd/common.py:34-47` | 低 |

## セキュリティの観察

- whitelist の検査は `.env` への注入を防ぎ、ログには人数だけを出します（`prepare-env.sh:13-16,40`）。
- `secrets.env` は `umask 077`、`chmod 600` と `mv` で作ります。
- SG は全世界に 25565 を開いており、online-mode と whitelist が実質の防御です。op 権限はこの内側の権限を広げる変更です。
- `common.py`、`plan.py`、`deploy.py` は例外本文を公開ログに出しません。
- プレイヤー名はサーバーログに含まれるため、保存を 14 日に短くしています（`modules/minecraft_server/main.tf:31`）。バックアップの `/data` にも `whitelist.json` が含まれます。

## 今回の作業で確認が必要な点

以下はコードから判断できないため、要確認です。

| 項目 | 内容 | 情報源 |
|---|---|---|
| 権限の取り消し | `EXISTING_OPS_FILE` の既定は `SYNC_FILE_MERGE_LIST` で、`OPS` は追加マージです。一覧から外して取り消すには `SYNCHRONIZE` が必要と読めます | itzg 公式ドキュメント。実機未確認 |
| 権限レベル | `SYNCHRONIZE` は既存項目の `level` と `bypassesPlayerLimit` を保持します。新規項目の値は `op-permission-level`（未設定）に従うと思われ、既定は 4 と思われます | 前半は公式ドキュメント、後半は推測 |
| op が 0 人 | 現在の検査は 1 名以上を要求します。SSM の値は空にできないと思われます。`OPS` 未設定時の `SYNCHRONIZE` の挙動は記載がありません | 推測 |
| whitelist との関係 | vanilla では op が whitelist を迂回できる可能性があります。26.3 での挙動は未確認です | 推測 |
| 既存の `ops.json` | ワールド EBS 上の内容は未確認です。手動で付けた権限があれば `SYNCHRONIZE` で消えます | 未確認 |
| 名前を解決できないとき | 起動が止まるかどうかは記載がありません | 公式ドキュメントに記載なし |
| 環境変数の変更の反映 | `secrets.env` の変更で `docker compose up` がコンテナを作り直す前提です。whitelist の変更も同じ前提で動いていると思われます | 推測 |
| 復元との関係 | 古いバックアップを復元すると古い `ops.json` が戻りますが、次の起動で `SYNCHRONIZE` が上書きすると思われます | 推測 |

## 単一サーバーの前提

一覧は `architecture.md` の「単一サーバーの前提」を参照してください。
