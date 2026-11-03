# Business Overview

## 目的

AWS 上で身内向けの Minecraft Java サーバーを 1 台運用するための Terraform 一式です。インフラの変更と、サーバーの起動・停止・復元を GitHub Actions から行います。本人 1 名が運用し、一緒に遊ぶ人は whitelist に登録されたプレイヤーです。

## 主な機能

| 機能 | 内容 | 根拠 |
|---|---|---|
| サーバーの提供 | EC2 上の Docker で `itzg/minecraft-server` を動かし、Elastic IP で公開します | `modules/minecraft_server/main.tf`、`docker/compose.yml` |
| 接続の制限 | online-mode と whitelist を強制します | `modules/minecraft_server/deploy.tf:13-16` |
| ゲーム設定の管理 | バージョン、ローダー、MOD、難易度などを `minecraft.json` で管理し、PR で変更します | `envs/prod/minecraft.json` |
| コスト抑制 | 無人 30 分で自動停止し、無応答や 12 時間超では外部から強制停止します | `files/bin/health.sh`、`lambda/watchdog/watchdog.py` |
| データ保護 | 毎時と停止時にワールドを S3 へバックアップし、照合します。workflow から復元できます | `files/bin/backup-lib.sh`、`files/bin/restore-apply.sh` |
| 通知 | 運用イベントを Discord とメールへ送ります | `lambda/notifier/notifier.py`、`modules/notifier/main.tf` |
| 変更の統制 | PR の必須チェック、承認付き apply、承認後の plan 照合を行います | `.github/workflows/pr.yml`、`.github/workflows/deploy.yml` |
| クライアント案内 | 参加者向けの手順書を設定から生成します | `scripts/ci/client_guide.py`、`docs/client-setup.md` |

## 業務上の制約

- **公開リポジトリ**です。AWS アカウント ID、IAM ロール名や ARN、バケット名、サーバーのアドレス、plan の全文を、コード、ログ、PR コメントに出しません（`README.md:117-119`）。
- **予算**は月 3,000 円相当です（`envs/prod/variables.tf:54-57`）。
- **環境**は `prod` のみ、リージョンは東京のみです（`envs/prod/variables.tf:24-27`）。

## 今回の作業との関係

現在のプレイヤー管理は whitelist だけで、ゲーム内の op 権限を付与する仕組みはありません（`OPS` と `EXISTING_OPS_FILE` はリポジトリ内に存在しません）。今回の作業は、この権限を whitelist と同じ SSM SecureString の仕組みで付与できるようにするものです。

別の Discord コミュニティ向けに 2 台目を追加する案は後続の作業です。現在の構成は 1 台を前提にしており、その箇所は `architecture.md` の「単一サーバーの前提」に記録しています。
