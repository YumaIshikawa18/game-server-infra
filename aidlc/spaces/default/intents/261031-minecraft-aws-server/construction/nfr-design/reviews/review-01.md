## Review

**Verdict:** NOT-READY
**Reviewer:** aidlc-architecture-reviewer-agent
**Date:** 2026-10-31T17:26:50Z
**Iteration:** 1
**Verdict Dictated:** no

### Findings

| ID | Severity | Location | Finding | Required action | Status |
|---|---|---|---|---|---|
| R-01 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/security-design.md > §2 IAM ロールの設計（`${prefix}-app-server`、`${prefix}-ci-ops`） | reliability-design.md §2 手順 7、§3、§7 と observability-design.md §2 は、ホスト上のスクリプト（stop.sh / backup）と start.yml が SNS に直接 Publish するとしています。しかし `${prefix}-app-server` の権限一覧にも `${prefix}-ci-ops` の権限一覧にも `sns:Publish` がありません（`sns:Publish` があるのは watchdog だけです）。このままではバックアップ失敗・起動失敗・停止完了の通知が AccessDenied になり、NFR4.8 と NFR4.10 を満たせません。 | `app-server` に通知用 SNS トピックだけへの `sns:Publish` を追加します。start.yml / stop.yml が SNS に送る経路は、`ci-ops` に同じ権限を足すか、スクリプト側から送る設計に一本化し、security-design.md §2 と observability-design.md §2 を一致させます。 | New |
| R-02 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/reliability-design.md > §8 復元（restore.yml）と security-design.md > §2 `${prefix}-ci-ops` / `${prefix}-app-server` | 復元は EC2 タグ `mc:mode=restore` の付け外しで起動ターゲットを切り替える設計です。しかし誰がこのタグを付けて外すのかが書かれていません。`ci-ops` に許可されているのは Start / Stop / Describe と指定 SSM ドキュメントだけです。`app-server` の CreateTags / DeleteTags は `mc:stopping` キーに限られています。どちらのロールでも `mc:mode` を操作できず、復元手順（NFR4.5、20 分以内の RTO）が実装できません。 | `mc:mode` を操作する主体を決めます。例として、`ci-ops` に `aws:TagKeys = mc:mode` に限った CreateTags / DeleteTags を足します。あるいは、タグを使わず SSM で渡す引数やローカルのフラグファイルに切り替えます。決めた方式を security-design.md §2 と reliability-design.md §8 の両方に書きます。 | New |
| R-03 | Major | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/security-design.md > §5 CI のセキュリティチェック（必須 10 種）と Assumptions | 必須 10 種に bats（Bash スクリプトのテスト）が含まれていません。bats は assumption として書かれているだけです。backup / stop / health / idle-stop / mod-sync / restore-apply の Bash スクリプトは、ワールドデータの保全（NFR4.1〜NFR4.4、NFR4.12）を担う中核です。それなのに ShellCheck（静的検査）だけでは、flock の排他・`trap` による `save-on`・世代削除の境界値・sha256 照合を CI で検証できません。team.md の Testing Posture「CI で実行し、マージ前に成功していること」を満たしません。 | bats を必須チェックに加えるか、スクリプト検証の別手段（例: pytest からの呼び出し）を CI の必須チェックとして明記します。そのうえで、チェック一覧（10 種または 11 種）と、assumption の承認前確認の扱いを確定させます。 | New |
| R-04 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/security-design.md > §2 `${prefix}-app-server` と observability-design.md > §1 メトリクスの収集 | `app-server` の `cloudwatch:PutMetricData` は名前空間 `Minecraft` に限定されています。一方、`disk_used_percent` は CWAgent の既定名前空間 `CWAgent` で送られます。設定で名前空間を変えない限り拒否されます。また `BackupBucketBytes` の `ListObjectVersions` には `s3:ListBucketVersions` が必要です。権限一覧の S3 は `hourly/` と `stop/` への List となっているだけで、この権限も旧バージョン全体の集計も想定されていません。 | CloudWatch Agent の `metrics_namespace` を `Minecraft` に揃えると設計に明記します。S3 側は `ListBucketVersions` の許可範囲を明記します。 | New |
| R-05 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/reliability-design.md > §7 起動失敗 | 起動失敗時の停止は、start.yml が SSM 経由で stop.sh を呼ぶ設計です。SSM エージェントが立ち上がる前にブートが失敗した場合は stop.sh を呼べません。NFR4.8 の「インスタンスを停止する」を満たせず、stop が必要な状況でインスタンスが残り、watchdog の 60 分条件まで課金が続きます。 | SSM に到達できない場合は、`ci-ops` の `ec2:StopInstances` で直接停止するフォールバックを設計に加えます。 | New |
| R-06 | Minor | aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/traceability.json > coverage | NFR Requirements が定義している NFR7.1〜NFR7.16（NFR7.6 を除く）と NFR8.1、NFR8.3 が coverage に載っていません。sensor は pass ですが、observability-design.md に対応する設計があるのに、どの節がどの要件に当たるかが追跡できません。 | NFR7.x と NFR8.x を coverage に追加し、observability-design.md の節へ対応づけます。 | New |

### Validation Tool Results

| Tool | Result | Interpretation |
|---|---|---|
| aidlc engine sensor-traceability --stage nfr-design | PASS（gaps 0、orphans 0、missing 0） | 形式上の網羅は取れています。ただし上記 Minor のとおり、NFR7.x / NFR8.x の対応が追跡表に出ていません。 |

### Summary

設計全体は一貫していて、要件との対応も取れています。ただし IAM 権限の設計が、設計内で使われている動作に追いついていません。SNS への Publish と `mc:mode` タグの操作は、どのロールにも許可されていません。Bash スクリプトのテストも CI の必須チェックに入っていません。この Major 3 件を直せば、開発者が推測なしで実装できる状態になります。
