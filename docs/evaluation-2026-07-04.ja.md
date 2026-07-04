# Kaizen Agents Organization 評価レポート — 2026-07-04

対象: kaizen-agents-org 全リポジトリ(`.github` / `kaizen-loop` / `builder-agent` / `verifier` / `coderabbit` / `renovate-config`)
根拠: GitHub 上の open PR / issue / CI 実測、`origin/main` のソース・eval コーパス、`production-readiness/logs/2026-06-29.md`、ローカル `~/.kaizen` の run 記録、ローカル checkout の状態。
前回評価: [improvement-report-2026-07-03.ja.md](./improvement-report-2026-07-03.ja.md)(戦略レポート。本レポートはその翌日時点の実測評価と差分)

---

## 1. 総合評価

**評点: B+(設計 A / 運用の証明 C)**

アーキテクチャ・安全設計・自己批判の文化は引き続き高水準で、直近 30 日で組織全体 217 件の PR がマージされるなど生産スループットは非常に高い。CI は全リポジトリで green。

しかし 2026-07-04 時点で最も目立つのは、**「生成する速度」が「人間が吸収(レビュー・マージ)する速度」を上回っている**ことである。生成 PR バックログは 06-29 の 5 件から **12 件へ倍増以上**し、滞留中に BEHIND / BLOCKED 化して手戻りが発生し始めている。改善(Kaizen)を名乗るシステムとして、いま必要なのは生成量の増加ではなく **WIP 制限とフロー効率の回復**、そして 07-03 レポートが指摘した「信頼の証明」(メトリクス・E2E 実績・verifier の実体化)である。

## 2. 現状スナップショット(2026-07-04 実測)

| 項目 | 値 | 備考 |
| --- | --- | --- |
| open PR(生成物) | **12 件**(kaizen-loop 3 / builder-agent 5 / verifier 4) | 06-29 は 5 件。5 日で倍増 |
| うち BLOCKED | 3 件(builder-agent #72 #74、verifier #71) | branch protection との相性問題が未解決 |
| うち BEHIND | 2 件(verifier #65 #66) | 滞留による陳腐化=手戻りの発生 |
| open issue(kaizen ラベル) | 17 件(.github 4 / kaizen-loop 4 / builder-agent 4 / verifier 5) | scout が 1 日 3 回生成し続けている |
| 直近 30 日マージ PR | 217 件(全 6 リポジトリ合計) | スループットは十分高い |
| CI(main) | 全リポジトリ成功 | 実行時間も 15〜35 秒と健全 |
| sandbox smoke 実績 | **0 件**(実運用 artifact なし) | issue #131 が open のまま。2 回連続の readiness 最優先指摘 |
| verifier 実装 | 依然 `minimal-verdict.ts`(正規表現照合) | eval コーパスは 6→**7 ケース**(golden +1)と微増 |
| メトリクス | `kaizen status` に review-window メトリクス追加(#151、07-04 マージ) | **GitHub への永続化は未着手**。分母つき週次集計はまだ存在しない |
| ローカル checkout | 全リポジトリが `codex/*` ブランチ上・dirty・origin より最大 16 コミット behind | `_pr-work/` に作業ディレクトリ 12 件が残置 |

## 3. 07-03 レポートからの進捗差分

前日の戦略レポート(P1〜P5)に対する 1 日での動き:

**前進したもの:**

- **P2(計測)**: kaizen-loop #151「review-window status metrics」がマージ(07-04)。`kaizen status --metrics` でレビュー期間内の集計が取れる基盤ができた。ただし「GitHub への永続化」「分母つき週次集計」は未着手。
- **P3(PR の証拠力)**: kaizen-loop #152「Surface verifier status in PR bodies」がマージ(07-04)。PR 本文への verifier 状態の転記が始まった。
- **P1-4(TMPDIR 問題)**: verifier #64「Avoid verifier tsx IPC path failures」が open・CLEAN。マージすれば検証失敗 4/13 の主因(#48)が解消する見込み。
- **P1-1(eval コーパス)**: golden ケースが 1 件追加(6→7)。さらに #65(missing-intent ケース)#66(閾値ゲート)が open 中。

**動いていないもの:**

- **sandbox smoke の実運用実績はゼロのまま**(見つかった artifact はテスト実行が tmp 配下に生成したもののみ)。issue #131 が open。
- **verifier の LLM 化 / staged review は未着手**(想定通り。Phase B の作業)。
- **BLOCKED PR の原因(branch protection)は未解明のまま**、件数はむしろ増えた(2→3)。

**悪化したもの:**

- **PR バックログ 5→12 件。** 滞留中に BEHIND 化(verifier #65 #66)が発生しており、「作ったが古くなって作り直し」という最も無駄なコストが出始めた。
- ローカル運用面: 全 checkout が sync 用ブランチのまま放置され、`_pr-work/` の残置が積み上がっている。fleet 運用の hygiene が readiness レビューの指摘通り証明できていない。

## 4. 今回新たに顕在化した問題 — スループットと吸収力の不均衡

07-03 レポートの P1〜P5 は引き続きすべて有効だが、本評価で新たに強調すべき構造問題が 1 つある。

**自動化のカデンツ(scout 1 日 3 回 + monitor + readiness 系)が、人間 1 人のレビュー帯域を前提にしていない。**

- issue の生成速度 > PR の消化速度 のとき、バックログは単調増加する。実際 5 日で PR は倍増、issue は 17 件滞留。
- 滞留 PR は BEHIND/コンフリクト化し、builder のやり直しコスト(=API コストと時間)に変換される。
- 価値式(マージ率 × (1−修正率) ÷ レビュー工数)の観点では、**マージされない PR は価値ゼロでコストのみ**。

これはトヨタ生産方式で言う「作りすぎのムダ」そのものであり、Kaizen を名乗るシステムとしては**プル型(レビュー帯域が空いたら作る)への転換、すなわち WIP 制限の導入**が正しい対処になる。外部プロダクトへのハーネス(最終目的)でも「メンテナのレビュー帯域を尊重するエージェント」は信頼獲得の必須条件であり、今ここで解く価値がある。

## 5. 強み(維持すべきもの — 前回から不変)

- 責務分離(Builders build / Verifiers verify / Loop coordinates)と Standalone Project Principle。
- JSON Schema による契約駆動統合、プロバイダ非依存(Codex/Claude/カスタム)。
- 安全設計(worktree 隔離、env allowlist、protected paths、PR-first、人間マージ必須)。
- 週次 readiness レビューが自組織の弱点を正直に文書化する文化。
- CI の速さと安定(全リポジトリ green、30 秒以内)。

## 6. 結論と次の一手

方向性は 07-03 レポートのロードマップ(A: 計測と証明 → B: ゲートの実体化と汎化 → C: 外部ハーネス)を維持する。ただし **Phase A の先頭に「バックログ排出と WIP 制限」を追加**する。生成を続けながら計測を整えても、滞留が手戻りを生み続けるため、まず流れを回復させる。

今週のアクション(優先順):

1. **open PR 12 件をゼロにする**(レビュー順序と手順は Playbook 参照。verifier #64 を最初に)。
2. **WIP 制限を導入する**(組織全体で生成 PR の open 上限を決め、超過中は scout/maintenance の新規着手を止める)。
3. **BLOCKED の根本原因(branch protection 設定)を特定・解消する。**
4. **`kaizen smoke` を 1 回実運用で実行し artifact を保存、issue #131 を閉じる。**
5. **メトリクス永続化**(#151 の集計を `.github` に週次 PR で追記する仕組み)。

実施手順・完了判定・具体コマンドは同ディレクトリの **[improvement-playbook.ja.md](./improvement-playbook.ja.md)** にまとめた。以後の改善作業はそちらをチェックリストとして進めること。
