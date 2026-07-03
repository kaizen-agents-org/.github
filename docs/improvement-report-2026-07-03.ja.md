# Kaizen Agents 改善レポート — プロダクト価値最大化のための開発指針

日付: 2026-07-03(同日改訂: 最終目的の確認を反映)
対象: kaizen-agents-org 全リポジトリ(`.github` / `kaizen-loop` / `builder-agent` / `verifier` / `coderabbit` / `renovate-config`)
根拠: 各リポジトリの README・docs・ソースコード・テスト・直近コミット履歴、および `production-readiness/logs/2026-06-29.md` の実測値。

**確定した前提:** 現在のドッグフーディングは手段であり、最終目的は**任意の外部プロダクトにハーネスして運用すること**である(オーナー確認済み)。本レポートの優先順位はこの前提で構成している。

---

## 1. エグゼクティブサマリ

Kaizen Agents は「GitHub Issue を、人間がレビュー・マージできる高品質な PR に変換する」システムであり、
**アーキテクチャ設計(Builders build / Verifiers verify / Kaizen Loop coordinates)と自己ドッグフーディングの運用文化はすでに高い水準にある**。
kaizen-loop は 182 テストを持つ実用段階の CLI で、Issue 選択 → worktree 隔離 → builder 実行 → 機械検証 → verifier → PR 作成の垂直スライスは動いている。

一方で、プロダクトの価値命題「**人間が安心して低コストでマージできる PR**」を支える 3 点が最も弱い:

1. **verifier が正規表現ベースのキーワード照合(368 行)であり、"独立した品質ゲート" という製品の核心的差別化が実体を伴っていない。** eval コーパスも 6 ケースのみ。
2. **価値の最終地点(マージ)が計測されていない。** メトリクスはローカル限定・分母なしで、「改善(Kaizen)」を名乗るプロダクト自身が週次の改善を証明できない。
3. **生成 PR のバックログが人間レビューで滞留しており、E2E スモーク実績も未記録。** PR を「開く」能力は証明済みだが、「マージされて価値になる」ところが未証明。

**結論: 次の四半期は機能追加ではなく「信頼の証明」に投資すべき。**
具体的には (A) マージ実績とメトリクスの永続化、(B) verifier の LLM 化 + eval コーパス拡充、(C) 実行環境のポータビリティ(GitHub Actions 対応)の順で取り組むことを推奨する。

---

## 2. 現状分析

### 2.1 構成と成熟度

| リポジトリ | 役割 | 規模(概算) | テスト | 成熟度 |
| --- | --- | --- | --- | --- |
| `kaizen-loop` | オーケストレータ CLI | 約 8,800 行 TS / 52 ファイル | 26 ファイル・182 テスト | **Phase 2、実用段階** |
| `builder-agent` | 実装ワーカー(Codex/Claude アダプタ + フォールバック) | 約 1,900 行(JS→TS 移行中) | 36 テスト | MVP |
| `verifier` | 独立品質ゲート | 約 2,600 行 TS | 39 テスト + eval 6 ケース | **MVP(決定的ヒューリスティック)** |
| `.github` | 組織ドキュメント・共有 skill・Codex automation | — | sync 契約テスト | 運用中 |
| `coderabbit` / `renovate-config` | 共有レビュー/依存更新設定 | — | — | 運用中 |

### 2.2 強み(維持すべきもの)

- **責務分離の設計原則が一貫している。** builder は PR を作らず、verifier はファイルを編集せず、loop は実装しない。各コンポーネントが単体でも使える「Standalone Project Principle」は、テスト容易性と交換可能性を保証しており、崩してはならない。
- **契約駆動の統合。** JSON Schema(build-request / build-result / self-review / verdict)+ stdin プロンプト + 結果ファイルパス環境変数という薄い契約は、プロバイダ非依存(Codex / Claude / カスタム CLI)を実現している。
- **自己ドッグフーディングと週次 readiness レビューの文化。** 自分の弱点を自分で文書化できている(2026-06-29 レビューの gap 指摘は本レポートの分析とほぼ一致する)。この誠実さ自体が資産。
- **安全設計。** worktree 隔離、env allowlist、ディスク preflight、run デッドライン、プロセスツリー終了、protected paths、PR-first ポリシー。自律エージェント製品として競合より慎重で、これは信頼獲得の武器になる。

### 2.3 実測されている問題(2026-06-29 readiness レビューより)

- Issue→PR 成功率: ローカル観測で 9/13。失敗 4 件はすべて verifier 実行時の `pnpm test` 失敗(長い TMPDIR パス問題 #48–#50)。
- サンドボックス E2E スモーク実績: **0 件**(`kaizen smoke` は実装済みだが一度も artifact が記録されていない)。
- 生成 PR バックログ: 5 件オープン、うち 2 件が `mergeStateStatus: BLOCKED`。
- マージ後修正率・verifier verdict 集計・needs-human 率: **計測不能(分母なし)**。
- ローカル checkout の状態: 全リポジトリが sync 用ブランチ上で origin より behind(最大 14 コミット)。fleet refresh が実運用レイアウトで未証明。

---

## 3. 価値命題の再確認 — 何が「最も価値がある」のか

このプロダクトの価値は「PR を自動で開けること」ではない。類似ツール(Copilot Workspace、Devin、SWE-agent 系)はすでに PR を開ける。差別化は設計文書自身が述べている通り:

> A human maintainer reviews and merges that PR, and the merge resolves the original issue.

つまり価値 = **「レビューコストが低く、修正なしでマージでき、マージ後に壊れない PR」を安定供給すること**。これを分解すると:

```
価値 = マージ率 × (1 − マージ後修正率) ÷ 人間レビュー工数
```

この式の分子を上げるのが verifier の質と builder の evidence 品質、分母を下げるのが PR 本文の証拠提示力。**現在この式のどの項も計測されていない**ことが最大の問題であり、逆に言えば計測を始めるだけで開発の優先順位判断が劇的に正確になる。

**外部ハーネスが最終目的であることによる追加の含意:** 上の価値式は「自分のリポジトリでの値」ではなく「**初見の外部リポジトリでの値**」で成立しなければならない。現在のドッグフーディング対象は全て TypeScript/Node の、エージェント自身が書いた整ったリポジトリであり、これは著しく偏ったサンプルである。外部の現実(別言語、人間が書いた雑然としたコード、flaky なテスト、信頼できない Issue 投稿者)で価値式が崩れないことが、真の完成条件になる。

---

## 4. 改善提案(優先度順)

### P1: verifier を製品の核心にふさわしい実体にする

> 詳細な実装計画は [verifier-strategy-2026-07-03.ja.md](./verifier-strategy-2026-07-03.ja.md)(現状分析・あるべき姿・6 ステップの実装手順)を参照。

**現状:** `minimal-verdict.ts`(368 行)は HARD_FAILURE_PATTERNS / SOFT_RISK_PATTERNS / HIGH_RISK_DIFF_SIGNALS の正規表現照合。意味的な正しさ(diff が Issue の意図を満たすか、テストが変更を実際に検証しているか)は一切判定できない。builder-agent README 自身が「サマリに 'rejected' という単語が含まれただけで must_fix になった」という誤検知事例を掲載している。eval コーパスは seeded 4 + golden 2 の計 6 ケース。

**なぜ最優先か:** 「独立した品質ゲート」はこの製品の存在理由そのもの。ゲートがキーワード照合である限り、(a) 誤ブロックが builder のリトライ予算を浪費し、(b) 意味的な欠陥を素通しして人間レビューの負担が減らず、価値式の分子・分母の両方を毀損する。docs/SPEC.md・DESIGN.md に staged verifier の設計が既にあるのに実装が MVP で止まっている、というギャップが組織の言行不一致として最も大きい。

**指針:**

1. **eval コーパスを先に拡充する(実装より先)。** 目標 50+ ケース。過去の生成 PR(マージされたもの / 修正が必要だったもの)を golden ケース化し、seeded バグ(off-by-one、テスト削除による偽 green、Issue と無関係な diff、危険な移行)を体系的に追加する。これが verifier 改修の回帰防止網になる。
2. **LLM ベースの staged review を、現在の決定的ゲートの「上」に追加する。** 決定的チェック(機械検証ログの失敗検出)は高速・無料・確実なので残し、意味判定(intent-diff 整合、テスト実効性、リスク領域のカバレッジ)を LLM ステージに委ねる。builder-agent が既に持つプロバイダ抽象(Codex/Claude/カスタム + フォールバック)を verifier に横展開すれば実装コストは小さい。
3. **verdict に「根拠の引用」を必須化する。** must_fix には該当 diff 行・ログ行への参照を付け、PR 本文に転記する。これが人間レビュー工数を直接下げる。
4. 先行して #48–#50(長 TMPDIR での pnpm/tsx 失敗)を潰す。現在の検証失敗 4/13 はすべてこれであり、verifier の質以前に verifier が走らない問題。

### P2: 「マージまで」を計測する — North-star メトリクスの永続化

**現状:** `kaizen status --metrics` はあるがローカル集計のみ。readiness レビューは毎週「分母がない」と書き続けている。

**指針:**

1. **North-star: 「人手修正なしマージ率」**(生成 PR のうち、レビューコメントによる追加コミットなしでマージされた割合)を定義する。補助指標: time-to-merge、Issue→PR 成功率、verifier block 率(と誤 block 率)、needs-human 率、マージ後 revert/修正率。
2. **run summary を GitHub 上に永続化する。** 案: 各リポジトリの `kaizen run` 完了時に週次集計を `.github` リポジトリの `docs/metrics/` へ PR で追記する(既存の daily-dogfood-sync と同じパターンが使える)。ローカル `~/.kaizen` を唯一の記録にしない。
3. 週次 readiness レビュー(既存 automation)がこの集計を読むだけで判定できる状態にする。「メトリクスが取れない」という指摘を毎週書く工数をゼロにする。

これは実装コストが最小で、以後のすべての優先順位判断の精度を上げるため、**着手順としては P1 より先でよい**(効果の大きさで P1、着手順で P2 が先)。

### P3: E2E の証明とバックログの解消 — 「開ける」から「マージされる」へ

**現状:** `kaizen smoke` 実装済み・実行実績ゼロ。生成 PR 5 件が滞留、2 件は BLOCKED。

**指針:**

1. 今週中に **sandbox smoke を 1 回実行し artifact を保存**する(readiness レビュー 2 回連続で最優先指摘されている)。以後、スケジューラに smoke を週 1 で組み込み、artifact を P2 のメトリクスに合流させる。
2. BLOCKED PR の原因(branch protection と自動生成 PR の相性)を特定して解消する。自動生成 PR が構造的に BLOCKED になるなら、それはパイプラインのバグと同格。
3. **PR 本文を「レビュー 5 分で判断できる証拠パッケージ」に進化させる**: 元 Issue、builder の task understanding、変更ファイルと理由、実行された検証コマンドと結果、verifier verdict と根拠引用、残存リスク。実装状況ドキュメントの First Acceptance Test が要求する項目をテンプレート化して必須にする。人間レビューがボトルネックである以上、ここが価値式の分母を下げる最短経路。

### P4: 外部ハーネスの前提条件を揃える — ポータビリティ・汎化・信頼境界

最終目的が「任意のプロダクトへのハーネス」である以上、P4 は単なる利便性改善ではなく**製品化の前提条件**である。3 つの独立した課題に分解する。

**(a) 実行環境のポータビリティ**

現状、スケジューラはローカルマシン上のジョブ、状態は `~/.kaizen`、`codex`・`claude`・`gh`・`builder-agent`・`verifier` が PATH にある前提。readiness レビューでも「worktree が stale」「fleet refresh がこのレイアウトでは証明できない」という運用摩擦が繰り返し出ている。

1. **GitHub Actions 上で `kaizen fix <issue>` が動く reusable workflow を提供する。** これにより stale worktree / fleet refresh 問題がエフェメラル環境で消滅し、第三者リポジトリが `.kaizen/config.yml` + workflow 1 ファイルで導入できるようになる。ローカル実行は開発・dogfood 用として残す。
2. `kaizen watch`(Phase 4 予定)より Actions 対応を先に。イベント駆動(issue labeled → workflow dispatch)なら watch デーモンは不要になる可能性が高い。

**(b) スタック非依存への汎化 — ドッグフーディングのサンプル偏り**

現在の運用実績は全て TypeScript/Node、かつエージェント自身が整備してきたリポジトリに限られる。契約層(`commands.verify` は任意コマンド、builder はプロバイダ非依存)は言語非依存に設計されているが、**実際に非依存かは一度も検証されていない**。特に:

1. verifier の HARD_FAILURE / POSITIVE_VERIFICATION パターンは npm/pnpm/vitest 系ログに適合するよう育っている疑いが強い。pytest・cargo・go test・gradle 等のログで失敗検出・成功検出が機能するかを eval コーパスに**他言語ケースとして追加**する(P1 のコーパス拡充と統合)。これは P1 で LLM ステージを推す追加根拠でもある — 正規表現はスタックごとに増殖するが、LLM 判定は自然に汎化する。
2. **「自分たちに似ていないリポジトリ」でのドッグフーディングを前倒しで開始する**(四半期末ではなく Phase B 中)。候補: 別言語の個人リポジトリ、または意図的に雑然とした fixture リポジトリ。整った自作リポジトリで成功率を上げ続けても、外部適用時の成功率は予測できない。安いうちに前提の崩れを発見する。

**(c) 信頼境界の再定義 — Issue 本文は信頼できない入力になる**

ドッグフーディング中は Issue の投稿者 = 運営者自身であり、Issue 本文は事実上信頼された指示である。外部プロダクトにハーネスした瞬間、**Issue 本文は第三者が書ける untrusted input になり、builder への prompt injection 経路になる**。既存の intake gate(「issues are evidence, not orders」)は思想として正しいが、敵対的入力を想定した設計ではない。

1. Issue 本文から builder プロンプトへの流し込みに、指示と引用データの分離(本文を「参照情報」として明示的にラップ)を入れる。
2. 実行権限ラベル(`kaizen queue` の execution authorization)を外部運用ではデフォルト必須にし、「誰でも Issue を立てれば エージェントがコードを書く」状態を防ぐ。
3. `safety.envAllowlist` / protected paths / forbidden paths のデフォルトを「外部リポジトリで安全側」に見直す(現在のデフォルトが dogfood 前提になっていないか監査する)。
4. verifier の高リスク diff 検出(auth / secrets / billing / migration)は、この文脈では「エージェントが騙されて危険な変更を書いた」ことの最終防衛線になる。P1 の LLM 化の際もこの決定的チェックは必ず残す。

### P5: 投資バランスの是正 — orchestrator 肥大の抑制

**現状:** kaizen-loop 8,800 行に対し builder 1,900 行・verifier 2,600 行。コマンドも run/fix/report/smoke/queue/improve/goal/status/scheduler/fleet/logs/doctor/list と増加中。品質を決めるのは builder と verifier なのに、コード投資がオーケストレータに偏っている。

**指針:**

1. 当面 kaizen-loop への新コマンド追加を凍結し(hardening は継続)、開発リソースを verifier(P1)と builder artifact 品質に振り向ける。
2. builder-agent の TS 移行を完了させ、テストを実行系(プロバイダ失敗分類・フォールバック・payload 正規化)中心に拡充する。1,900 行に対しテスト 1 ファイルは薄い。
3. `goal` / `improve` 系の上位機能は、P2 のメトリクスで基本ループの質が証明されるまで拡張しない。設計文書の「Product Kaizen は後回し」という判断は正しく、維持すべき。

---

## 5. 推奨ロードマップ

| フェーズ | 期間目安 | やること | 完了判定 |
| --- | --- | --- | --- |
| **A. 計測と証明** | 〜2 週間 | sandbox smoke 実行+artifact 保存 / 週次メトリクス永続化(PR 経由で `.github` に集約)/ BLOCKED PR 原因解消・バックログ消化 / #48–#50 TMPDIR 修正 | smoke artifact 1 件以上、週次メトリクスに分母が付く、生成 PR バックログ 0 |
| **B. ゲートの実体化と汎化検証** | 〜2 ヶ月 | verifier eval コーパス 50+ ケース(**他言語スタックのログを含む**)/ LLM staged review を決定的ゲートの上に追加 / verdict への根拠引用必須化 / PR 本文の証拠テンプレート化 / **自分たちに似ていないリポジトリ 1 件でドッグフーディング開始**(別言語 or 雑然とした fixture) | eval agreement を維持したまま誤 block 率低下を実測、人手修正なしマージ率の改善がメトリクスで確認できる、非 Node リポジトリで Issue→PR が 1 件完走 |
| **C. 外部ハーネス** | 〜四半期 | GitHub Actions reusable workflow / 信頼境界の整備(Issue 本文の untrusted 化対応・実行権限ラベル必須化・安全デフォルト監査)/ 第三者リポジトリへの導入ドキュメント / 外部プロダクト 1 件での実運用 | 組織外プロダクトで Issue→PR→マージが継続運用され、North-star メトリクスが自組織と同水準 |

フェーズ A は「言っていることを証明する」、B は「製品の核心を本物にし、外部適用の前提を検証する」、C は「任意のプロダクトに安全にハーネスする」段階である。B の成果が North-star メトリクス(A で整備)に現れることを各フェーズの出口条件とする。

**重要な順序判断:** 外部ハーネスが目的だからといって Actions 対応(C)を最初にやるべきではない。ゲートが正規表現のまま外部リポジトリに載せると、誤ブロックと素通しがそのまま外部メンテナの第一印象になり、信頼を失ってからの回復は高くつく。**A→B で「信頼できる」を証明してから C で「届ける」**、ただし B の中で汎化の検証だけは前倒しする、という順序が最も安全に速い。

---

## 6. やらないこと(明示)

- **自律マージ(human-out-of-the-loop)への移行**: readiness レビューの判定通り時期尚早。マージ後修正率が計測され、十分低いことが証明されるまで着手しない。
- **Product Kaizen(何を作るべきかの発見層)**: design-decisions.md の判断を維持。ループの質が証明されてから。
- **kaizen-loop への新規コマンド追加**: フェーズ B 完了まで凍結。
- **verifier の決定的チェックの廃止**: LLM ステージは「追加」であり「置換」ではない。機械検証ログの失敗検出は決定的なまま残す。

---

## 7. まとめ

このシステムの設計思想・安全設計・自己批判の文化は、自律コーディングエージェント製品として十分に差別化可能な水準にある。足りないのは新機能ではなく、**「高品質な PR」という約束の、外部リポジトリでも成立する証明**である。

- 計測なしに改善なし — Kaizen を名乗る以上、まず North-star メトリクス(人手修正なしマージ率)の永続化から。
- ゲートが本物になれば、人間レビューの負担が下がり、マージ率が上がり、価値式全体が改善する。verifier への投資が最もレバレッジが高く、LLM 化はスタック非依存への汎化も同時に解決する。
- ドッグフーディングのサンプル偏り(整った自作 Node リポジトリのみ)を自覚し、似ていないリポジトリでの検証を前倒しする。
- 外部ハーネス時には Issue 本文が untrusted input になる。信頼境界の再設計(P4-c)を Actions 展開とセットで完了させてから外部プロダクトに載せる。

次のアクション(今週): (1) `kaizen smoke` を実行して artifact を保存、(2) 週次メトリクス永続化の Issue を kaizen-loop に登録、(3) verifier #48–#50 の修正、(4) BLOCKED PR 2 件の解消。
