#!/usr/bin/env bash
# fork-upstream-ref.sh — この fork で「upstream の版」とみなす git の参照を出力する（dev/fork-sync.md が正本）
#
# 使い方: dev/fork-upstream-ref.sh [リポジトリ]   （既定はカレントディレクトリ）
#   出力: 見つかった参照のコミット ID（40 桁）を 1 行に 1 つ。1 つも無ければ何も出さず exit 1
#
# 対象: refs/remotes/upstream/main（fork-sync.sh が足す remote）と refs/remotes/origin/main（fork の main = upstream のミラー）。
# **あるものをすべて出す**——片方だけ fetch して古いままのことがある（どちらか一方を選ぶと、古い方を選んだとき
# 取り込んだ upstream のコミットが upstream と認められない）。使う側は「どれかから到達できる」で判定する。
# 【使う側】selftest.sh の凍結記録の検査（T-FREEZE）が、upstream の取り込み（merge）で入った記録の変更を fork の違反と数えないために呼ぶ。
# このファイルは fork 固有で、upstream には無い。無ければ selftest.sh は従来どおりすべての変更を数える。
set -uo pipefail
d=${1:-.}
found=1
for r in refs/remotes/upstream/main refs/remotes/origin/main; do
  if c=$(git -C "$d" rev-parse -q --verify "$r^{commit}" 2>/dev/null); then echo "$c"; found=0; fi
done
exit "$found"
