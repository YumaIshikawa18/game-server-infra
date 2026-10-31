# Deployment Strategy

## 方針

EC2 1 台と独立したワールド EBS を使うため、インスタンス置き換えは停止を伴う recreate とする。blue/green や canary は採用しない。ワールドの二重書き込みと追加の常時稼働を避ける。feature flag は作らず、Minecraft / ローダー / MOD の具体的なバージョンを PR で変更する。

| 段階 | 対象 | 条件 | 結果 |
|---|---|---|---|
| PR | master へ入れる候補 | CI の必須 11 チェック | plan サマリーとコードを確認できる |
| マージ後 plan | prod の変更予定 | 現在の master、plan 専用 OIDC | 件数・アドレスを Job Summary で提示 |
| prod 承認 | 同じコミット | 本人が GitHub Environment で承認 | apply ロールを取得できる |
| 再 plan | prod | 共通 S3 ロック、同一 master、値を含むハッシュ一致 | 承認内容と異なればここで停止 |
| 置き換え保護 | 稼働中の管理 EC2 | SSM で保存・バックアップ照合・停止 | 保護に失敗すれば置き換え拒否 |
| apply | prod | 比較した saved plan を同じ job で使用 | Terraform state 更新 |
| スモークテスト | 新しい instance_id | SSM 応答後、server list ping | 停止中は省略を明記。最終確認はクライアント接続 |

実行中の apply を、後続マージで自動キャンセルしない。承認待ちで master が変わった run は、開始時の revision 確認で拒否する。

## 運用の状態

start は復元モードを拒否し、停止処理中なら停止完了を待つ。起動後に SSM と Minecraft を確認する。失敗時は停止し、SSM が使えない場合も EC2 の直接停止を試みる。

stop は通常の保存・バックアップを試みて停止する。SSM 不通などのフォールバックではデータの最終保存を保証できないため、その旨を警告通知する。置き換えではこの直接停止フォールバックを使わず、バックアップ保証がなければ apply を拒否する。

restore は停止中だけ受け付ける。専用タグで Minecraft 起動を止め、復元後も停止しておく。停止確認後にタグを外し、本人が start を実行して確認する。

## ロックと変更の範囲

deploy の承認待ちを stop が待たないよう GitHub の 2 グループは維持する。その上で、実 apply と手動の起動・停止・復元だけを S3 の共有ロックで直列化する。Terraform の state ロックは別で、S3 ネイティブロックを使い続ける。DynamoDB は追加しない。

ホストの自動停止・バックアップと watchdog は、この workflow ロックの外側で動く。ホストの処理同士は既決の flock とタグで保護する。外部からの直接 AWS 操作も避け、復旧時は runbook の排他確認を行う。

## 検証の境界

今回のローカルテストは制御ロジックを AWS mock で検証するもの。AWS 上の IAM、SSM の成功応答、バックアップ復元、server list ping、クライアントからの実接続は、Environment Provisioning と Deployment Execution で確認する。停止中のスモーク省略を接続確認の成功として扱わない。

## Sources

- `cd-config.md`、`rollback-runbook.md`、`deployment-pipeline-questions.md`
- `../../construction/ci-pipeline/ci-config.md`、`quality-gates.md`
- `../../construction/infrastructure-design/infrastructure-specification.md`、`cicd-pipeline.md`
- `../../construction/nfr-design/reliability-design.md`

## Assumptions & Open Questions

None.
