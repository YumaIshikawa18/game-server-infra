<!-- INVARIANT: examples are single-line HTML comments so a fresh template parses to total=0 (MEMORY_EMPTY). Do NOT un-comment or split across lines. t100 guards this. -->
> This file is kept up to date automatically while the stage runs. Add observations at the review step, not by editing here directly.

## Interpretations
<!-- example: 2026-05-29T10:14:32Z — chose REST over GraphQL; the consuming team only needs CRUD, revisit if subscriptions land -->

- 2026-11-03T13:52:13Z — 目標の一覧は Testing Contract と team.md から作り、要件の NFR は別の表にした; ステージの定める情報源に `nfr-requirements` がないため。実機で確認する要件は未確認と明記し、成功として数えていない。

## Deviations
- 2026-11-03T13:52:13Z — テストの検知力の確認と変更前の `bats` を、`.ci-private` の使い捨てのコピーで実行した; 作業ツリーを変えないため。使ったコピーとスクリプトは削除した。

<!-- example: 2026-05-29T10:14:32Z — skipped the optional caching layer the stage prose suggested; the dataset is small enough that it adds risk -->

## Tradeoffs
<!-- example: 2026-05-29T10:14:32Z — picked TDD over BDD this run; the team is unit-first and the domain is well-understood -->

## Open questions
<!-- example: 2026-05-29T10:14:32Z — confirm the retention window with compliance before the next stage hardens the schema -->
