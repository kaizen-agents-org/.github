# Onboarding Kit 設計書 — Kaizen Agents を改善対象リポジトリへ簡単に展開する仕組み(2026-07-05)

対象読者: この仕組みを実装するエージェント/人間、および導入判断をするオーナー。
位置づけ: [product-adoption-plan-2026-07-05.ja.md](./product-adoption-plan-2026-07-05.ja.md)(いつ・どの条件で載せるか)の姉妹編として、**どうやって載せるか**を設計する。Phase C-1(kaizen-loop#173)の詳細設計を含む。

---

## 1. 目的とゴール

**ゴール: 対象リポジトリのメンテナが、30 分以内・コマンド 4 つ以内で「Issue を立てたら検証済み PR が返ってくる」状態に到達できること。** 前提知識は「gh CLI が使える」程度とする。

測定可能な完了条件:

- 導入手順が「インストール → `kaizen init` → `kaizen doctor` → `kaizen smoke`」の 4 ステップに収まる
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
2. **プロファイルはデータ、ロジックはコマンド**: スタック別・リスク許容度別の差分は `.github/onboarding/` 配下の宣言的プロファイルに置き、`kaizen init` はそれを読むだけにする。プロファイル追加にコード変更を不要にする。
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

### 6.1 Onboarding Profiles(`.github/onboarding/profiles/`)

dogfood-sync targets と同じ「宣言的な設定プリセット + 契約チェック」パターンを一般化する。

```text
.github/onboarding/
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

### 6.3 Branch protection プリセット(`.github/onboarding/scripts/apply-branch-protection.sh`)

#106 で文書化する組織標準(required status check + `required_conversation_resolution: true` + `enforce_admins`)を `gh api` の PUT 1 回で適用する冪等スクリプト。required check 名は config の verify に対応する CI job 名を引数で受ける。既存の sync スクリプト群と同様に**テストスクリプトを併設**する。

`kaizen init` からは実行しない(対象リポジトリの管理権限に踏み込む操作は明示的な別ステップに分離する)。

### 6.4 Onboarding contract check(`.github/onboarding/scripts/check-onboarding-contract.sh`)

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

1. **各リポジトリにリリースタグ(`v0.x`)を導入**し、互換の取れた組を `.github/onboarding/versions.json` に記録する(`{"kaizen-loop": "v0.9.0", "builder-agent": "v0.7.2", "verifier": "v0.5.1"}`)。
2. Stage 1 のインストールは `npm install -g "github:kaizen-agents-org/<repo>#<tag>"` を versions.json に従って行う 1 スクリプト(`install-kaizen.sh`)に包む。
3. Stage 2 以降で npm 公開(または GHCR コンテナイメージ)に移行する。**インストール手段は versions.json の後ろに隠蔽されているので、移行しても導入手順は変わらない。**

### 6.7 GitHub Actions reusable workflow(Stage 2 = Phase C-1、kaizen-loop#173 の詳細化)

- **対象リポジトリ側は caller 1 枚**(`.github/workflows/kaizen-run.yml`): `issues: labeled` で `kaizen:run` ラベルを検知し、reusable workflow を呼ぶ。導入物は「config + caller workflow 1 ファイル」で C-1 の要求どおり。
- **reusable workflow は kaizen-loop リポジトリで管理**(`kaizen-agents-org/kaizen-loop/.github/workflows/kaizen-fix-reusable.yml@v0.x`): versions.json の組をセットアップ → contract check(§6.4)→ `kaizen fix <issue>` → PR 作成。エフェメラル環境なのでローカル registry/workspace は使わず、`kaizen fix` の workspace を runner 内に閉じる。
- **権限**: `permissions: contents: write, pull-requests: write, issues: write` を caller で最小宣言。クロスリポジトリ不要(自リポジトリ完結)なので GitHub App 導入は必須ではないが、`GITHUB_TOKEN` の PR には CI がトリガーされない制約があるため、**fine-grained PAT または App トークンを secret で受ける口を最初から設ける**(dogfood-sync の `KAIZEN_SYNC_TOKEN` と同じパターン)。
- **起動条件**: `kaizen:run` ラベルは書き込み権限者しか付与できないため、これ自体が execution authorization(#174)の実装になる。ラベル付与者の権限チェックを workflow 冒頭で再検証する(ラベルは剥がし忘れが起きるため、実行後に自動で剥がす)。

## 7. 導入フロー(メンテナ視点の UX)

```bash
# 0. インストール(versions.json の互換組を一括)
curl -fsSL https://raw.githubusercontent.com/kaizen-agents-org/.github/main/onboarding/scripts/install-kaizen.sh | sh

# 1. 対象リポジトリで初期化(config 雛形 + ラベル + issue テンプレート)
cd my-product && kaizen init --profile pilot-python
# → 生成された .kaizen/config.yml の verify コマンドを確認して commit(人間の確認ポイント)

# 2. branch protection を組織標準に(管理権限が必要な操作として分離)
bash onboarding/scripts/apply-branch-protection.sh --check-name test

# 3. プリフライト → 受け入れゲート
kaizen doctor --repair
kaizen smoke --yes          # artifact が docs/smoke-runs/ に生成されたら導入完了
```

以後は adoption plan §7 のとおり、低リスク issue を 2〜3 件流して週次メトリクスで流量を判断する。

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

1. `.github`: `onboarding/` ディレクトリ新設(profiles 4 種 + versions.json + README + scripts 2 本 + テスト)
2. kaizen-loop: `init --profile` オーバーレイ対応(hardening)
3. kaizen-loop: `init/detect.ts` の多言語化(verifier#70 と検出テーブルを共有)
4. 各リポジトリ: リリースタグ `v0.x` の導入と tagging 手順の文書化

## 10. Phase B 凍結との整合

プレイブックの凍結ルール「kaizen-loop への新コマンド追加は Phase B 完了まで凍結(hardening は可)」に対し、本設計の Stage 1 は:

- 新コマンド: **なし**(`init` / `doctor` / `smoke` は既存)
- kaizen-loop の変更は `init` のオプション追加と detect 拡張のみ(hardening の範囲)
- 新規資産はすべて `.github` 側(プロファイル・スクリプト)に置く

Stage 2(reusable workflow)は Phase C-1 そのものであり、Phase B 出口条件(verifier 意味判定 + 非 Node 完走実績)を待ってから着手する。

## 11. 完了判定

- **Stage 1**: 組織外の(または非 Node の)リポジトリ 1 件が §7 の 4 ステップだけで導入完了し、smoke artifact と contract check green が揃う。所要時間 30 分以内。
- **Stage 2**: 同じリポジトリで `kaizen:run` ラベル付与から人手ゼロで ready-for-review PR が返る。
- **Stage 3**: 第三者メンテナがドキュメントのみで導入に成功する(サポートなし)。

## 12. 未解決の設計論点

1. **builder/verifier の LLM プロバイダ認証**: Actions 型では `ANTHROPIC_API_KEY` / Codex 認証を対象リポジトリの secret として要求することになる。コスト帰属(誰の API 予算で走るか)の方針が未定 — Stage 2 着手時にオーナー判断が必要。
2. **npm 公開のタイミング**: `github:` インストールはビルド時間と Node バージョン差異のリスクがある。Stage 1 の実測で問題が出たら公開を前倒す。
3. **プロファイルの同期方式**: kaizen-loop 同梱コピーと `.github` 正本のドリフト検出を shared-skill-sync に相乗りさせるか、独立ジョブにするか。
