#!/usr/bin/env bash
# change-dev.sh — fork/custom への変更の運用ヘルパー（dev/change-dev.md が正本）
#
# 使い方:
#   dev/change-dev.sh mode                    Auto-Pilot（CHG_DEV_AUTO_PILOT）を解決し、分岐を表示する
#   dev/change-dev.sh mode --value            true / false だけを出力する（ワークフロー用）
#   dev/change-dev.sh plan-check [base] [head-branch]
#       計画先行の検査。base（既定 origin/fork/custom）から HEAD までのコミットで、
#       実装ファイルに触れる最初のコミットより前に「計画ファイルだけのコミット」があることを確かめる。
#       計画ファイル = .devs/changes/<YYYY-MM-DD>_<slug>/implementation_plan.md（同じ場所の task.md も可）
#       計画は base に無い新しい implementation_plan.md であること（マージ済みの古い計画は数えない）
#       免除: 変更が docs/・README*・.devs/ だけのブランチ、sync/upstream-* と dependabot/* ブランチ
#             （名前での免除は品質ゲートのため。auto-merge.yml はこれらのブランチを自動マージしない）
#
# 終了コード: 0=通過 1=違反（理由を表示） 2=使い方・前提の誤り
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: git リポジトリ内で実行してください" >&2; exit 2; }
KEY=CHG_DEV_AUTO_PILOT
DEFAULTS_FILE="$ROOT/.github/change-dev.env"

# KEY=value 形式から値を読む（# コメント・引用符・export を許す）。無ければ空
read_env_value() {
  local file=$1
  [ -r "$file" ] || return 0
  awk -v k="$KEY" '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/^[[:space:]]*(export[[:space:]]+)?/, "", line)
      if (index(line, k "=") != 1 && line !~ ("^" k "[[:space:]]*=")) next
      sub(/^[^=]*=[[:space:]]*/, "", line)
      if (line ~ /^".*"$/ || line ~ /^\x27.*\x27$/) line = substr(line, 2, length(line) - 2)
      else sub(/[[:space:]]+#.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      v = line
    }
    END { if (v != "") print v }
  ' "$file"
}

is_true() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in true|1) return 0 ;; *) return 1 ;; esac; }

# 解決順: プロセス環境変数（Actions ではリポジトリ変数 vars.CHG_DEV_AUTO_PILOT をここへ渡す）→ .env → .github/change-dev.env
resolve_mode() {
  local raw src
  if [ -n "${CHG_DEV_AUTO_PILOT:-}" ]; then raw=$CHG_DEV_AUTO_PILOT; src=env
  else
    raw=$(read_env_value "$ROOT/.env"); src=.env
    if [ -z "$raw" ]; then raw=$(read_env_value "$DEFAULTS_FILE"); src=.github/change-dev.env; fi
    if [ -z "$raw" ]; then src=unset; fi
  fi
  MODE_RAW=$raw; MODE_SRC=$src
  if is_true "$raw"; then MODE=true; else MODE=false; fi
}

cmd_mode() {
  resolve_mode
  if [ "${1:-}" = "--value" ]; then echo "$MODE"; return 0; fi
  echo "$KEY=$MODE（出所: $MODE_SRC${MODE_RAW:+, 値: $MODE_RAW}）"
  if [ "$MODE" = true ]; then
    cat <<'EOF'
  計画レビュー: 待たない（計画をコミットして要約を報告し、続行する。PR で再レビューされる）
  PR          : ready for review で作る
  PR 作成後   : 品質ゲート成功で auto-merge.yml が Rebase Merge する（止めるときは PR に hold ラベル）
EOF
  else
    cat <<'EOF'
  計画レビュー: 承認を待つ
  PR          : draft で作る
  PR 作成後   : 人がマージする（auto-merge.yml は何もしない）
EOF
  fi
}

is_plan_file() { [[ "$1" =~ ^\.devs/changes/[0-9]{4}-[0-9]{2}-[0-9]{2}_[^/]+/(implementation_plan|task)\.md$ ]]; }
is_exempt_file() { [[ "$1" == docs/* || "$1" == README* || "$1" == .devs/* ]]; }

cmd_plan_check() {
  local base=${1:-origin/fork/custom} branch=${2:-}
  [ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD)
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "ERROR: base '$base' がありません" >&2; exit 2; }

  case "$branch" in
    sync/upstream-*|dependabot/*) echo "plan-check: 免除（$branch は取り込み・依存更新のブランチ）"; return 0 ;;
  esac

  local files f all_exempt=1
  files=$(git -c core.quotePath=false diff --name-only "$base"...HEAD)
  if [ -z "$files" ]; then echo "plan-check: 免除（$base からの変更なし）"; return 0; fi
  while IFS= read -r f; do is_exempt_file "$f" || { all_exempt=0; break; }; done <<<"$files"
  if [ "$all_exempt" -eq 1 ]; then echo "plan-check: 免除（docs/・README*・.devs/ だけの変更）"; return 0; fi

  # 先に「最後に base を取り込んだ merge 以降」だけを見る。同じブランチで前の PR が squash / rebase で
  # マージ済みのとき、その古いコミット（base には別 SHA で入っている）で次の変更を違反扱いしないため。
  # そこに計画が無ければ全履歴で判定し直す（途中で base を merge しただけのブランチを誤って落とさない）。
  local m p seg=""
  for m in $(git rev-list --first-parent --merges "$base"..HEAD); do
    for p in $(git rev-list --parents -n 1 "$m" | cut -d' ' -f3-); do
      if git merge-base --is-ancestor "$p" "$base"; then seg=$m; break 2; fi
    done
  done
  if [ -n "$seg" ] && plan_check_range "$base" "$seg..HEAD" 2>/dev/null; then return 0; fi
  plan_check_range "$base" "$base..HEAD"
}

# plan_check_range <base> <rev-range>: 範囲内のコミットを古い順に見て、実装に触れる最初のコミットより前に
# base に無い implementation_plan.md だけのコミットがあるかを判定する
plan_check_range() {
  local base=$1 range=$2 c cf f plan_seen=0 plan_commit="" only_plan has_plan
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # base を取り込む merge 自体は判定しない（中身は base の変更）
    if [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -gt 2 ]; then continue; fi
    cf=$(git -c core.quotePath=false diff-tree --no-commit-id --name-only -r --root "$c" | sort -u)
    [ -n "$cf" ] || continue
    only_plan=1; has_plan=0
    while IFS= read -r f; do
      if is_plan_file "$f"; then
        # base に既にある計画は数えない（マージ済みの古い計画で次の変更を通さない）
        if [[ "$f" == */implementation_plan.md ]] && ! git cat-file -e "$base:$f" 2>/dev/null; then has_plan=1; fi
      else only_plan=0; fi
    done <<<"$cf"
    if [ "$only_plan" -eq 1 ]; then
      [ "$has_plan" -eq 1 ] && { plan_seen=1; plan_commit=$c; }
      continue
    fi
    # 計画ファイル以外に触れる最初のコミット
    if [ "$plan_seen" -eq 1 ]; then
      echo "plan-check: 通過（計画 $(git rev-parse --short "$plan_commit") → 最初の実装 $(git rev-parse --short "$c")）"
      return 0
    fi
    echo "plan-check: 違反 — 実装コミット $(git rev-parse --short "$c") より前に、計画ファイルだけのコミットがありません。" >&2
    if printf '%s\n' "$cf" | grep -q '/implementation_plan\.md$'; then
      echo "  計画が実装と同じコミットに入っています。計画を単独のコミットに分けてください。" >&2
    fi
    echo "  .devs/changes/<YYYY-MM-DD>_<slug>/implementation_plan.md を単独でコミットしてから実装する（dev/change-dev.md §2）" >&2
    return 1
  done < <(git rev-list --reverse --topo-order "$range")
  echo "plan-check: 違反 — 実装の変更があるのに、それに先立つ計画コミットが見つかりません" >&2
  return 1
}

case "${1:-}" in
  mode) shift; cmd_mode "$@" ;;
  plan-check) shift; cmd_plan_check "$@" ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
