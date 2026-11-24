# 実装計画: C2 Codex 向け harness（Agent Skills の標準配置）と入口文書の大きさの検査

改善候補レビュー（2026-11）の C2。`AGENTS.md` を読むホストのうち、まだ harness の無い OpenAI Codex に、
skill を Agent Skills の標準の場所（`.agents/skills/`）へ置く harness を足す。あわせて、起動時に読まれる入口文書の大きさを検査する。

## 事実（公式文書。実測ではない）
- Codex は、リポジトリでは CWD からリポジトリのルートまでの各ディレクトリの `.agents/skills` を探す。`SKILL.md` には `name` と `description` が要る
  （learn.chatgpt.com/docs/build-skills、2026-11-24 に確認）。本体の `skills/*/SKILL.md` は両方を持つ。
- Codex はルートから CWD までの `AGENTS.md` を連結して読み、合計が `project_doc_max_bytes`（既定 32 KiB）を超えると黙って切り詰める
  （第三者の解説による。公式文書では未確認）。
- 生成先のルート `AGENTS.md` は約 4.4 KB だが、`spec-extraction/AGENTS.md` は約 35 KB ある。`spec-extraction/` で起動すると
  合計が約 40 KB になり、末尾（Off-limits など）が落ちる。

## 方針
- `hosts/codex/` を `hosts/_template` から作る（GP-107 の手順。`hosts/` の外にホスト名を書かない）。
  - `placement.sh`: skill を `.agents/skills/` に置く。ベンダ固有の入口は置かない（ルートの `AGENTS.md` をそのまま読む）。
    起動時に連結されうる入口（ルート＋`spec-extraction/AGENTS.md`）の合計が 32 KiB を超えるなら警告を出す。
  - `setup.md` → `HOST-SETUP.md`: ルートで開くこと。`spec-extraction/` で開く場合は `project_doc_max_bytes` を上げること。
  - `entry.md` §5（検証官の隔離）: 読み取りを機械で制限する手段は**確立していない**と書き、GP-16 ルール8 の縮退を指す。
  - `profile.env`: 測っていない項目は `unknown`。`SUPPORT_LEVEL=placed-unverified`。`MEASURED.md` は「未測定」と書く。
- `hosts/README.md` の対応表に `codex` を `placed-unverified` で載せる。

## 検証（selftest に足す）
- `init.sh --host=codex` が成功し、skill が `.agents/skills/` に本体と同じ内容で置かれる。他ホストの配置物（`.claude/`・`.kiro/`）を置かない。
- PLACED_PATHS の突合と HOST.md＝entry.md の写しの検査に codex を加える。
- ホストに依らない検査: 生成先のルート `AGENTS.md` が 32 KiB 以下（いちばん厳しい既知の上限で、起動時に必ず読まれる入口が切れない）。
- Codex の HOST-SETUP.md が `project_doc_max_bytes` と `spec-extraction/` で開くときの注意を持つ。
- `./selftest.sh` が base より失敗を増やさない。別コンテキストの反証レビュー。
