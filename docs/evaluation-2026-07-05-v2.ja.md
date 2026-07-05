# Kaizen Agents Organization 評価レポート — 2026-07-05 v2(同日午後の再評価)

対象: kaizen-agents-org 全 6 リポジトリ(`.github` / `kaizen-loop` / `builder-agent` / `verifier` / `coderabbit` / `renovate-config`)
根拠: GitHub 実測(open PR/issue、CI run、branch protection API、PR #85 の review threads)、各リポジトリ `origin/main` のソース確認(fetch 済み)、ローカル checkout の状態確認。
前回評価: [evaluation-2026-07-05.ja.md](./evaluation-2026-07-05.ja.md)(同日午前・main 同期直後)

> 注: 前回評価(同日午前)の後に kaizen-loop で WIP 制限・smoke 永続化を含む複数の PR がマージされており、本レポートはその差分を反映した最新スナップショットである。

---

## 1. 総合評価

**評点: A-(設計 A / 運用の証明 B+)** — 午前評価から「運用の証明」が半段階上昇。

午前評価で「未着手」とされた **WIP 制限(A-3)が実装済み**(`safety.wipLimit` デフォルト 5、組織全体の open 生成 PR 数で判定、超過時は intake をスキップ)、**sandbox smoke の実運用実績(A-4)も達成**(artifact が `kaizen-loop/docs/smoke-runs/` にコミットされ、issue #131 が 07-04 に close)。プレイブック Phase A の主要項目のうち残るは **メトリクスの GitHub 永続化(A-5)のみ**となった。

一方で本評価により **2 つの新事実** が判明した:

1. **BLOCKED の根本原因を特定**: branch protection の `required_conversation_resolution: true` + レビュー bot(CodeRabbit / Codex connector)の未解決スレッドが原因。設定ミスではなく品質ゲートが機能している状態だが、**未文書化**(A-2 の完了判定は未達)。
2. **verifier の正規表現ゲートの誤検知が実運用で発生**(verifier issue #86: 成功テスト出力中の "blocked" という語を blocking failure と誤判定)。午前評価が「意味的な誤検知の根本原因はまだ残っている」と警告した通りの事象が、予測どおり顕在化した。

## 2. 現状スナップショット(07-05 午後実測)

| 項目 | 午前(07-05 v1) | 今回(07-05 v2) | 判定 |
| --- | --- | --- | --- |
| open PR(生成物) | 1 件 | **1 件**(builder-agent #85、skills sync、BLOCKED) | 維持(#72 はマージ済み、#85 は新規) |
| BLOCKED PR | 0 件 | **1 件**(#85 — 未解決レビュースレッド 2 件が原因、ゲートは正常動作) | 原因特定済み |
| open issue(全リポジトリ) | 9 件(kaizen ラベル) | **27 件**(kaizen-loop 9 / verifier 9 / builder-agent 5 / .github 4、うち Roadmap 系 8 件) | issue 化が進んだ(下記 §5.4) |
| CI(main) | 全リポジトリ成功 | **全リポジトリ成功** | 維持 |
| WIP 制限 | 未着手 | **実装済み**(`src/orchestrator/wipLimit.ts`、config デフォルト 5、`kaizen status --metrics` にも反映) | **A-3 実質完了**(超過スキップの実観測のみ未) |
| sandbox smoke 実運用実績 | 0 件 | **1 件**(`docs/smoke-runs/2026-07-04T07-49-09Z-issue-157.json`、issue #131 close 済み) | **A-4 ほぼ完了**(週次ジョブ登録は #171 で追跡中) |
| メトリクス永続化(`.github/docs/metrics/`) | 未作成 | **未作成**(issue #158 で追跡中) | A-5 未達 |
| verifier eval コーパス | 20 ケース | **23 ケース**(golden 12 + seeded 11) | 微増 |
| verifier 追加ハードニング | — | **secrets redaction(#79)、direction-aware high-risk check(#77)がマージ** | 前進 |
| verifier LLM 化ロードマップ | 戦略ノートのみ | **issue #80〜#85 として Step 別に起票**(Stage 6 judge 純関数化 / Claude API Claim 抽出 / 反証ゲート / Probe Driver SDK) | Phase B 着手準備完了 |
| ローカル fleet hygiene | 同期直後 clean | **数時間で再劣化**(builder-agent 6 behind、verifier 2 behind + dirty、kaizen-loop はマージ済みブランチ上 + 未 PR の push 済みコミット 1 件) | **構造問題(§5.1)** |

## 3. 組織構成の評価(何が良いか)

構成そのものは引き続き高水準。特筆すべき設計判断:

- **責務分離が明確な 6 リポジトリ構成**: orchestrator(kaizen-loop)/ worker(builder-agent)/ 独立ゲート(verifier)の 3 コンポーネント + 共有設定(coderabbit / renovate-config)+ ドキュメント・自動化ハブ(.github)。verifier を builder から独立させた判断は「自己申告を自己検証させない」原則の体現で、外部ハーネス化のゴールに直結する。
- **verifier の eval-first 開発**: SPEC / DESIGN / EVAL / MVP の 4 文書、23 ケースのコーパス(pytest / cargo / go test / eslint の実ログ込み)、`thresholds.json` による回帰ゲート、CI 必須化。**LLM 化(Step 3〜)より先にコーパスと閾値を固めた順序は正しい**。
- **dogfood-sync の契約化**: `.github/dogfood-sync/manifest.json` + ターゲット別契約 + 契約チェックスクリプト + シェルスクリプト自体のテスト。ワークフローも caller(`daily-dogfood-sync.yml`)と reusable(`sync-daily-dogfood.yml`、`workflow_call`)に分離されており、初見で重複に見えるが正しいパターン。
- **証拠強度の階層化が始まっている**: verifier の `evidence_grade`(executed/reported)、PR 本文の evidence strength ラベル(kaizen-loop #161 マージ済み)、smoke artifact の Readiness Evidence 表(`issueLinkRecognized` を「ブランチ名より強い証拠」と明示する等、証拠の強弱を意識した設計)。
- **branch protection が実質的な品質ゲートとして機能**: required check(test)+ conversation resolution 必須 + enforce_admins。生成 PR にレビュー bot の指摘が残っている限りマージできない構造は、自律マージを凍結している現フェーズの方針と整合する。

## 4. プレイブック Phase A 進捗(更新)

| 項目 | 午前評価 | 今回 |
| --- | --- | --- |
| A-1 PR バックログ 0 | ほぼ達成 | **達成**(open は当日生成の sync PR #85 のみ) |
| A-2 BLOCKED 根本原因解消 | 実質解消(未文書化) | **原因特定済み・未文書化**(下記 §5.2) |
| A-3 WIP 制限 | 未着手 | **実装完了**(超過スキップのログ実観測のみ残) |
| A-4 sandbox smoke | 未達成 | **達成**(#131 close、artifact コミット済み。週次ジョブは #171) |
| A-5 メトリクス永続化 | 部分達成 | **未達**(#158 で追跡中。Phase A の最後の宿題) |
| A-6 fleet hygiene | 今回作業で解消 | **再劣化**(§5.1 — 恒久対策なしでは維持できないことが実証された) |

## 5. 発見事項と改善提案(優先度順)

### 5.1 【最優先】ローカル fleet hygiene は「掃除」では維持できない — worktree 運用への移行を

午前の同期からわずか数時間で再劣化した:

- **builder-agent**: main が 6 コミット behind(#72 のマージを未取得)
- **verifier**: main が 2 コミット behind + `minimal-verdict.ts` と test に**未コミットの変更**(進行中の作業が primary checkout 上に裸で存在)
- **kaizen-loop**: マージ済みブランチ `codex/prompt-source-precedence`(PR #165)上に留まり、さらに**そのブランチにしか存在しない push 済みコミット `066c2ab`「Include issue comments in verifier prompts」が main に未反映・対応 PR なし**で漂流している。放置すればブランチ削除で作業が消える。

これは A-6 を「掃除タスク」として扱う限り毎日再発する。**エージェントの作業を worktree に隔離し、primary checkout は常に clean main を保つ**構造変更が必要。関連 issue は既にある(kaizen-loop #87/#88 系、.github #104「Daily dogfood sync rejects Git worktree targets」)ので、**これらの優先度を Phase A 残項目と同格に引き上げる**ことを提案する。即時対応として `066c2ab` は PR 化するか意図的に破棄するかを判断すべき。

### 5.2 BLOCKED の正体は `required_conversation_resolution` — design-decisions.md に記録して A-2 を完了させる

builder-agent の protection 実測: required check = `test`(strict)、**required reviews なし**、`enforce_admins: true`、**`required_conversation_resolution: true`**。PR #85 は test / CodeRabbit とも SUCCESS だが、CodeRabbit(Major 1 件)と Codex connector(P2 1 件)の**未解決スレッド 2 件**により BLOCKED になっている。

つまり「checks green なのに BLOCKED」は謎でも不具合でもなく、**レビュー bot の指摘に応答するまでマージさせない設計**が働いている。これは望ましい挙動だが、2 回の readiness レビューと 2 回の評価レポートで「原因不明」として繰り返し調査されており、調査コストが無駄に発生している。**`.github/docs/design-decisions.md` に「生成 PR と conversation resolution の運用方針」(誰が・いつスレッドを resolve するか、bot 指摘への応答責務は builder か人間か)を 1 節追記するだけで A-2 が完了する**。実装ゼロで済む最安の改善。

なお、自動 skills-sync PR にすら CodeRabbit の Major 指摘が付いている点は、**sync 系 PR の生成物の品質も他の生成 PR と同じゲートを通っている**ことを意味し、健全である。

### 5.3 verifier の誤検知が実運用で発生(#86)— Phase B(LLM 化)着手の判断材料が揃った

verifier issue #86「成功しているテスト出力中の "blocked" という語を blocking failure と誤判定」は、戦略ノートと午前評価が予測していた正規表現ゲートの意味的限界の**実データによる確認**である。プレイブックは「正規表現ゲートの限界(誤検知)を実データで再確認してから進めるとよい」としていたが、**その条件が満たされた**。

推奨: (1) #86 の実ログを golden ケースとしてコーパスに追加(誤検知の再現を eval で固定)、(2) 起票済みの Step 3(#82: Claude API による Claim 抽出)に着手。決定的ゲートは残し LLM は追加(置換ではない)という凍結方針は維持する。

なお小さな衛生問題として、seeded コーパスに番号プレフィックスの重複がある(`sb-009-unexecuted-command-blocks` と `sb-009-unexplained-diff-needs-context`)。フル ID は一意なので実害はないが、次のケース追加時にリネームしておくとよい。

### 5.4 issue 数が 9 → 27 に増加 — Roadmap 起票は良いが、WIP 制限の「生成側」への適用を忘れない

verifier #80〜#85、kaizen-loop #171〜#174 など、戦略ノートの Step / Phase を issue 化した結果 open issue が 3 倍になった。ロードマップの可視化としては正しい。ただし午前の組織設計メモ(§2.1「スループット制御が生成側にしか存在しない」)の指摘どおり、**issue の生成速度が消化速度を上回る構造は PR バックログ問題の再演になり得る**。実装済みの `wipLimit` は「PR の滞留」で intake を止める仕組みであり、issue の滞留は制御しない。当面は Roadmap ラベル(または `kaizen:P2` 等)で「今やる issue」と「ロードマップ占位 issue」を明確に分離し、scout/monitor が Roadmap issue を重複起票しないことを確認するとよい。また builder-agent #75/#76 の `kaizen:in-progress` ラベルは対応 PR が存在せず stale の疑いがある — ラベルの実態同期も軽く行うべき。

### 5.5 メトリクス永続化(A-5)が Phase A 最後の宿題

`.github/docs/metrics/` は依然未作成(issue #158 で追跡中)。`kaizen status --metrics` はローカルで分母つき集計(reviewWindow、wipLimit 状態含む)を返せるようになったので、**残作業は daily-dogfood-sync と同じパターンで週次 PR を書くだけ**。North-star(人手修正なしマージ率)が計測されない限り、「自律マージへ進んでよいか」「外部ハーネスの品質は自組織と同水準か」という Phase B/C の出口判定ができない。明日(07-06 月曜)の週次 readiness レビュー前に着手する価値が高い。

### 5.6 builder-agent のテストが単一 1,385 行ファイルのまま(#75)

TS 移行後もテストは `test/builder-agent.test.js`(JS のまま、1,385 行)1 本で、ソース約 2,200 行に対しモジュール別の分割がない。issue #75/#76 が正しく捕捉しているので新規指摘ではないが、**builder-agent は 3 コンポーネント中テスト構造が最も弱い**(kaizen-loop は 26 ファイル、verifier は eval コーパス + 3 ファイル)。provider fallback や failure classification(#76)のような分岐の多いロジックこそ回帰が怖い場所なので、Phase B で builder のプロバイダ抽象を verifier に横展開する前に固めておきたい。

### 5.7 ドキュメントの置き場所と参照系譜の整理(小)

評価レポート・プレイブックの正本がローカル ghq ルート(バージョン管理外)にあり、`.github/docs/` に同期コピーが存在する二重構造になっている。さらに `.github/docs/org-design-improvement-notes-2026-07-05.ja.md` 内の `../../IMPROVEMENT-PLAYBOOK.ja.md` 等へのリンクはリポジトリ外を指しており **GitHub 上では切れている**。正本を `.github/docs/` 側に一本化し(ローカル側をコピーにする)、リンクをリポジトリ内相対パスに直すことを推奨。また、プレイブックの進捗ログが 07-04 の初回エントリのまま更新されておらず、「チェックリストとして消化する」という自らの運用契約が守られていない — A-3/A-4 完了時点でチェックとログを付けるべきだった。

## 6. 結論

- **設計は引き続き A**。責務分離、eval-first、契約化された sync、証拠強度の階層化と、外部ハーネス化のゴールに向けて一貫した判断が積み上がっている。
- **運用の証明は B+ に上昇**。WIP 制限と sandbox smoke という「2 回連続で最優先指摘だった 2 項目」が 1 日で解消されたのは大きい。ただし §5.1 の fleet hygiene 再劣化が示すとおり、**「人が頑張って掃除した状態」は数時間しか持たない**。仕組み化(worktree 隔離)まで行って初めて A に上がる。
- 直近の推奨着手順(コスト昇順):
  1. **§5.2** — design-decisions.md に conversation resolution の運用方針を追記(実装ゼロ、A-2 完了)
  2. **§5.1 即時分** — 漂流コミット `066c2ab` の PR 化 or 破棄判断、3 リポジトリの main 同期
  3. **§5.5** — 週次メトリクス PR の自動化(#158、Phase A 完了条件の最後の 1 つ)
  4. **§5.3** — #86 のログを golden ケース化 → verifier Step 3(LLM Claim 抽出、#82)着手
  5. **§5.1 恒久分** — worktree 運用への移行(#87/#88/#104 の優先度引き上げ)

Phase A はほぼ出口に到達した。**Phase B の着手条件(コーパス + CI ゲート + 誤検知の実データ)はすべて揃った**というのが本評価の最重要の結論である。

## 7. 追跡 issue(2026-07-05 起票)

本レポートの提案のうち未追跡だったものを issue 化した:

| 提案 | issue | 内容 |
| --- | --- | --- |
| §5.2 | [.github#106](https://github.com/kaizen-agents-org/.github/issues/106) | conversation-resolution 運用方針を design-decisions.md に文書化(A-2 完了) |
| §5.7 | [.github#107](https://github.com/kaizen-agents-org/.github/issues/107) | 評価/プレイブック文書の正本を .github に一本化・リンク切れ修正 |
| §5.4 | [.github#108](https://github.com/kaizen-agents-org/.github/issues/108) | roadmap ラベル分離 + stale な kaizen:in-progress の照合 |
| §5.1 即時 | [kaizen-loop#175](https://github.com/kaizen-agents-org/kaizen-loop/issues/175) | 漂流コミット 066c2ab の PR 化 or 破棄判断 |
| §5.3 | [verifier#88](https://github.com/kaizen-agents-org/verifier/issues/88) | #86 の実ログを golden ケース化(修正前に赤で固定) |
| §5.3 小 | [verifier#89](https://github.com/kaizen-agents-org/verifier/issues/89) | sb-009 プレフィックス重複のリネーム |

既存 issue で追跡済みのため新規起票しなかったもの: メトリクス永続化(kaizen-loop#158)、worktree 運用(kaizen-loop#87/#88、.github#104)、verifier LLM 化 Step 3(verifier#82)、builder-agent テスト分割(builder-agent#75/#76)。
