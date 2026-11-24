#!/bin/bash
# placement.sh — OpenAI Codex 向けの配置（GP-107 ルール1）
#
# ホスト固有パス（`.agents/`）と Codex の設定名を知ってよいのはこの層だけである。
# **何も実測していない**（MEASURED.md。SUPPORT_LEVEL=placed-unverified）。
set -euo pipefail

# --- 入口への導線 ---
# Codex はルートの AGENTS.md を読む（文書による）ので、ベンダ固有の入口ファイルは置かない。

# --- skill ---
# 【.agents/skills/ に置く】Agent Skills の標準の場所。Codex はリポジトリでは CWD からルートまでの
# 各ディレクトリの .agents/skills を探し、SKILL.md に name と description を要求する（文書による。MEASURED.md）。
if [ -d "$SKILLS_SRC" ]; then
  mkdir -p "$SPEC_REPO/.agents/skills"
  cp -R "$SKILLS_SRC/." "$SPEC_REPO/.agents/skills/"
  echo "  placed   : .agents/skills/（$(find "$SKILLS_SRC" -name 'SKILL.md' | wc -l | tr -d ' ') 件）"
fi

# --- 入口文書の大きさ ---
# Codex はルートから CWD までの AGENTS.md を連結し、合計が project_doc_max_bytes（既定 32 KiB）を超えると
# 黙って切り詰める（文書による。未実測）。ルートで開けばルートの AGENTS.md だけだが、spec-extraction/ で開くと
# spec-extraction/AGENTS.md も連結され、末尾（Off-limits など）が落ちうる。黙って落ちるので、ここで数えて知らせる。
_codex_limit=32768
# 【配置の時点の大きさ】init.sh は配置の後で解析対象パスなどを埋めるので、実際はここで数えた値より少し大きい（「約」と書く）。
# 【無いファイルで止まらない】set -e と pipefail のもとで cat が失敗すると、メッセージ無しで配置が止まる（apply-host.sh で実測）
_codex_sum=0
for _f in "$SPEC_REPO/AGENTS.md" "$WROOT/AGENTS.md"; do
  if [ -f "$_f" ]; then _codex_sum=$((_codex_sum + $(wc -c < "$_f"))); fi
done
if [ "$_codex_sum" -gt "$_codex_limit" ]; then
  echo "  WARN     : spec-extraction/ で Codex を開くと、AGENTS.md の連結が約 ${_codex_sum} バイトになり既定の上限 ${_codex_limit} を超える"
  echo "             （末尾が黙って落ちる）。リポジトリのルートで開く。spec-extraction/ で開くなら HOST-SETUP.md §2 の設定を入れる"
fi
