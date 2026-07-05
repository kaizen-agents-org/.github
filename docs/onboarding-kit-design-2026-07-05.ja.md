# Onboarding Kit 設計書 — Kaizen Agents を改善対象リポジトリへ簡単に展開する仕組み(2026-07-05)

対象読者: この仕組みを実装するエージェント/人間、および導入判断をするオーナー。
位置づけ: [product-adoption-plan-2026-07-05.ja.md](./product-adoption-plan-2026-07-05.ja.md)(いつ・どの条件で載せるか)の姉妹編として、**どうやって載せるか**を設計する。Phase C-1(kaizen-loop#173)の詳細設計を含む。

---

## 1. 目的とゴール

**ゴール: 改善したいリポジトリのディレクトリで 1 コマンド叩けば導入が完了し、同じコマンドの再実行でいつでも最新に追従できること。** 所要 30 分以内、前提知識は「gh CLI が使える」程度とする。

測定可能な完了条件:

- 導入が対象リポジトリ内での **1 コマンド**(`onboard.sh`、内部の人間確認ポイントは 3 つまで — §7)で完了する
- **アップデートも同じコマンドの再実行**で完了する(冪等。§7.1)
- smoke artifact の生成をもって導入完了と機械判定できる(人間の目視チェックリスト不要)
- 導入されたリポジトリの設定が組織の安全最低線(§6.4)を満たすことを決定的スクリプトで検証できる

## 2. 非ゴール

- 自律マージの導入(組織方針どおり凍結継続)
- 信頼できない起票者からの issue 受付(kaizen-loop#160/#174 完了まで。[adoption plan §4-3](./product-adoption-plan-2026-07-05.ja.md))
- Product Kaizen(何を作るかの発見層)
- kaizen-loop への**新コマンド追加**(Phase B 完了まで凍結。本設計は既存コマンドの hardening と `.github` 側の資産追加のみで Stage 1 を実現する — §10)

## 3. 現状資産の棚卸し(再発明しないために)

展開機構の大部分は**既に存在する**。本設計の主作業は「点在する資産を 1 本の導入動線につなぐ」ことである。

| 資産 | 場所 | 展開機構での役割 |
| --- | --- | --- |
| `kaizen init` | kaizen-loop `src/init/` | config 雛形生成・スタック検出(現状 Node のみ)・ラベル作成・issue テンプレート・workspace/registry 登録 |
| `kaizen doctor` | kaizen-loop `src/commands/doctor.ts` | プリフライト(gh auth / ラベル / workspace / agent auth / builder・verifier 可用性 / builder runtime smoke)。`--repair` あり |
| `kaizen smoke` | kaizen-loop `src/commands/smoke.ts` | sandbox Issue→PR の完走テスト + artifact 保存(受け入れゲートにそのまま使える) |
| `.kaizen/config.yml` 契約 | kaizen-loop `src/config/schema.ts`、実例は `.github/dogfood-sync/targets/*/` | 導入の中心成果物。policy(pr-only / protectedPaths)・wipLimit・verify コマンド等 |
| dogfood-sync targets | `.github/.github/dogfood-sync/` | **プロファイル(設定プリセット)の原型**。契約チェックスクリプト + そのテストという運用パターンも流用可能 |
| shared skills sync | `.github/scripts/sync-kaizen-shared-skills.sh` | 対象リポジトリへのスキル配布の既存経路 |
| branch protection 運用方針 | .github#106(文書化予定) | 対象リポジトリへ適用すべき protection プリセットの根拠 |

## 4. 設計原則

1. **契約ファースト**: 導入とは「Onboarding Contract(§5)を満たすこと」であり、手順書の遂行ではない。契約充足は決定的スクリプトで検証する(「判定はコードで、発見は LLM で」の原則を導入プロセスにも適用)。
2. **プロファイルはデータ、ロジックはコマンド**: スタック別・リスク許容度別の差分は `onboarding/` 配下の宣言的プロファイルに置き、`kaizen init` はそれを読むだけにする。プロファイル追加にコード変更を不要にする。
3. **受け入れゲート = smoke artifact**: 「導入できたか」の判定は smoke の完走 artifact 1 点に集約する(kaizen-loop#169 で確立した永続化パターンを流用)。
4. **段階的に手離れさせる**: ローカル scheduler 型(今すぐ)→ GitHub Actions 型(Phase C-1)→ 公開テンプレート(Stage 3)。同じ契約の上にランタイムだけ差し替える。

## 5. 全体アーキテクチャ

中心概念は **Onboarding Contract** — 対象リポジトリが Kaizen 運用可能であるための状態定義:

```text
Onboarding Contract(対象リポジトリの状態)
├── .kaizen/config.yml            … スキーマ準拠 + 組織安全最低線を充足(§6.4)
├── .github/ISSUE_TEMPLATE/kaizen.yml
├── ラベル                        … kaizen / kaizen:P0-P2 / kaizen:pr-only / (Actions 型では kaizen:run)
├── branch protection             … required check + required_conversation_resolution(#106 準拠)
├── skills/ + skills-manifest.json … 同梱版 shared skills の vendor コピーと指紋(§6.8)
└── docs/smoke-runs/<ts>.json     … 受け入れゲート通過の証拠(1 件以上)
```

この契約の上に、2 つのランタイム形態を載せる:

```text
形態 A: Local Scheduler 型(Stage 1、今すぐ)          形態 B: GitHub Actions 型(Stage 2 = Phase C-1)
┌─────────────────────────────┐                       ┌─────────────────────────────┐
│ オーナーのマシン             │                       │ 対象リポジトリの Actions     │
│  kaizen scheduler(既存)     │                       │  kaizen-run.yml(caller 1 枚)│
│   └→ kaizen fix <issue>     │                       │   issue labeled kaizen:run   │
│       ├ builder-agent        │                       │   └→ reusable workflow 呼出  │
│       ├ 機械検証(config)    │                       │      (kaizen-loop 側で管理)  │
│       └ verifier             │                       │       └→ kaizen fix <issue>  │
└─────────────────────────────┘                       └─────────────────────────────┘
        └──────────── どちらも同じ Onboarding Contract / 同じ PR 品質ゲートに合流 ────────────┘
```

形態 A は既に dogfood で稼働している構成そのものであり、Stage 1 の実装対象は「導入動線」だけである。

## 6. コンポーネント設計

### 6.1 Onboarding Profiles(`onboarding/profiles/`)

dogfood-sync targets と同じ「宣言的な設定プリセット + 契約チェック」パターンを一般化する。

```text
onboarding/                     # kaizen-agents-org/.github リポジトリ直下
├── profiles/
│   ├── pilot-node.yml      # Node/TS 向けパイロット(wipLimit: 2、verify は npm test 系)
│   ├── pilot-python.yml    # pytest / ruff ベース
│   ├── pilot-go.yml        # go test / go vet ベース
│   ├── pilot-rust.yml      # cargo test / clippy ベース
│   └── standard.yml        # パイロット卒業後(wipLimit: 5)
├── versions.json           # 3 コンポーネントの互換バージョン組(§6.6)
└── README.md               # プロファイルの選び方
```

プロファイルは `.kaizen/config.yml` の**部分オーバーレイ**(デフォルト config に対する差分)とする。パイロット系プロファイルの共通差分:

- `safety.wipLimit: 2`(レビュー帯域に合わせ低く。adoption plan §4-4)
- `policy.mode: pr-only`、`directCommit: 0/0`(固定)
- `run.maxIssuesPerNight: 1`(初期流量を絞る)
- `policy.protectedPaths` に組織最低線(§6.4)を必ず含む

### 6.2 `kaizen init` の拡張(hardening、新コマンドなし)

既存 `init` に 2 点を足す:

1. **`--profile <name|path|URL>`**: プロファイルを読み込んで config 雛形にオーバーレイする。ネットワーク非依存にするため、既定は kaizen-loop 同梱コピー(shared-skill-sync と同様に `.github` を source of truth として同期)。
2. **スタック検出の多言語化**(`src/init/detect.ts`): 現状 `package.json` のみ → `pyproject.toml` / `go.mod` / `Cargo.toml` / `Gemfile` を追加し、profile 未指定時の verify コマンド推定に使う。verifier#70(default workspace verification commands の推定)と同じ検出テーブルを共有すること。**検出は提案までとし、確定は人間が config を確認してコミットする**(検証コマンドは信頼の根幹なので自動確定しない)。

### 6.3 Branch protection プリセット(`onboarding/scripts/apply-branch-protection.sh`)

#106 で文書化する組織標準(required status check + `required_conversation_resolution: true` + `enforce_admins`)を `gh api` の PUT 1 回で適用する冪等スクリプト。required check 名は config の verify に対応する CI job 名を引数で受ける。既存の sync スクリプト群と同様に**テストスクリプトを併設**する。

`kaizen init` からは実行しない(対象リポジトリの管理権限に踏み込む操作は明示的な別ステップに分離する)。

### 6.4 Onboarding contract check(`onboarding/scripts/check-onboarding-contract.sh`)

`check-daily-dogfood-sync-contract.sh` の一般化。対象リポジトリに対して決定的に検証する:

- `.kaizen/config.yml` がスキーマ準拠(`kaizen doctor` の config チェックを再利用)
- **組織安全最低線**: `policy.mode == pr-only`、`wipLimit <= 5`、`verifier.enabled == true`、`protectedPaths` が最低集合(`.github/**`, `**/.env*`, `**/secrets/**`, `**/*migration*/**`, `.kaizen/**`)を包含、`forbiddenPaths` に `**/.git/**`
- ラベル・issue テンプレート・branch protection の存在
- smoke artifact の存在(導入完了判定)

このスクリプトが Stage 2 では reusable workflow の**実行前ガード**にもなる(契約を満たさないリポジトリでは `kaizen fix` を起動しない)。

### 6.5 受け入れゲート: `kaizen doctor` → `kaizen smoke`

新規実装なし。導入手順の最後を「`doctor --repair` が全 green → `smoke --yes` が artifact を生成」に固定し、artifact を対象リポジトリの `docs/smoke-runs/` にコミットする(kaizen-loop#169 のパターン)。週次 smoke ジョブ(kaizen-loop#171)はプロファイルの scheduler 節に既定で含める。

### 6.6 バージョン配布(Stage 1 の主要な未整備点)

3 コンポーネント(kaizen-loop / builder-agent / verifier)は npm 未公開で、現状の導入手段はローカル checkout 前提である。設計:

1. **各リポジトリにリリースタグ(`v0.x`)を導入**し、互換の取れた組を `onboarding/versions.json` に記録する(`{"kaizen-loop": "v0.9.0", "builder-agent": "v0.7.2", "verifier": "v0.5.1"}`)。
2. Stage 1 のインストールは `npm install -g "github:kaizen-agents-org/<repo>#<tag>"` を versions.json に従って行う 1 スクリプト(`install-kaizen.sh`)に包む。
3. Stage 2 以降で npm 公開(または GHCR コンテナイメージ)に移行する。**インストール手段は versions.json の後ろに隠蔽されているので、移行しても導入手順は変わらない。**

### 6.7 GitHub Actions reusable workflow(Stage 2 = Phase C-1、kaizen-loop#173 の詳細化)

- **対象リポジトリ側は caller 1 枚**(`.github/workflows/kaizen-run.yml`): `issues: labeled` で `kaizen:run` ラベルを検知し、reusable workflow を呼ぶ。導入物は「config + caller workflow 1 ファイル」で C-1 の要求どおり。
- **reusable workflow は kaizen-loop リポジトリで管理**(`kaizen-agents-org/kaizen-loop/.github/workflows/kaizen-fix-reusable.yml@v0.x`): versions.json の組をセットアップ → contract check(§6.4)→ `kaizen fix <issue>` → PR 作成。エフェメラル環境なのでローカル registry/workspace は使わず、`kaizen fix` の workspace を runner 内に閉じる。
- **権限**: `permissions: contents: write, pull-requests: write, issues: write` を caller で最小宣言。クロスリポジトリ不要(自リポジトリ完結)なので GitHub App 導入は必須ではないが、`GITHUB_TOKEN` の PR には CI がトリガーされない制約があるため、**fine-grained PAT または App トークンを secret で受ける口を最初から設ける**(dogfood-sync の `KAIZEN_SYNC_TOKEN` と同じパターン)。
- **起動条件**: `kaizen:run` ラベルは書き込み権限者しか付与できないため、これ自体が execution authorization(#174)の実装になる。ラベル付与者の権限チェックを workflow 冒頭で再検証する(ラベルは剥がし忘れが起きるため、実行後に自動で剥がす)。

### 6.8 Shared skills の展開 — push 型から pull 型への反転

org 内リポジトリへの skills 配布は「`.github/skills/` 正本 → sync workflow が PR を送る push 型」だが、外部リポジトリには権限的にも作法的にも使えない。**pull 型に反転する**:

1. **初回配布**: `kaizen init` が、インストール済みツールチェーンに同梱された shared skills(builder-agent は既に `package.json` の `files` に `skills` を含む)を対象リポジトリの `skills/` に vendor し、各ファイルのハッシュを `skills/skills-manifest.json` に記録する。
2. **更新**: skills のバージョンはツールチェーンのリリースタグに乗せる。**versions.json のバンプ = skills の更新**であり、オーナーは `install-kaizen.sh` 再実行 → `kaizen doctor --repair` で追従する(`--repair` に「manifest 不一致の skill を同梱版から再 vendor」を追加 — 既存コマンドの hardening)。
3. **ドリフト検出**: contract check(§6.4)が manifest と実ファイルの一致、および manifest とインストール済みツールチェーン同梱版の一致を検証する。org 内で稼働中の skill drift 監視(builder-agent#83)と同じ考え方の一般化。

### 6.9 Automations の展開 — 3 層で扱いを分ける

`.github/automations/` の自動化は役割ごとに展開方針が異なる。「簡単に導入」の実現手段は**コピーではなく、テンプレート化(scout)と登録制(monitor/readiness)**である。

| 層 | 展開方針 | 仕組み |
| --- | --- | --- |
| コアループ(issue→PR) | **init で展開済み** | `scheduler.jobs` は config の一部でありプロファイルに同梱。追加作業なし |
| scout(issue 生成側) | **初期は無効、opt-in** | 下記 (a) |
| monitor / readiness-review | **展開しない。登録制で「見る側」に加える** | 下記 (b) |

**(a) scout の opt-in 展開**: 現行プロンプトは org 固有記述がハードコードのため、`onboarding/automations/scout.prompt.template.md` としてパラメータ化(repo / ラベル / WIP 上限 / 起票上限)し、`enable-scout.sh --repo <owner/repo>` がレンダリングして実行環境(Stage 1: オーナーの automation runner、Stage 2: 対象リポジトリの scheduled workflow)に登録する。**有効化の前提条件**をスクリプトが検証する: 週次メトリクスが存在し、直近の消化が安定していること(組織設計メモ §2.1「生成側だけ増やさない」の原則をコードで強制)。

**(b) fleet registry(登録制)**: `onboarding/fleet.json` に監視対象リポジトリを列挙し、org 側の monitor / weekly-readiness プロンプトはこのリストを読んで巡回する。**対象リポジトリの追加 = fleet.json への 1 行 PR** であり、automation のコピーは発生しない。週次メトリクス永続化(kaizen-loop#158)がこのリストを分母に艦隊全体を集計する構造にすると、readiness レビューが org 内外を一望できる。

## 7. 導入フロー(メンテナ視点の UX)— 対象リポジトリで 1 コマンド

```bash
cd my-product
curl -fsSL https://raw.githubusercontent.com/kaizen-agents-org/.github/main/onboarding/onboard.sh | sh
```

`onboard.sh` は §6 のコンポーネントを 1 本の冪等な動線に束ねるオーケストレータである。対象リポジトリ内には何も前提としない: 依存する兄弟スクリプト(`install-kaizen.sh` / `apply-branch-protection.sh` / `check-onboarding-contract.sh`)と versions.json は、自身と同じ base URL(`kaizen-agents-org/.github` の `onboarding/` 配下)から同一 ref で取得する。内部では次を順に行う:

```text
onboard.sh(冪等 — 既に済んでいるステップは検知してスキップ)
1. ツールチェーン install/update      … versions.json と突合、差分があれば更新(§6.6)
2. スタック検出 → プロファイル提案    … [確認 1] プロファイルと verify コマンドの承認
3. kaizen init --profile <選択>       … config + ラベル + issue テンプレート + skills vendor(§6.8)
4. branch protection 適用             … [確認 2] 管理権限操作の承認(§6.3)
5. kaizen doctor --repair             … プリフライト(認証・コマンド可用性)
6. kaizen smoke --yes                 … [確認 3] sandbox issue/PR 作成の承認 → artifact 生成
7. check-onboarding-contract.sh       … 契約充足の最終判定 → 「導入完了」を表示
```

人間の確認ポイントは 3 つに限定する(verify コマンド = 信頼の根幹、protection = 管理権限、smoke = 実 PR 作成)。それ以外は自動。CI 等の非対話環境向けに `--yes --profile <name>` で全確認をスキップできる。

以後は adoption plan §7 のとおり、低リスク issue を 2〜3 件流して週次メトリクスで流量を判断する。

### 7.1 アップデートの仕組み — 「導入コマンドの再実行 = アップデート」

kaizen-agents-org 側は常に改修が入る前提なので、追従を専用手順にせず**同じ `onboard.sh` の再実行に一本化**する。冪等設計により再実行時は実質こう動く:

1. **ツールチェーン更新**: インストール済みバージョンと最新 versions.json を突合し、差分のあるコンポーネントだけ更新(互換の取れた組でしか配布されないので、部分更新による組み合わせ破綻がない — §6.6)
2. **skills 再 vendor**: skills-manifest.json の指紋差分だけ更新(§6.8)
3. **config マイグレーション**: スキーマが進化した場合、`kaizen doctor` が旧 config を検出して警告し、可能なものは `--repair` で自動移行、判断が要るものは差分を提示して確認を求める(**ユーザーがカスタマイズした値は上書きしない** — プロファイル由来のデフォルトとユーザー変更を区別するため、init が生成時に `# kaizen-default` コメントでマーキングする)
4. **契約再検証**: contract check で更新後も安全最低線を満たすことを確認

**更新の気づき**: プロファイルの scheduler 節に週 1 の self-update check ジョブを既定で含め、upstream の versions.json に新しい互換組が出たら対象リポジトリに通知 issue を 1 件立てる(自動更新はしない — 更新の実行は常にオーナーの 1 コマンド)。同一バージョンに対する通知は 1 回のみ(重複起票ガード)。

## 8. セキュリティ / 信頼境界

- **Stage 1〜2 共通**: issue 起票は書き込み権限者(= 信頼済み)に限定。`kaizen:run` ラベル権限がそのまま実行認可になる。
- **外部起票者の受け入れは本キットのスコープ外**: kaizen-loop#160(untrusted input のデータブロック化)と #174(safety デフォルト監査)の完了が前提。contract check に「#160 完了前は外部公開リポジトリで `issues.label` 自動監視を有効化しない」ガードを入れる。
- プロファイルの `protectedPaths` 最低集合は**オーバーレイで削れない**(check スクリプトが包含を検証する)ことで、導入者の設定ミスによる安全線の低下を防ぐ。

## 9. 段階ロードマップと既存 issue マッピング

| Stage | 内容 | 依存 / 対応 issue | 目安 |
| --- | --- | --- | --- |
| 1 | Local Scheduler 型の導入動線: profiles + init 拡張 + protection スクリプト + contract check + versions.json | 新規 issue 起票が必要(下記)。#106(protection 文書)と整合 | 〜2 週間(adoption plan のパイロット開始点と同期) |
| 2 | GitHub Actions 型: reusable workflow + caller テンプレート | kaizen-loop#173(C-1)、#174(実行認可)、リリースタグ導入 | Phase B 完了後 |
| 3 | 公開テンプレート化: `kaizen-template` リポジトリ(caller + config + README)を「Use this template」で配布、導入ドキュメント(第三者メンテナ向け) | Phase C-3 の導入ドキュメント整備と統合 | Phase C |

Stage 1 の実装 issue(この設計書のマージ後に起票する):

1. `.github`: `onboarding/` ディレクトリ新設 — profiles 4 種 + versions.json + README + scripts(`onboard.sh` オーケストレータ / `install-kaizen.sh` / `apply-branch-protection.sh` / `check-onboarding-contract.sh`)+ scout プロンプトテンプレート + `fleet.json` + テスト(→ .github#112)
2. kaizen-loop: `init --profile` オーバーレイ対応 + skills vendor(init 時)と `doctor --repair` での再 vendor(いずれも hardening)(→ kaizen-loop#178)
3. kaizen-loop: `init/detect.ts` の多言語化(verifier#70 と検出テーブルを共有)(→ kaizen-loop#179)
4. 各リポジトリ: リリースタグ `v0.x` の導入と tagging 手順の文書化(→ .github#113)

## 10. Phase B 凍結との整合

プレイブックの凍結ルール「kaizen-loop への新コマンド追加は Phase B 完了まで凍結(hardening は可)」に対し、本設計の Stage 1 は:

- 新コマンド: **なし**(`init` / `doctor` / `smoke` は既存)
- kaizen-loop の変更は `init` のオプション追加と detect 拡張のみ(hardening の範囲)
- 新規資産はすべて `.github` 側(プロファイル・スクリプト)に置く

Stage 2(reusable workflow)は Phase C-1 そのものであり、Phase B 出口条件(verifier 意味判定 + 非 Node 完走実績)を待ってから着手する。

## 11. 完了判定

- **Stage 1**: 組織外の(または非 Node の)リポジトリ 1 件が §7 の 1 コマンドだけで導入完了し、smoke artifact と contract check green が揃う。所要時間 30 分以内。さらに、その後の versions.json バンプ 1 回に対して**同じコマンドの再実行だけで**追従できる(§7.1)ことを 1 回実証する。
- **Stage 2**: 同じリポジトリで `kaizen:run` ラベル付与から人手ゼロで ready-for-review PR が返る。
- **Stage 3**: 第三者メンテナがドキュメントのみで導入に成功する(サポートなし)。

## 12. 未解決の設計論点

1. **builder/verifier の LLM プロバイダ認証**: Actions 型では `ANTHROPIC_API_KEY` / Codex 認証を対象リポジトリの secret として要求することになる。コスト帰属(誰の API 予算で走るか)の方針が未定 — Stage 2 着手時にオーナー判断が必要。
2. **npm 公開のタイミング**: `github:` インストールはビルド時間と Node バージョン差異のリスクがある。Stage 1 の実測で問題が出たら公開を前倒す。
3. **プロファイルの同期方式**: kaizen-loop 同梱コピーと `.github` 正本のドリフト検出を shared-skill-sync に相乗りさせるか、独立ジョブにするか。
4. **config マイグレーションの堅牢性**: `# kaizen-default` マーキング(§7.1)は YAML の再整形で消えうる。ユーザーカスタマイズの検出を「プロファイル適用結果とのハッシュ比較」に置き換えるか、config を「生成層(profile 由来)+ オーバーライド層(ユーザー)」の 2 ファイルに分離するか — Stage 1 実装時に決める。
