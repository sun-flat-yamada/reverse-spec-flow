# OpenAI Codex 実測記録

> **このファイルが `SUPPORT_LEVEL` の根拠である**（GP-107 ルール8）。
> **何も実測していない。** 配置は公式文書と解説を読んで決めた。そのため `SUPPORT_LEVEL=placed-unverified` を名乗る
> （未測定の項目を「問題なし」と読まない）。

| 項目 | 値 |
|---|---|
| ホスト | OpenAI Codex CLI（**IDE 拡張・クラウドは対象外**。測ったら別の面として扱う。GP-107 ルール2） |
| 版 | 未測定 |
| 実施日 | —（文書の確認: 2026-11-24） |

## 文書で読んだこと（実測ではない）

| # | 項目 | 文書の記述 | 出所 | 配置への反映 |
|---|---|---|---|---|
| D1 | skill の探索場所 | リポジトリでは作業ディレクトリからリポジトリのルートまでの各ディレクトリの `.agents/skills` を探す。`SKILL.md` には `name` と `description` が要る | OpenAI の Codex 文書「Build skills」（learn.chatgpt.com/docs/build-skills。developers.openai.com/codex/skills からの転送先） | `.agents/skills/` に置く。本体の `SKILL.md` は両方を持つ（selftest が検査） |
| D2 | `AGENTS.md` の読み方と上限 | ルート（と利用者の設定ディレクトリ）から作業ディレクトリまでの `AGENTS.md` を連結し、合計が `project_doc_max_bytes`（既定 32 KiB）で打ち切られる。超えた分は黙って切り詰められる | 第三者の解説（公式文書の該当箇所は未確認。上限に達した後のファイルが「切り詰められる」のか「足されない」のかも未確認） | `placement.sh` が連結の合計を数えて警告する。`setup.md` §2 |

## 測定項目

| # | 項目 | 回数 | 結果 | 判定 |
|---|---|---|---|---|
| 1 | 入口文書の読み込み（ルート / 入れ子） | 0 | — | `unknown` |
| 2 | skill の発動（`.agents/skills/`） | 0 | — | `unknown` |
| 3 | サブエージェント（起動手段・並列・同時数） | 0 | — | `unknown` |
| 4 | **検証官への生成物の流入**（GP-22 の隔離） | 0 | — | `unknown` |
| 5 | **検証官のツール権限**（読み取りを解析対象の配下に制限できるか） | 0 | — | `unknown` |
| 6 | ゲートの実行（タイムアウト・出力上限） | 0 | — | `unknown` |
| 7 | 上限を超えた `AGENTS.md` の切り詰め（D2 の確かめ） | 0 | — | `unknown` |

**測るときは** `hosts/kiro-cli/MEASURED.md` の測り方（一意のトークンを埋めたフィクスチャ）に倣い、版・日付・回数を残す。
