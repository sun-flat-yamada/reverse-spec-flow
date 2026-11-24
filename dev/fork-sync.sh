#!/usr/bin/env bash
# fork-sync.sh — upstream（aws-samples/sample-reverse-spec-flow）の更新を fork へ取り込む
#
# ブランチ構成（dev/fork-sync.md が正本）:
#   main         upstream/main のミラー。fast-forward 以外で動かさない（独自コミットを置かない）
#   fork/custom  fork 独自の変更。既定ブランチ。Claude の PR はここへ向ける
#
# 使い方:
#   dev/fork-sync.sh check            状態を報告するだけ（何も変更しない）。exit 0=同期済み / 10=取り込み待ちあり
#   dev/fork-sync.sh sync [--push]    (1) main を upstream/main へ fast-forward する（--push 時。fork/custom と独立）
#                                     (2) fork/custom が未取り込みなら sync/upstream-<upstreamの短縮ハッシュ> を
#                                         fork/custom から切って upstream を merge する。origin に同名があれば作り直さない
#                                     --push で origin へ送る（force しない。PR 作成は呼び出し側）
#
# 終了コード: 0=成功/同期済み 10=取り込み待ちあり(check) 2=前提違反（main が独自コミットを持つ・remote 不足など）
#             3=merge 衝突（sync ブランチは作らない。手で解消する）
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/aws-samples/sample-reverse-spec-flow}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
MIRROR_BRANCH="${MIRROR_BRANCH:-main}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-fork/custom}"

die() { echo "ERROR: $*" >&2; exit "${2:-2}"; }
info() { echo "[fork-sync] $*"; }

git rev-parse --git-dir >/dev/null 2>&1 || die "git リポジトリ内で実行してください"

ensure_remotes() {
  local cur
  if ! cur=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null); then
    info "remote '$UPSTREAM_REMOTE' を追加: $UPSTREAM_URL"
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  elif [ "${cur%.git}" != "${UPSTREAM_URL%.git}" ]; then
    # 別の repo を指す upstream をそのまま main へミラーしない
    die "remote '$UPSTREAM_REMOTE' が $cur を指しています（期待: $UPSTREAM_URL。違う repo なら UPSTREAM_URL で指定する）"
  fi
  git remote get-url "$ORIGIN_REMOTE" >/dev/null 2>&1 || die "remote '$ORIGIN_REMOTE' がありません"
  git fetch --quiet "$UPSTREAM_REMOTE" "$MIRROR_BRANCH"
  git fetch --quiet "$ORIGIN_REMOTE" "$MIRROR_BRANCH" "$CUSTOM_BRANCH" \
    || die "origin に $MIRROR_BRANCH / $CUSTOM_BRANCH がありません（dev/fork-sync.md の初期設定を参照）"
}

# 件数を数える。A..B = B にあって A に無いコミット
count() { git rev-list --count "$1..$2"; }

report() {
  local up="$UPSTREAM_REMOTE/$MIRROR_BRANCH" mir="$ORIGIN_REMOTE/$MIRROR_BRANCH" cus="$ORIGIN_REMOTE/$CUSTOM_BRANCH"
  MIRROR_OWN=$(count "$up" "$mir")      # main にだけあるコミット（0 でなければ前提違反）
  UPSTREAM_NEW=$(count "$mir" "$up")    # upstream にあって main にまだ無いコミット
  CUSTOM_BEHIND=$(count "$cus" "$up")   # upstream にあって fork/custom にまだ無いコミット
  info "upstream/$MIRROR_BRANCH  = $(git rev-parse --short "$up")"
  info "$MIRROR_BRANCH: upstream より先行 $MIRROR_OWN / 未取り込み $UPSTREAM_NEW"
  info "$CUSTOM_BRANCH: upstream の未取り込み $CUSTOM_BEHIND / 独自コミット $(count "$up" "$cus")"
}

cmd_check() {
  ensure_remotes
  report
  [ "$MIRROR_OWN" -eq 0 ] || die "$MIRROR_BRANCH が upstream に無いコミットを $MIRROR_OWN 件持っています（ミラー原則違反。独自変更は $CUSTOM_BRANCH へ移す）"
  if [ "$UPSTREAM_NEW" -eq 0 ] && [ "$CUSTOM_BEHIND" -eq 0 ]; then info "同期済み"; return 0; fi
  info "取り込み待ちがあります: dev/fork-sync.sh sync --push"
  exit 10
}

cmd_sync() {
  local push=0
  [ "${1:-}" = "--push" ] && push=1
  ensure_remotes
  report
  [ "$MIRROR_OWN" -eq 0 ] || die "$MIRROR_BRANCH が upstream に無いコミットを $MIRROR_OWN 件持っています（fast-forward できません）"

  local up_sha short sync_branch
  up_sha=$(git rev-parse "$UPSTREAM_REMOTE/$MIRROR_BRANCH")
  short=$(git rev-parse --short=7 "$up_sha")

  # (1) main の fast-forward は fork/custom の状態と独立に行う
  #     （fork/custom を手で同期済みでも main だけ取り残される、を防ぐ。merge が衝突しても main は進める）
  if [ "$UPSTREAM_NEW" -gt 0 ]; then
    if [ "$push" -eq 1 ]; then
      # upstream の SHA をそのまま push する＝ fast-forward でなければ origin 側で拒否される（force しない）
      git push "$ORIGIN_REMOTE" "$up_sha:refs/heads/$MIRROR_BRANCH"
      info "$MIRROR_BRANCH を upstream $short へ fast-forward しました"
    else
      info "$MIRROR_BRANCH は upstream より $UPSTREAM_NEW 件遅れています（--push で fast-forward する）"
    fi
  fi

  if [ "$CUSTOM_BEHIND" -eq 0 ]; then info "$CUSTOM_BRANCH は取り込み済み（sync ブランチは作らない）"; return 0; fi

  sync_branch="sync/upstream-$short"
  # (2) 同じ upstream SHA の sync ブランチが origin に既にあれば作り直さない
  #     （PR 上でレビュー・衝突解消のために積まれたコミットを上書きしない）
  if git ls-remote --exit-code --heads "$ORIGIN_REMOTE" "$sync_branch" >/dev/null 2>&1; then
    info "$sync_branch は origin に既にあります（作り直さない。既存の PR で取り込む）"
    echo "SYNC_BRANCH=$sync_branch"
    echo "UPSTREAM_SHA=$up_sha"
    return 0
  fi

  # 作業ツリーを汚さないよう一時 worktree で行う。trap は関数の外（スクリプト終了時）に走るので local にしない
  SYNC_WT=$(mktemp -d "${TMPDIR:-/tmp}/fork-sync.XXXXXX")
  trap 'git worktree remove --force "${SYNC_WT:-}" >/dev/null 2>&1 || true; rm -rf "${SYNC_WT:-}"' EXIT
  git worktree add --quiet --detach "$SYNC_WT" "$ORIGIN_REMOTE/$CUSTOM_BRANCH"
  (
    cd "$SYNC_WT"
    git checkout --quiet -B "$sync_branch"
    if ! git merge --no-edit -m "chore(sync): merge upstream $short into $CUSTOM_BRANCH" "$up_sha"; then
      git merge --abort || true
      echo "ERROR: upstream $short の merge が衝突しました。手で解消してください（dev/fork-sync.md §4）" >&2
      exit 3
    fi
  )
  info "作成: $sync_branch（$CUSTOM_BRANCH + upstream $short）"

  if [ "$push" -eq 1 ]; then
    git push "$ORIGIN_REMOTE" "$sync_branch"
    info "push 済み。$sync_branch → $CUSTOM_BRANCH の PR を作成してください"
  else
    info "push していません（--push で origin へ送る）"
  fi
  echo "SYNC_BRANCH=$sync_branch"
  echo "UPSTREAM_SHA=$up_sha"
}

case "${1:-}" in
  check) shift; cmd_check "$@" ;;
  sync)  shift; cmd_sync "$@" ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
