#!/usr/bin/env bash
# fork-sync-test.sh — dev/fork-sync.sh をローカルのフィクスチャ（upstream / origin を模した repo）で検査する
# exit 0 = 全件通過。ネットワークに触れない。
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
F="$HERE/fork-sync.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fork-sync-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  ✅ $1"; }
ng()  { echo "  ❌ $1"; fail=1; }
expect_rc() { local want=$1 got=$2 msg=$3; [ "$got" -eq "$want" ] && ok "$msg (rc=$got)" || ng "$msg (want rc=$want, got rc=$got)"; }

g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
g init -q "$T/up" && g -C "$T/up" commit -q --allow-empty -m a
g clone -q --bare "$T/up" "$T/origin.git" && g -C "$T/origin.git" branch fork/custom main
g clone -q "$T/origin.git" "$T/work"
export UPSTREAM_URL="$T/up" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cd "$T/work"

"$F" check >/dev/null 2>&1; expect_rc 0 $? "同期済みなら check は 0"

g -C "$T/up" commit -q --allow-empty -m b
g checkout -q -b c origin/fork/custom && echo x > x && g add x && g commit -qm custom && g push -q origin c:fork/custom
"$F" check >/dev/null 2>&1; expect_rc 10 $? "upstream に新コミットがあれば check は 10"

out=$("$F" sync --push 2>&1); expect_rc 0 $? "sync --push が成功する"
br=$(printf '%s\n' "$out" | sed -n 's/^SYNC_BRANCH=//p')
[ "$(g -C "$T/origin.git" rev-parse main)" = "$(g -C "$T/up" rev-parse main)" ] && ok "origin/main が upstream と同じ SHA に fast-forward された" || ng "origin/main が upstream と一致しない"
g -C "$T/origin.git" merge-base --is-ancestor main "$br" && g -C "$T/origin.git" merge-base --is-ancestor fork/custom "$br" \
  && ok "sync ブランチ $br が upstream と fork/custom の両方を含む" || ng "sync ブランチが両方を含まない"
[ "$(g worktree list | wc -l)" -eq 1 ] && ok "一時 worktree が残らない" || ng "一時 worktree が残っている"

# 既存の sync ブランチ（PR 上のレビュー修正コミット）を上書きしない
g fetch -q origin && g checkout -q -b fix "origin/$br" && echo fix > fix && g add fix && g commit -qm reviewer-fix && g push -q origin "fix:$br"
fixsha=$(g rev-parse HEAD)
out=$("$F" sync --push 2>&1); expect_rc 0 $? "sync ブランチが既にあれば再実行は成功する"
[ "$(g -C "$T/origin.git" rev-parse "$br")" = "$fixsha" ] && ok "既存 sync ブランチのコミットを上書きしない" || ng "既存 sync ブランチが上書きされた"
printf '%s\n' "$out" | grep -q "^SYNC_BRANCH=$br$" && ok "既存 sync ブランチでも SYNC_BRANCH を出力する（PR 作成のため）" || ng "SYNC_BRANCH が出力されない"

g -C "$T/origin.git" update-ref refs/heads/fork/custom "$br"   # PR マージ相当
"$F" check >/dev/null 2>&1; expect_rc 0 $? "取り込み後は check が 0 に戻る"
out=$("$F" sync --push 2>&1); expect_rc 0 $? "取り込み済みでの sync --push は成功する"
printf '%s\n' "$out" | grep -q '^SYNC_BRANCH=' && ng "何も無いのに SYNC_BRANCH を出力した" || ok "何も無いときは SYNC_BRANCH を出力しない（ワークフローの if が依存）"

# fork/custom を手で同期済みでも main が遅れていれば check は 10、sync --push で main だけ進む
g -C "$T/up" commit -q --allow-empty -m e
g -C "$T/origin.git" fetch -q "$T/up" main && g -C "$T/origin.git" update-ref refs/heads/fork/custom FETCH_HEAD
"$F" check >/dev/null 2>&1; expect_rc 10 $? "fork/custom 同期済みでも main が遅れていれば check は 10"
"$F" sync --push >/dev/null 2>&1; expect_rc 0 $? "その状態で sync --push が成功する"
[ "$(g -C "$T/origin.git" rev-parse main)" = "$(g -C "$T/up" rev-parse main)" ] && ok "main だけ fast-forward された" || ng "main が取り残された"

# 衝突しても main は fast-forward される（sync ブランチは作らない）
(cd "$T/up" && echo u > x && g add x && g commit -qm conflict)
g -C "$T/origin.git" update-ref refs/heads/fork/custom "$br"   # x を持つ独自ブランチへ戻す
"$F" sync --push >/dev/null 2>&1; expect_rc 3 $? "merge 衝突は 3 で止まる"
[ "$(g -C "$T/origin.git" rev-parse main)" = "$(g -C "$T/up" rev-parse main)" ] && ok "衝突時も main は fast-forward される" || ng "衝突時に main が進まない"
g -C "$T/origin.git" show-ref --quiet "refs/heads/sync/upstream-$(g -C "$T/up" rev-parse --short=7 main)" && ng "衝突時に sync ブランチを push した" || ok "衝突時は sync ブランチを push しない"
[ "$(g worktree list | wc -l)" -eq 1 ] && ok "衝突時も一時 worktree が残らない" || ng "衝突時に一時 worktree が残っている"

# main が独自コミットを持つとき（ミラー原則違反）は止まり、main を動かさない
g fetch -q origin && g checkout -q -b m origin/main && g commit -q --allow-empty -m own && g push -q -f origin m:main
own=$(g rev-parse HEAD)
"$F" check >/dev/null 2>&1; expect_rc 2 $? "main が独自コミットを持てば 2（ミラー原則違反）"
"$F" sync --push >/dev/null 2>&1; expect_rc 2 $? "その状態では sync --push も 2 で止まる"
[ "$(g -C "$T/origin.git" rev-parse main)" = "$own" ] && ok "その状態で main を動かさない" || ng "main が動かされた"

# upstream remote が別の repo を指していれば止まる
g remote set-url upstream "$T/origin.git"
"$F" check >/dev/null 2>&1; expect_rc 2 $? "upstream remote が期待と違う repo を指せば 2"

[ "$fail" -eq 0 ] && echo "fork-sync-test: PASS" || echo "fork-sync-test: FAIL"
exit "$fail"
