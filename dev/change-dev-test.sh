#!/usr/bin/env bash
# change-dev-test.sh — dev/change-dev.sh をフィクスチャ repo で検査する（ネットワーク不使用）。exit 0 = 全件通過
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/change-dev.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/change-dev-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "  ✅ $1"; }
ng() { echo "  ❌ $1"; fail=1; }
expect_rc() { [ "$2" -eq "$1" ] && ok "$3 (rc=$2)" || ng "$3 (want rc=$1, got rc=$2)"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CHG_DEV_AUTO_PILOT

git init -q -b fork/custom "$T/r" && cd "$T/r"
mkdir -p dev .github && cp "$SRC" dev/change-dev.sh
echo base > init.sh && git add . && git commit -qm base
F=dev/change-dev.sh
P=.devs/changes/2026-11-24_x/implementation_plan.md
plan() { mkdir -p "$(dirname "$P")" && echo plan >> "$P" && git add "$P" && git commit -qm plan; }
impl() { echo "$1" >> "${2:-init.sh}" && git add -A && git commit -qm impl; }
fresh() { git checkout -q -B "${1:-feat/x}" fork/custom; }

# --- mode ---
[ "$($F mode --value)" = false ] && ok "設定が無ければ Auto-Pilot は false" || ng "設定が無いのに true"
printf '# c\nCHG_DEV_AUTO_PILOT=true # note\n' > .github/change-dev.env
[ "$($F mode --value)" = true ] && ok ".github/change-dev.env の true を読む（行末コメント付き）" || ng ".github/change-dev.env を読めない"
echo 'export CHG_DEV_AUTO_PILOT="false"' > .env
[ "$($F mode --value)" = false ] && ok ".env が .github/change-dev.env より優先される（export・引用符付き）" || ng ".env が優先されない"
[ "$(CHG_DEV_AUTO_PILOT=1 $F mode --value)" = true ] && ok "環境変数が .env より優先される（1 は true）" || ng "環境変数が優先されない"
[ "$(CHG_DEV_AUTO_PILOT=yes $F mode --value)" = false ] && ok "true/1 以外は false（yes を有効と読まない）" || ng "yes を true と読んだ"
printf 'CHG_DEV_AUTO_PILOT=true\r\n' > .github/change-dev.env; rm .env
[ "$($F mode --value)" = true ] && ok "CRLF の設定ファイルでも読む" || ng "CRLF で読めない"
printf 'XCHG_DEV_AUTO_PILOT=true\n' > .github/change-dev.env
[ "$($F mode --value)" = false ] && ok "似た名前のキーを読まない" || ng "似た名前のキーを読んだ"
git checkout -q -- . 2>/dev/null; git clean -qfd .github .env 2>/dev/null

# --- plan-check ---
fresh; plan; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "計画コミット → 実装コミットは通過"

fresh; impl a; plan
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "実装が計画より先なら違反"

fresh; mkdir -p "$(dirname "$P")"; echo plan > "$P"; echo a >> init.sh; git add -A; git commit -qm both
out=$($F plan-check fork/custom 2>&1); expect_rc 1 $? "計画と実装が同じコミットなら違反"
printf '%s' "$out" | grep -q '同じコミット' && ok "同じコミットの違反を理由として示す" || ng "同じコミットの理由を示さない"

fresh; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "計画が無ければ違反"

fresh; mkdir -p .devs/changes/2026-11-24_x; echo t > .devs/changes/2026-11-24_x/task.md; git add -A; git commit -qm task; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "task.md だけでは計画と数えない"

fresh; mkdir -p .devs/changes/x; echo p > .devs/changes/x/implementation_plan.md; git add -A; git commit -qm badplan; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "日付の無い置き場所の計画は数えない"

fresh; mkdir -p docs; echo d > docs/a.md; git add -A; git commit -qm docs
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "docs/ だけの変更は免除"

fresh; echo d > pipeline.md; git add -A; git commit -qm md
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "docs/ 外の .md（本体の規約文書）は免除しない"

fresh sync/upstream-abc1234; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "sync/upstream-* は免除"
git checkout -q -b other; $F plan-check fork/custom sync/upstream-abc1234 >/dev/null 2>&1; expect_rc 0 $? "head ブランチ名を引数で渡せる（Actions の detached HEAD 用）"

fresh; Q=.devs/changes/2026-11-24_日本/implementation_plan.md; mkdir -p "$(dirname "$Q")"; echo p > "$Q"; git add -A; git commit -qm plan-ja; impl a
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "非 ASCII を含む置き場所の計画も数える"
fresh; mkdir -p docs; echo d > docs/日本.md; git add -A; git commit -qm docs-ja
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "非 ASCII 名の docs/ だけの変更も免除"

# マージ済み（base にある）計画を再利用して実装だけのコミットを通さない
fresh; plan; git checkout -q fork/custom; git merge -q --ff-only feat/x; git checkout -q -B feat/y fork/custom; impl b
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "base に既にある計画を追記しても新しい計画と数えない"
git checkout -q -B feat/z fork/custom; echo more >> "$P"; git add -A; git commit -qm replan; impl c
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "既存の計画ファイルを編集しただけのコミットも数えない"

# 同じブランチで前の PR が squash マージ済み → base を merge して次の計画と実装を積む（クラウドセッションの再利用）
fresh feat/reuse; plan; impl r1
git checkout -q fork/custom; git merge -q --squash feat/reuse >/dev/null; git commit -qm squashed; git checkout -q feat/reuse
git merge -q --no-edit fork/custom
P2=.devs/changes/2026-11-25_y/implementation_plan.md; mkdir -p "$(dirname "$P2")"; echo p2 > "$P2"; git add -A; git commit -qm plan2; impl r2
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "squash 済みの旧コミットが残るブランチでも、base 取り込み後の計画 → 実装は通過"
git checkout -q -B feat/reuse2 feat/reuse~2; impl r3   # base 取り込み後に計画なしで実装（plan2 を含まない）
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 1 $? "base 取り込み後に計画なしで実装すれば違反（旧 squash 済み計画では通さない）"
# 途中で base を merge しただけのブランチ（計画は merge より前）は通過
git checkout -q fork/custom; echo b >> base.txt; git add -A; git commit -qm base2
fresh feat/mid; P3=.devs/changes/2026-11-26_z/implementation_plan.md; mkdir -p "$(dirname "$P3")"; echo p3 > "$P3"; git add -A; git commit -qm plan3; impl m1
git checkout -q fork/custom; echo c >> base.txt; git add -A; git commit -qm base3; git checkout -q feat/mid; git merge -q --no-edit fork/custom; impl m2
$F plan-check fork/custom >/dev/null 2>&1; expect_rc 0 $? "途中で base を merge したブランチ（計画は merge 前）も通過"

fresh; $F plan-check no-such-base >/dev/null 2>&1; expect_rc 2 $? "base が無ければ 2"

[ "$fail" -eq 0 ] && echo "change-dev-test: PASS" || echo "change-dev-test: FAIL"
exit "$fail"
