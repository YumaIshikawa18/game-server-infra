# Cross-Unit Traceability

**判定: pass**（25 件すべてに実装またはテストが対応。未対応は 0 件）

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-generation-plan.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/unit-test-instructions.md`、`aidlc/spaces/default/intents/261103-discord-multi-server/construction/code-generation/code-summary.md`

この作業に Unit はありません。担当はすべて Code Generation のステージです。この判定は対応するファイルがあることを示すもので、実機で動作を確認したことは示しません。未確認の項目は `test-results.md` にあります。

| ID | 担当 | 対象ファイル | 状態 |
|---|---|---|---|
| FR1.1 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR1.2 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR1.3 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR2.1 | code-generation | `modules/minecraft_server/deploy.tf` | 対応あり |
| FR2.2 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR3.1 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR3.2 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR3.3 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR3.4 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR3.5 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| FR4.1 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| FR4.2 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| FR5.1 | code-generation | `README.md` | 対応あり |
| FR5.2 | code-generation | `README.md` | 対応あり |
| FR6.1 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| FR6.2 | code-generation | `tests/host/helpers.bash` | 対応あり |
| FR6.3 | code-generation | `modules/minecraft_server/tests/minecraft_server.tftest.hcl` | 対応あり |
| NFR1 | code-generation | `modules/minecraft_server/tests/minecraft_server.tftest.hcl` | 対応あり |
| NFR2 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| NFR3 | code-generation | `modules/minecraft_server/files/bin/prepare-env.sh` | 対応あり |
| NFR4 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| NFR5 | code-generation | `tests/host/prepare_env.bats` | 対応あり |
| NFR6 | code-generation | `modules/minecraft_server/deploy.tf` | 対応あり |
| NFR7 | code-generation | `scripts/ci/check.py` | 対応あり |
| NFR8 | code-generation | `README.md` | 対応あり |

## 未対応の項目

なし。
