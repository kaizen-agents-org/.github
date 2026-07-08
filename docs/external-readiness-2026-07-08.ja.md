# 外部適用準備状況レポート(2026-07-08)

質問: **「このハーネス群を他のプロジェクトに適用する仕組みは万全と言えるか?」**

回答: **万全とは言えない。** 導入の「入り口」(init / doctor / onboarding kit 設計)は形になりつつあるが、外部適用を支える 4 本柱 — ①非 Node 実績、②実行環境の可搬性、③信頼境界、④判定品質の証拠 — のいずれも完了していない。プレイブックの区分で言えば、現在地は Phase A 末〜B 序盤であり、Phase B-4(汎化検証)と Phase C(外部ハーネス)は未着手。

関連: [improvement-playbook.ja.md](./improvement-playbook.ja.md) / [onboarding-kit-design-2026-07-05.ja.md](./onboarding-kit-design-2026-07-05.ja.md) / [product-adoption-plan-2026-07-05.ja.md](./product-adoption-plan-2026-07-05.ja.md)

---

## 1. できていること(外部適用の観点で)

| 項目 | 根拠 |
| --- | --- |
| `kaizen init` が冪等な導入コマンドとして仕様化、`kaizen doctor` で前提検査 | kaizen-loop `docs/02-cli-spec.md` §`kaizen init` / §doctor |
| setup / verify コマンドは per-project 設定値(npm 固定ではない) | kaizen-loop `docs/03-config-spec.md`(`setup:` / `verify:` は任意コマンド) |
| onboarding kit の設計と issue 化 | [onboarding-kit-design-2026-07-05.ja.md](./onboarding-kit-design-2026-07-05.ja.md)、.github#112、kaizen-loop#178(profile overlay)、#179(非 Node stack 検出) |
| verifier eval に非 Node ログのケースが存在 | golden: gp-005(cargo)/gp-006(pytest)/gp-007(go test)、seeded: sb-005/sb-006 |
| プロンプトに「issue 本文より repo 指示・制約が優先」の明文 | kaizen-loop `src/agents/prompt.ts:20`(builder)/ `:91`(verifier) |
| ブロック分類・WIP 制限・smoke などの運用 hardening が進行 | ledger/current.md 2026-07-06、kaizen-loop#184/#186-#189 マージ済み |

## 2. ギャップ(万全と言えない理由)

### G1. 非 Node リポジトリでの完走実績がゼロ(Playbook B-4 未着手)

Issue→PR→マージの実績は Node/TypeScript の自組織 3 リポジトリのみ。`kaizen init` の stack 検出も Node 前提(kaizen-loop#179 が open)。外部プロダクトは Python/Go/Rust 等である可能性が高く、「崩れる前提」(verifier のログパターン、builder のスタック仮定、setup コマンド前提)が未検証。

### G2. eval コーパスが目標の半分以下(Playbook B-1 未達)

現在 23 ケース(golden 12 + seeded 11)。目標は 50+ / 非 Node 10+。非 Node は現状 5 ケース。fixture 形式(実リポジトリ + 注入バグ)への移行は verifier#81 が担うが、verifier#94 の通り blocked 状態で、後続の #82(LLM Stage 0)の受け入れ条件を塞いでいる。**「verifier が外部スタックでも正しく block/pass できる」ことの証拠が薄いまま**。

### G3. 実行環境の可搬性がない(Playbook C-1 未着手 + 追跡消失)

現行の実行系はローカル macOS + launchd/cron + ローカル認証済み CLI(Codex/Claude)前提。GitHub Actions reusable workflow(C-1)は存在しない(各リポジトリの workflow は `ci.yml` のみ)。さらに **C-1/C-2 の tracking issue(kaizen-loop#173/#174)は 2026-07-06 に「gated roadmap」として close されており、Phase C の追跡が issue 上から消えている**。また dogfood 自身が sandbox/認証起因の失敗を頻発させており(kaizen-loop#194、ledger 07-06 の verifier#81 リトライ記録)、統制された自環境ですらこの状態なら、外部環境ではさらに脆い。

### G4. 信頼境界が「文言」止まりで構造的でない(Playbook C-2 未実施)

`prompt.ts` は issue 本文・コメントをプロンプトへ**生のまま補間**している(`src/agents/prompt.ts:24,95`、`src/goals/runner.ts:346`)。優先順位の明文はあるが、issue 本文に `# Constraints` 等の見出しや JSON フェンスを書けばプロンプト構造に紛れ込める。自組織では issue 作成者が身内なので許容できたが、**外部リポジトリでは第三者が issue を書ける**ため prompt injection の攻撃面が質的に変わる。execution authorization ラベルのデフォルト必須化、`safety.envAllowlist` / protected paths の外部基準監査も未実施。

### G5. 「同水準」を測るメトリクス基盤が未完(Playbook A-5 残件)

Phase C 出口条件は「外部プロダクトで人手修正なしマージ率が自組織と同水準」。しかし北極星メトリクスの週次永続化(`.github` の `docs/metrics/<ISO週>.md`)は**存在しない**(2026-07-08 時点で `docs/metrics/` ディレクトリなし。定義は `docs/production-readiness/metrics.md` にあり)。自組織のベースラインが取れていないため、外部適用の成否を判定する物差しがない。

## 3. アクション(issue マッピング)

| ギャップ | 対応 issue | 状態 |
| --- | --- | --- |
| G1 stack 検出 | kaizen-loop#179(非 Node stack 検出)、#178(profile overlay)、.github#112(onboarding kit) | 既存 open |
| G1 完走実績 | **.github#120**: 非 Node リポジトリで Issue→PR→マージを 1 件完走(B-4) | 新規作成済み |
| G2 コーパス | verifier#81(fixture corpus)/ #94(blocked 解消)→ **verifier#97**: 50+/非 Node 10+ への拡充 | 新規作成済み |
| G3 可搬性 | **kaizen-loop#199**: C-1 GitHub Actions reusable workflow(Actions secrets 認証含む) | 新規作成済み |
| G4 信頼境界 | **kaizen-loop#198**: issue 本文・コメントの構造的ラップ + **kaizen-loop#200**: authorization ラベル必須化・safety デフォルト外部基準監査 | 新規作成済み |
| G5 メトリクス | **.github#119**: 週次メトリクスを `docs/metrics/` に PR で永続化(A-5 完了) | 新規作成済み |
| C-3 導入ドキュメント | **.github#122**: 第三者メンテナ向け導入ガイド(アウトライン起案済み — issue コメント参照) | 新規作成済み |
| C-3 外部実運用 | **.github#123**: 外部プロダクト 1 件で継続運用、North-star 同水準を確認 | 新規作成済み |
| 全体追跡 | **.github#121(umbrella)**: 対応表・実施順序・チェックリスト | 新規作成済み |

## 4. 判定の目安(いつ「万全に近い」と言えるか)

1. 非 Node リポジトリで Issue→PR→マージ 1 件完走、前提崩れがすべて issue 化済み(B-4 出口)
2. eval 50+ / 非 Node 10+ が CI 必須チェックで回帰検出できる(B-1 出口)
3. `.kaizen/config.yml` + workflow 1 ファイルでエフェメラル環境導入が完結(C-1)
4. issue 本文が構造的に untrusted 扱いされ、外部基準の safety デフォルト監査済み(C-2)
5. 週次メトリクスで自組織ベースライン(人手修正なしマージ率)が確立(A-5)
