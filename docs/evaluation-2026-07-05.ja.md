# Kaizen Agents Organization 評価レポート — 2026-07-05(main 最新化後)

対象: kaizen-agents-org 全リポジトリ(`.github` / `kaizen-loop` / `builder-agent` / `verifier` / `coderabbit` / `renovate-config`)
根拠: 全リポジトリを `origin/main` へ fast-forward 同期した直後の GitHub 実測(open PR/issue、CI)、`verifier` の `pnpm eval` 実行結果、`kaizen-loop` のソース確認、ローカル `~/.kaizen` の smoke artifact 確認。
前回評価: [evaluation-2026-07-04.ja.md](./evaluation-2026-07-04.ja.md)、[improvement-playbook.ja.md](./improvement-playbook.ja.md)

---

## 1. 総合評価

**評点: A-(設計 A / 運用の証明 B）** — 前回(B+、運用の証明 C)から明確に改善。

前回指摘した「生成速度がレビュー速度を上回る」問題(PR バックログ 12 件)がほぼ解消し、eval コーパスも 7 ケースから 20 ケース(他言語ログ込み)へ拡充された。プレイブックの Phase A のうち複数項目が実質的に完了している。残る最大のギャップは **実運用 sandbox smoke の実績がまだゼロ** であることと、**WIP 制限がまだ仕組み化されていない**こと。

## 2. 現状スナップショット(2026-07-05 実測、main 同期直後)

| 項目 | 前回(07-04) | 今回(07-05) | 判定 |
| --- | --- | --- | --- |
| open PR(生成物) | 12 件 | **1 件**(builder-agent #72、CLEAN) | 大幅改善 |
| BLOCKED PR | 3 件 | **0 件** | 解消 |
| BEHIND PR | 2 件 | **0 件** | 解消 |
| open issue(kaizen ラベル) | 17 件 | **9 件** | 改善 |
| CI(main) | 全リポジトリ成功 | **全リポジトリ成功**(直近 run 確認) | 維持 |
| verifier eval コーパス | 7 ケース(golden +1) | **20 ケース**(seeded 10 + golden 10) | 大幅改善 |
| verifier eval 実行結果 | — | **20/20 pass、agreement 1.0、偽陽性率 0** | 良好(ただし後述の留保あり) |
| verifier CI ゲート | なし | **`pnpm eval` が CI 必須ステップ化** | 導入済み |
| 他言語ログ対応 | なし | **golden ケースに pytest/cargo/go test/eslint 実ログ 4 件を追加** | Phase B-1 着手済み |
| verifier `evidence_grade` | なし | **`executed` / `reported` を区別するフィールドを導入** | 新機能(下記で評価) |
| sandbox smoke 実運用実績 | 0 件 | **0 件**(見つかった 4 件はすべてテスト実行の一時 artifact) | 未解消 |
| WIP 制限の実装 | なし | **`src/config/schema.ts` に該当フィールドなし** | 未着手 |
| メトリクス永続化(`docs/metrics/`) | なし | **`.github/docs/metrics/` ディレクトリ自体が未作成** | 未着手 |
| ローカル fleet hygiene | 全 checkout dirty・behind | **本評価作業で 6 リポジトリを stash → main に同期済み** | 今回の作業で解消 |

## 3. 前回プレイブックからの進捗(Phase A 項目別)

- **A-1(PR バックログをゼロにする)**: ほぼ達成。verifier #64/#65/#66、builder-agent #70〜#73、kaizen-loop #153/#154 はすべてマージ済みとみられる(open PR が builder-agent #72 の 1 件のみに減少)。
- **A-2(BLOCKED の根本原因解消)**: 実質的に解消。現在 BLOCKED の PR はゼロ。ただし branch protection 設定自体の恒久的な文書化(`design-decisions.md` への追記)がなされたかは本評価では未確認 — 次回 issue/PR 履歴で要確認。
- **A-3(WIP 制限を仕組みにする)**: **未着手。** `src/config/schema.ts` に `wipLimit` 相当のフィールドが存在しない。バックログは今たまたま少ないが、再発防止の仕組みがまだない。
- **A-4(sandbox smoke を実運用で1回完走)**: **未達成。** issue #131 は open のまま。ローカルに見つかる smoke-runs artifact は全てテストの副産物で、実運用レイアウトでの実行ではない。
- **A-5(メトリクスを GitHub に永続化)**: **部分達成。** `kaizen status --metrics` にレビューウィンドウ集計(`reviewWindow` フィールド)が実装され、ローカルでは分母つき集計が取得可能になった。しかし `.github/docs/metrics/` への週次 PR 永続化はまだ実装されていない。
- **A-6(ローカル fleet の hygiene 回復)**: 本評価作業の一環として今回実施(全 6 リポジトリを stash 保全の上で `main` に fast-forward)。恒久的な自動化(automations プロンプトへの明記)は未確認。

## 4. 新たに評価すべき点 — `evidence_grade` の導入について

verifier に `evidence_grade`(`executed` / `reported`)という新しいフィールドが追加されている。これは 07-03 の verifier 戦略ノートが指摘した問題 — 「ログの中の単語一致だけで、実際にコマンドが実行されたのか、テキストとして報告されただけなのかを区別できない」— に対する直接的な回答であり、**判定はコードで、発見は LLM で** という設計原則を壊さずに信頼性を底上げする良い一歩である。ただし以下は未検証:

- `evidence_grade: "reported"` がついた Finding の重み付け(confidence 式への反映)が、戦略ノートの `CheckKind` 強度(runtime=1.0 / test=0.9 / static=0.7 / reading=0.5)と整合しているか。
- 正規表現マッチそのもの(`HARD_FAILURE_PATTERNS` 等 17 パターン)は変わっていないため、**意味的な誤検知の根本原因はまだ残っている**。`evidence_grade` は「証拠の質」を区別する一歩だが、「診断そのものの精度」を上げる LLM 化(戦略ノート Step 3〜4)はまだ着手されていない。

## 5. 結論

Phase A の「流れの回復」は大きく前進した。次に着手すべきは:

1. **WIP 制限の実装**(A-3)— 今回の急速な消化はレビュー努力の結果であり、仕組みがなければ再びバックログが積み上がる。
2. **sandbox smoke の実運用実行**(A-4)— 2 回連続で readiness の最優先指摘のまま。issue #131 を閉じる。
3. **メトリクスの GitHub 永続化**(A-5)— ローカル集計は取れるようになったので、あとは `.github/docs/metrics/` への週次書き込みを自動化するだけ。
4. **Phase B(verifier LLM 化)への着手判断**— eval コーパスが 20 ケースに拡充され CI ゲート化もされたので、戦略ノート Step 3(Claim 抽出の LLM 化)に進む条件は整いつつある。ただし正規表現ゲートの限界(誤検知)を実データで再確認してから進めるとよい。

具体的な次アクションは引き続き [improvement-playbook.ja.md](./improvement-playbook.ja.md) のチェックリストに従う。A-1/A-2 は完了扱いにしてよい状態、A-3〜A-5 が次の焦点。
