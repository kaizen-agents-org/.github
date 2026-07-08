# Kaizen Agents 改善プレイブック(実施手引き)

作成: 2026-07-04
使い方: **このファイルをチェックリストとして上から順に消化する。** 各タスクに「完了判定」があるので、判定を満たしたらチェックを付け、`進捗ログ` 節に日付と一言を追記する。週次 readiness レビュー(月曜)の前に必ず本ファイルの進捗を更新する。

関連ドキュメント:

- 評価レポート(現状の根拠): [evaluation-2026-07-04.ja.md](./evaluation-2026-07-04.ja.md)
- 戦略レポート(なぜこの順番か): [improvement-report-2026-07-03.ja.md](./improvement-report-2026-07-03.ja.md)
- verifier 実装計画: [verifier-strategy-2026-07-03.ja.md](./verifier-strategy-2026-07-03.ja.md)
- 最終目的の確認: dogfooding は手段、**外部プロダクトへのハーネス運用がゴール**(2026-07-03 オーナー確認)

---

## 運用ルール(常時適用)

- **WIP 制限**: 組織全体で生成 PR の open 件数が **5 件** を超えている間は、新しい issue への着手(`kaizen fix` / maintenance ジョブの新規実行)を行わない。まずレビュー・マージで排出する。
- **鮮度優先**: open PR が BEHIND になったら、新規作業より先に rebase する(放置すると builder のやり直しコストになる)。
- **凍結**: kaizen-loop への新コマンド追加は Phase B 完了まで凍結(hardening は可)。自律マージ・Product Kaizen 層は着手しない。
- **完了の定義**: 「PR を開いた」は完了ではない。**マージされて main に載り、元 issue が閉じた**ときに完了。

---

## Phase A: 流れの回復と計測(目安 1〜2 週間)

### A-1. PR バックログをゼロにする ⬜

2026-07-04 の初回作成時点では 12 件(kaizen-loop 3 / builder-agent 5 / verifier 4)だったが、PR #95 マージ後の再確認では残りは builder-agent #72 の 1 件。以下を優先してレビュー・マージする:

1. ⬜ **builder-agent #72**(provider failure evidence)— 現在 `CLEAN`。契約(schema/docs)とテストが揃っているか確認してマージする。
2. ⬜ その他のリポジトリに新規生成 PR が増えていないか確認し、増えていたら WIP 制限(A-3)を優先する。

レビュー時の判断基準: 契約(schema/docs)とテストが揃っているか、diff が issue の意図の範囲内か。迷ったら `kaizen:needs-human` コメントを残して次へ(滞留させない)。

**完了判定**: 以下がすべて 0 件、対応する issue が閉じている。

```bash
for repo in .github kaizen-loop builder-agent verifier coderabbit renovate-config; do
  count="$(gh pr list -R "kaizen-agents-org/${repo}" --state open --json number --jq 'length')"
  printf '%s\t%s\n' "${repo}" "${count}"
done
```

### A-2. BLOCKED の根本原因を解消する ⬜

初回作成時点では builder-agent #72 #74、verifier #71 が checks 成功なのに `mergeStateStatus: BLOCKED` だった。2026-07-04 の再確認では #72 は `CLEAN`、#74 はマージ済みなので、まず A-1 で残 PR を処理し、BLOCKED が再発したら以下で原因を特定する。06-29 readiness でも同事象が指摘済みで、branch protection と自動生成 PR の相性問題の疑いが強い。

手順:

1. ⬜ 各リポジトリの protection 設定を確認: `gh api repos/kaizen-agents-org/<repo>/branches/main/protection | jq`
2. ⬜ BLOCKED の PR で何が未充足か特定(required reviews / required checks の名前不一致 / CODEOWNERS など)。
3. ⬜ 原因を修正し、`.github/docs/design-decisions.md` に「自動生成 PR と branch protection の運用方針」として記録する。

**完了判定**: checks が green の生成 PR が BLOCKED にならないことを新規 PR 1 件で確認。

### A-3. WIP 制限を仕組みにする ✅

評価レポート §4 の「作りすぎのムダ」対策。まず運用で、次に自動化で。

1. ⬜ 即時(運用): scout automation のカデンツを 1 日 3 回 → **1 日 1 回**に減らす(`$CODEX_HOME/automations` と `.github/automations/README.md` の両方を更新)。バックログがゼロになったら戻すか判断。
2. ✅ 自動化: kaizen-loop の issue 選択時に「対象リポジトリ+組織全体の open 生成 PR 数」を数え、上限(config で `wipLimit`、デフォルト 5)超過なら着手をスキップして理由をログに残す。scout プロンプトにも「open PR が上限超過のリポジトリには issue を作らない」を追記。
3. ✅ `kaizen status --metrics` に open PR 滞留日数(最古の生成 PR の経過日数)を追加し、週次レビューで監視する。

**完了判定**: 2026-07-05 v2 評価で `safety.wipLimit` デフォルト 5、組織全体の open 生成 PR 数による intake skip、`kaizen status --metrics` 反映を確認済み。WIP 超過スキップの実観測と scout カデンツ調整は継続監視。

### A-4. sandbox smoke を実運用で 1 回完走させる ✅

readiness レビュー 2 回連続の最優先指摘。issue: kaizen-loop #131。

1. ✅ `kaizen smoke` を sandbox 設定で実行(手順は kaizen-loop `docs/13-sandbox-smoke.md`)。
2. ✅ 生成された `~/.kaizen/**/smoke-runs/*.json` artifact を確認し、`.github/docs/production-readiness/` 配下(または次回 readiness ログ)に記録として引用する。
3. ⬜ 成功したらスケジューラに **週 1 の smoke ジョブ**を登録する。
4. ✅ issue #131 を artifact への参照つきで close。

**完了判定**: 2026-07-05 v2 評価で実運用レイアウトの smoke artifact と #131 close を確認済み。週次ジョブ登録は kaizen-loop#171 で継続追跡。

### A-5. メトリクスを GitHub に永続化する ⬜

#151(review-window status metrics、07-04 マージ済み)の集計をローカル限定にしない。

1. ⬜ North-star を定義してドキュメント化: **人手修正なしマージ率**(生成 PR のうち追加コミットなしでマージされた割合)。補助: time-to-merge / Issue→PR 成功率 / verifier block 率 / needs-human 率 / マージ後 revert 率 / **open PR 滞留日数(A-3)**。定義は `.github/docs/production-readiness/metrics.md` に追記。
2. ⬜ 週次で `kaizen status --metrics` の出力(全リポジトリ分)を `.github` の `docs/metrics/<ISO週>.md` へ PR で追記する仕組みを作る(daily-dogfood-sync と同じパターンが流用できる)。
3. ⬜ 週次 readiness レビュー automation のプロンプトを「この集計を読む」よう更新し、「メトリクスが取れない」という定型指摘を廃止する。

**完了判定**: `docs/metrics/` に分母つきの週次集計が 1 件マージされ、次回 readiness レポートがそれを引用している。

### A-6. ローカル fleet の hygiene を回復する ⬜

全 checkout が `codex/*` ブランチ・dirty・最大 16 コミット behind。`_pr-work/` に残置 12 件。

1. ⬜ 各リポジトリで未コミット変更を確認し、必要なものは退避、不要なら破棄して `main` に戻し `git pull`。
2. ⬜ `_pr-work/` 配下 12 ディレクトリを確認し、マージ済み PR に対応するものは削除。
3. ⬜ `kaizen fleet --root .. --owner kaizen-agents-org --repo .github --repo builder-agent --repo kaizen-loop --repo verifier --repo coderabbit --repo renovate-config --prune --verify` を実行し、全 6 リポジトリの verify が通ることを確認(readiness の「fleet refresh 未証明」ギャップを閉じる)。
4. ⬜ 再発防止: sync/automation 完了時に checkout を main へ戻す(または作業を worktree に限定する)運用を automations プロンプトに明記。issue #87 #88(worktree 対応)がこの文脈なので優先度を上げる。

**完了判定**: 6 リポジトリすべて `main`・clean・up-to-date。fleet --verify 成功のログが readiness に記録できる。

### Phase A 出口条件

- 生成 PR バックログ 0 件、WIP 制限が稼働
- 実運用 smoke artifact ≥ 1、週次 smoke ジョブ登録済み
- 分母つき週次メトリクスが `.github` にマージされている
- BLOCKED 問題の原因が文書化・解消済み

---

## Phase B: ゲートの実体化と汎化検証(目安 〜2 ヶ月)

> 詳細設計は `verifier-strategy-2026-07-03.ja.md` に従う。ここでは実施順序と完了判定のみ。

### B-1. eval コーパスを 50+ ケースに拡充する(実装より先)⬜

- ⬜ 過去の生成 PR から golden ケース化(マージ成功例・修正が必要だった例の両方)。現在 7 ケース。
- ⬜ seeded バグを体系的に追加: off-by-one / テスト削除による偽 green / issue と無関係な diff / 危険な migration / 「rejected」等の語による誤検知ケース(builder-agent README 掲載の実例)。
- ⬜ **他言語スタックのログを必ず含める**: pytest / cargo / go test / gradle の失敗・成功ログ(外部ハーネスの前提検証)。
- ⬜ #66 の閾値ゲートを CI に組み込み、コーパス拡充が回帰を検出できる状態にする。

**完了判定**: 50+ ケース、うち非 Node スタック 10+、CI で eval が必須チェック化。

### B-2. LLM staged review を決定的ゲートの上に追加する ⬜

- ⬜ 決定的チェック(機械検証ログの失敗検出)は**残す**。LLM は intent-diff 整合 / テスト実効性 / リスク領域の意味判定を担う。
- ⬜ builder-agent の プロバイダ抽象(Codex/Claude/フォールバック)を verifier に横展開。
- ⬜ verdict に**根拠引用(該当 diff 行・ログ行)を必須化**し、PR 本文へ転記(#152 の拡張)。
- ⬜ B-1 のコーパスで regex 版と LLM 版の agreement / 誤 block 率を比較計測してから切り替える。

**完了判定**: eval agreement を維持したまま誤 block 率が regex 版より低いことを実測。verdict に根拠引用が付く。

### B-3. PR 本文を「5 分でレビューできる証拠パッケージ」にする ⬜

- ⬜ テンプレート必須項目: 元 issue / builder の task understanding / 変更ファイルと理由 / 実行した検証コマンドと結果 / verifier verdict と根拠引用 / 残存リスク。
- ⬜ 人手修正なしマージ率と time-to-merge(A-5)の改善で効果を確認する。

**完了判定**: テンプレートが契約化され、メトリクスで time-to-merge の短縮が確認できる。

### B-4. 「似ていないリポジトリ」でドッグフーディングを開始する ⬜

- ⬜ 別言語(Python or Rust or Go)の実リポジトリ、または意図的に雑然とした fixture リポジトリを 1 件選定。
- ⬜ Issue→PR を 1 件完走させ、崩れた前提(verifier のログパターン、builder のスタック仮定、コマンド前提)をすべて issue 化する。

**完了判定**: 非 Node リポジトリで Issue→PR→マージが 1 件完了し、発見された前提崩れが issue として記録されている。

### Phase B 出口条件

- verifier が意味判定+根拠引用を持ち、誤 block 率の低下が実測されている
- 人手修正なしマージ率が改善傾向(A-5 の週次メトリクスで確認)
- 非 Node リポジトリでの完走実績 1 件

---

## Phase C: 外部ハーネス(目安 〜四半期)

### C-1. GitHub Actions reusable workflow ⬜

- ⬜ `kaizen fix <issue>` がエフェメラル環境で動く workflow を提供(`issue labeled` → dispatch)。導入は `.kaizen/config.yml` + workflow 1 ファイルで完結させる。
- ⬜ ローカル scheduler / fleet は開発・dogfood 用として維持。`kaizen watch` は Actions 対応で不要になる可能性が高いので着手しない。

### C-2. 信頼境界の再設計(外部運用の前提)⬜

- ⬜ Issue 本文を untrusted input として扱う: builder プロンプトへは「参照データ」として明示的にラップし、指示と分離。
- ⬜ 実行権限ラベル(execution authorization)を外部運用でデフォルト必須化。
- ⬜ `safety.envAllowlist` / protected paths のデフォルトを外部リポジトリ基準で監査。
- ⬜ verifier の高リスク diff 検出(auth/secrets/billing/migration)を決定的チェックとして必ず残す。

### C-3. 外部プロダクト 1 件での実運用 ⬜

- ⬜ 導入ドキュメント(第三者メンテナ向け)整備。
- ⬜ 外部プロダクトで Issue→PR→マージの継続運用を開始し、North-star メトリクスが自組織と同水準であることを確認。

### Phase C 出口条件

- 組織外プロダクトで継続運用され、人手修正なしマージ率が自組織と同水準。

---

## やらないこと(再掲・変更なし)

- 自律マージ(human-out-of-the-loop)— マージ後修正率が十分低いと証明されるまで着手しない
- Product Kaizen(何を作るかの発見層)
- kaizen-loop への新コマンド追加(Phase B 完了まで)
- verifier の決定的チェックの廃止(LLM は追加であって置換ではない)

---

## 進捗ログ

| 日付 | 実施内容 | 備考 |
| --- | --- | --- |
| 2026-07-04 | プレイブック作成。評価レポート 2026-07-04 に基づく | バックログ 12 件、smoke 実績 0、コーパス 7 ケースからスタート |
| 2026-07-04 | A-1/A-2/A-6 を現況に更新 | open PR は builder-agent #72 の 1 件。完了判定コマンドを repo 別 count に修正し、fleet 対象を 6 リポジトリへ補正 |
| 2026-07-05 | 午後の再評価([evaluation-2026-07-05-v2.ja.md](./evaluation-2026-07-05-v2.ja.md))。A-3(WIP 制限)実装完了・A-4(smoke)達成(kaizen-loop#131 close)を確認。A-2 の BLOCKED 根本原因を特定: `required_conversation_resolution` + bot 未解決スレッド(文書化は .github#106)。A-5(メトリクス永続化)が Phase A 最後の未達項目(kaizen-loop#158)。実プロダクト投入プランを [product-adoption-plan-2026-07-05.ja.md](./product-adoption-plan-2026-07-05.ja.md) として策定 | fleet hygiene が同期後数時間で再劣化 — worktree 運用(kaizen-loop#87/#88、.github#104)の優先度引き上げを提案。verifier 誤検知が実運用で発生(verifier#86)、Phase B 着手条件が成立。追跡 issue: .github#106/#107/#108、kaizen-loop#175、verifier#88/#89 |
| 2026-07-06 | `.github/docs/` を評価レポート・プレイブックの正本として明記し、A-3/A-4 のチェック状態を 2026-07-05 v2 評価に合わせて更新 | 残る継続監視項目は scout カデンツ、WIP 超過スキップの実観測、週次 smoke ジョブ登録 |
| 2026-07-08 | 外部適用準備状況を評価([external-readiness-2026-07-08.ja.md](./external-readiness-2026-07-08.ja.md))。結論: 万全ではない(非 Node 実績ゼロ / コーパス 23 件 / C-1 未着手かつ追跡消失 / 信頼境界が文言止まり / A-5 週次メトリクス未完)。新規 issue: kaizen-loop#198(prompt 信頼境界)、.github#119(A-5 メトリクス)、.github#120(B-4 非 Node dogfood)、.github#121(umbrella: Phase C 追跡復活) | kaizen-loop#173/#174 close で消えた Phase C 追跡は .github#121 に一元化 |
| 2026-07-08 | Phase C を実行可能 issue 化: kaizen-loop#199(C-1 reusable workflow)、kaizen-loop#200(C-2 authorization ラベル必須化 + safety 監査)、verifier#97(B-1 コーパス 50+)、.github#122(C-3 導入ドキュメント — アウトラインを issue コメントに起案済み)、.github#123(C-3 外部実運用)。umbrella .github#121 に実施順序を記載 | 導入ガイドの骨子は .github#122 コメント参照。C-1 は kaizen-loop#198/#200 完了が前提 |
