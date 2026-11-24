#!/usr/bin/env bash
# handoff.sh — 生成した specs/ を、再構築側の仕様駆動ツール（Kiro / OpenSpec / GitHub Spec Kit）へ渡す素材を作る
#
# 使い方:
#   exporters/handoff.sh <仕様リポジトリ> [--target kiro|openspec|speckit|all] [--out <dir>] [--force]
#
#   <仕様リポジトリ>  init.sh が作った <source>-spec/（specs/ を持つディレクトリ）
#   --target          既定 all
#   --out             既定 <仕様リポジトリ>/handoff。既存のディレクトリには、この道具が作ったもの（.handoff-generated）だけ上書きする
#   --force           .handoff-generated の無い既存ディレクトリにも書く
#
# 書式の機械変換はしない（各ツールの書式は変わりやすい）。代わりに、引用・UNKNOWN・検証状態を落とさないための規則を
# 各ツールの「常に読まれる場所」へ置く素材と、能力ごとの依頼文を作る。対象プロジェクトには書き込まない（人がコピーする）。
# 詳細は exporters/README.md。
#
# 終了コード: 0=成功 2=使い方・入力の誤り
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }
usage() { sed -n '2,18p' "$0"; exit 2; }

REPO="" TARGET=all OUT="" FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    -*) die "不明なオプション: $1" ;;
    *) [ -z "$REPO" ] || die "仕様リポジトリは 1 つだけ指定する"; REPO=$1; shift ;;
  esac
done
[ -n "$REPO" ] || usage
case "$TARGET" in kiro|openspec|speckit|all) ;; *) die "--target は kiro / openspec / speckit / all のどれか（指定: $TARGET）" ;; esac
[ -d "$REPO/specs" ] || die "$REPO に specs/ がありません（init.sh が作った仕様リポジトリを指定する）"
REPO=$(cd "$REPO" && pwd -P)
[ -n "$OUT" ] || OUT="$REPO/handoff"

if [ -e "$OUT" ] && [ ! -d "$OUT" ]; then die "--out がディレクトリではありません: $OUT"; fi
# シンボリックリンクを解いて判定する（まだ無いパスは、存在する祖先で解く。判定前に何も作らない）
_p=$OUT; while [ ! -d "$_p" ]; do _p=$(dirname "$_p"); done
_rest=${OUT#"$_p"}; OUT="$(cd "$_p" && pwd -P)${_rest:+/${_rest#/}}"; OUT=${OUT%/}
# 仕様リポジトリそのもの・specs/ の中・specs/ を持つ場所には書かない（README.md などを上書きしうる）
case "$OUT/" in "$REPO/"|"$REPO/specs/"*) die "--out に仕様リポジトリそのものや specs/ の中は指定できません: $OUT" ;; esac
[ ! -d "$OUT/specs" ] || die "--out に specs/ を持つディレクトリは指定できません: $OUT"
mkdir -p "$OUT"
MANIFEST="$OUT/.handoff-generated"
# 既存の出力先: この道具が作ったもの（目録あり）なら、目録に載ったファイルだけ消して書き直す。
# 目録の無い空でないディレクトリは --force のときだけ使い、その場合も既存のファイル・ディレクトリには触れない（衝突したら止める）
if [ -f "$MANIFEST" ]; then
  while IFS= read -r g; do
    case "$g" in ''|/*|*..*) continue ;; esac
    if [ -f "$OUT/$g" ] && [ ! -L "$OUT/$g" ]; then rm -f "$OUT/$g"; fi
  done < "$MANIFEST"
  # 空になったディレクトリだけ片付ける（利用者のファイルが入ったディレクトリは残る）
  find "$OUT" -depth -mindepth 1 -type d -empty -delete 2>/dev/null || true
elif [ -n "$(ls -A "$OUT")" ]; then
  [ "$FORCE" -eq 1 ] || die "$OUT は空でなく、この道具が作ったものではありません（使うなら --force。既存のファイルには触れない）"
fi
: > "$MANIFEST.new"
# 途中で止まっても、書いたファイルは目録に残す（次回の再実行で片付けられるように）
trap '[ -f "$MANIFEST.new" ] && mv -f "$MANIFEST.new" "$MANIFEST"' EXIT
# emit <相対パス>: 出力ファイルを作る（既存の、目録に無いファイルは上書きしない）。標準入力を書く
emit() {
  local rp=$1 dst="$OUT/$1"
  if [ -e "$dst" ] || [ -L "$dst" ]; then die "既存のファイルを上書きしません: $dst（この道具が作ったものではない）"; fi
  mkdir -p "$(dirname "$dst")"
  cat > "$dst"
  echo "$rp" >> "$MANIFEST.new"
}

# --- 能力の選択 -----------------------------------------------------------------
# 1) specs/rebuild/ のうち能力仕様の目印（artifact-key: capability-spec。旧値 tier1-rebuild も受ける）を持つもの
# 2) 無ければ specs/behavior/*.md
# どちらも _ で始まるファイル（雛形）と spec-id が TEMPLATE-DO-NOT-INDEX のものは除く
fm() { # fm <file> <key> — 最初の front-matter（--- で囲まれた区画。前に HTML コメントがあってよい）から値を読む
  awk -v k="$2" '{ line=$0; sub(/\r$/, "", line) }
    state==0 && line=="---" { state=1; next }
    state==0 && line ~ /^#/ { exit }            # 見出しに達したら front-matter は無い
    state==1 && line=="---" { exit }
    state==1 && index(line, k ":")==1 { sub(/^[^:]*:[[:space:]]*/, "", line)
      if (line ~ /^".*"$/ || line ~ /^\047.*\047$/) line = substr(line, 2, length(line) - 2)
      else sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line); print line; exit }' "$1"
}
is_template() { [ "$(basename "$1" | cut -c1)" = _ ] || [ "$(fm "$1" spec-id)" = TEMPLATE-DO-NOT-INDEX ]; }
# 能力仕様の目印。gates.sh の artifact_key_re と同じく行頭に固定する（散文に書いただけの語を拾わない）
CAP_RE="^($(printf '\357\273\277'))?[[:space:]]*(<!--[[:space:]]*)?artifact-key: (capability-spec|tier1-rebuild)"

SOURCE_KIND=""
CAPS=() SKIPPED=()
collect() { # collect <dir> <require-cap-marker 0|1>
  local f cs
  while IFS= read -r f; do
    is_template "$f" && continue
    [ "$2" -eq 1 ] && ! grep -qE "$CAP_RE" "$f" && continue
    cs=$(fm "$f" coverage-status)
    case "$cs" in
      out-of-scope|generated) SKIPPED+=("$f|$cs|$(fm "$f" scope-exclusion)"); continue ;;
    esac
    CAPS+=("$f")
  done < <(find "$1" -type f -name '*.md' ! -name '_*' 2>/dev/null | LC_ALL=C sort)
}
[ -d "$REPO/specs/rebuild" ] && collect "$REPO/specs/rebuild" 1
if [ ${#CAPS[@]} -gt 0 ]; then SOURCE_KIND="specs/rebuild（技術非依存の能力仕様）"
else
  [ -d "$REPO/specs/behavior" ] && collect "$REPO/specs/behavior" 0
  [ ${#CAPS[@]} -gt 0 ] && SOURCE_KIND="specs/behavior（実装事実層。能力仕様が無いため）"
fi
[ ${#CAPS[@]} -gt 0 ] || die "渡せる仕様がありません（specs/rebuild の能力仕様も specs/behavior の仕様も 0 件。out-of-scope / generated は渡さない）"

# UNKNOWN の集計。gates.sh の G-FRESH と同じ規則: HTML コメントの中と、取り消し線で「解消済」と書いた行は数えない。
# タグの無い `UNKNOWN:` / `UNKNOWN：` は未決（blocking と同じ扱い）。undecidable・deferred などは「その他」に数える。
# 出力: "<未決> <partial> <その他>"
unknown_counts() {
  awk '
    { line=$0
      while (1) {
        if (incom) { e=index(line, "-->"); if (!e) { line=""; break } line=substr(line, e+3); incom=0 }
        s=index(line, "<!--"); if (!s) break
        out=out substr(line, 1, s-1); line=substr(line, s+4); incom=1
      }
      text=out line; out=""
      if (text ~ /~~.*~~ \*\*解消済/) next
      while (match(text, /UNKNOWN(\[[^]]*\]|:|：)?/)) {
        tok=substr(text, RSTART, RLENGTH)
        if (tok=="UNKNOWN[blocking]" || tok=="UNKNOWN:" || tok=="UNKNOWN：") b++
        else if (tok=="UNKNOWN[partial]") p++
        else if (tok!="UNKNOWN[...]") o++
        text=substr(text, RSTART+RLENGTH)
      }
    }
    END { printf "%d %d %d\n", b, p, o }' "$1"
}

rel() { printf '%s' "${1#"$REPO"/}"; }

# 検証状態の正本は密度台帳（spec-extraction/03-audit/density-ledger.tsv の verify_status・fabricated_open）。
# front-matter の verification: は表示にすぎない（gates.sh の決着どおり）ので判定に使わない。
LEDGER="$REPO/spec-extraction/03-audit/density-ledger.tsv"
ledger_state() { # ledger_state <rel-path> → "<blocks> <not-verified> <fabricated_open>"（台帳が無ければ "-"）
  [ -f "$LEDGER" ] || { echo "-"; return; }
  awk -F'\t' -v f="$1" '
    /^#/ || NF < 2 { next }
    !h { for (i=1;i<=NF;i++) { k=$i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); c[k]=i } h=1; next }
    { sf=$c["spec_file"]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sf); sub(/^\.\//, "", sf)
      if (sf != f) next
      n++; vs=$c["verify_status"]; gsub(/[[:space:]]/, "", vs); if (vs != "verified") nv++
      fo=$c["fabricated_open"]; gsub(/[[:space:]]/, "", fo); if (fo ~ /^[0-9]+$/) fab += fo }
    END { printf "%d %d %d\n", n, nv, fab }' "$LEDGER"
}

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "（git でない）")
ANOM="spec-extraction/03-audit/observed-anomalies.md"

# --- 共通: README（能力一覧）と context.md ------------------------------------------
total_block=0 not_ready=0
ROWS=""
for f in "${CAPS[@]}"; do
  read -r b pa o < <(unknown_counts "$f")
  cs=$(fm "$f" coverage-status)
  reasons=()
  [ "$b" -gt 0 ] && reasons+=("未決の UNKNOWN が残る")
  [ "$pa" -gt 0 ] && reasons+=("partial（確認範囲の外は未確定）")
  case "$cs" in verified) ;; *) reasons+=("coverage-status=${cs:-なし}") ;; esac
  st=$(ledger_state "$(rel "$f")")
  if [ "$st" = "-" ]; then vtxt="台帳なし"; reasons+=("検証状態を確認できない（台帳なし）")
  else
    read -r nb nv fab <<<"$st"
    if [ "$nb" -eq 0 ]; then vtxt="台帳に行なし"; reasons+=("台帳に密度ブロックが無い")
    else
      vtxt="${nb} ブロック中 未検証 ${nv}・fabricated 残 ${fab}"
      [ "$nv" -gt 0 ] && reasons+=("未検証のブロックがある")
      [ "$fab" -gt 0 ] && reasons+=("fabricated が残る")
    fi
  fi
  if [ ${#reasons[@]} -gt 0 ]; then
    joined=""; for r in "${reasons[@]}"; do joined="${joined:+$joined・}$r"; done
    ready="**要注意**（$joined）"; not_ready=$((not_ready+1))
  else ready="可"; fi
  total_block=$((total_block+b))
  ROWS="$ROWS| \`$(rel "$f")\` | \`$(fm "$f" spec-id)\` | ${cs:-—} | $vtxt | $b | $pa | $o | $ready |
"
done

{
  echo "# handoff — 仕様駆動ツールへの受け渡し素材"
  echo
  echo "- 生成元: \`$REPO\`（コミット \`$COMMIT\`）"
  echo "- 生成日時: $NOW（\`exporters/handoff.sh\`）"
  echo "- 渡す単位: $SOURCE_KIND、${#CAPS[@]} 件"
  echo
  echo "**この素材は仕様を書き換えない。** 各ツールの AI が \`specs/\` を直接読み、要求・設計・タスクを起こす。"
  echo "そのとき引用・UNKNOWN・検証状態を落とさないための規則が \`context.md\`（と各ツール向けの写し）である。"
  echo
  echo "## 能力の一覧"
  echo
  echo "検証状態は密度台帳（\`spec-extraction/03-audit/density-ledger.tsv\`）が正本。front-matter の \`verification:\` は使わない。"
  echo "「可」は**機械的に確かめられる範囲で**問題が無いという意味で、仕様の正しさを保証しない（\`specs/AGENTS.md\` §2 の確認は別に要る）。"
  echo
  echo "| 仕様ファイル | spec-id | coverage-status | 密度台帳 | 未決 UNKNOWN | partial | その他の UNKNOWN | 渡してよいか |"
  echo "|---|---|---|---|---|---|---|---|"
  printf '%s' "$ROWS"
  echo
  echo "要注意 ${not_ready} 件 / 未決の UNKNOWN 合計 ${total_block} 件。**要注意の能力は、再構築側で確定扱いしない**（\`context.md\` 規則 4）。"
  if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo
    echo "### 渡さなかった仕様（母集団外・機械生成物）"
    echo
    echo "| 仕様ファイル | coverage-status | scope-exclusion |"
    echo "|---|---|---|"
    for sk in "${SKIPPED[@]}"; do
      IFS='|' read -r sf scs sex <<<"$sk"
      echo "| \`$(rel "$sf")\` | $scs | ${sex:-—} |"
    done
  fi
  echo
  echo "## 各ツールへの置き方"
  echo
  echo "| ツール | 置くもの | 置き先（対象プロジェクト） | 確認できた範囲（2026-11） |"
  echo "|---|---|---|---|"
  echo "| Kiro | \`kiro/.kiro/steering/reverse-spec.md\` | \`.kiro/steering/\` | steering の置き場所と \`inclusion: always\`。spec ファイルの置き場所・書式は未確認なので依頼文で作らせる |"
  echo "| OpenSpec | \`openspec/config-context.md\` の本文 | \`openspec/config.yaml\` の \`context: \\|\` ブロックの中（字下げして追記） | \`context:\` が全成果物に注入されること。要求は \`### Requirement:\` ＋ \`#### Scenario:\`（\`openspec validate\` が検査） |"
  echo "| Spec Kit | \`speckit/constitution-addendum.md\` の中身 | \`.specify/memory/constitution.md\` の末尾に**追記** | constitution の置き場所。spec の書式（FR-001・\`[NEEDS CLARIFICATION: …]\`）は雛形から |"
  echo
  echo "**どのツールでも、次を対象プロジェクトから読める場所に置く**（例: 対象プロジェクトの文書ディレクトリに複製するか、サブモジュールにする）。"
  echo "置いた場所に合わせて \`context.md\` 内のパスを読み替える。"
  echo
  echo "- \`specs/\` 一式（\`specs/AGENTS.md\` を含む）"
  echo "- \`$ANOM\`（観測された異常の記録。**仕様どおりに直すと壊れる箇所**が載る。無ければ不要）"
  echo
  echo "**SUPPORT_LEVEL: placed-unverified** — 各ツールでの往復（依頼文 → 生成物 → 引用が残ったか）を実測していない。"
  echo "測ったら \`exporters/README.md\` の対応表を更新する。"
} | emit README.md

CONTEXT_BODY="既存システムの仕様は reverse-spec-flow が生成した \`specs/\` にある。再構築ではこれを既存挙動の正本として扱う。

1. 要求・設計・タスクを起こす前に \`specs/AGENTS.md\` を読み、そこに書かれた信頼度の判定（coverage-status・UNKNOWN・検証状態）に従う。
2. 既存挙動に由来する要求・設計判断・タスクには、根拠の仕様 ID（\`[[SPEC-...]]\`）と、仕様が挙げた \`path:line\` をそのまま引き継いで書く。根拠を書けないものは既存挙動ではなく新規の決定として区別する。
3. \`UNKNOWN[...]\` を推測で埋めない。そのツールの「未確定」の書き方（質問・NEEDS CLARIFICATION・open question）に写し、種別（blocking / partial / undecidable など）を残す。\`UNKNOWN[blocking]\` を含む能力は、それが解消するまで実装タスクに進めない。\`UNKNOWN[partial]\` は書かれた確認範囲の外を未確定として扱う。
4. 受け渡し素材の一覧（handoff/README.md）で「要注意」の能力は確定扱いしない。そこから起こした要求には「未検証の仕様に由来」と書く。
5. 仕様に書かれていない挙動を「既存どおり」と書かない。既存どおりと書けるのは、仕様に根拠があるものだけ。
6. \`$ANOM\` があれば読む。そこに載った異常は、仕様どおりに直すと既存の利用者や連携先が壊れる可能性がある。再構築で直すか残すかを要求として明示的に決める。"

{ echo "# 再構築で既存仕様（reverse-spec-flow）を使うときの規則"; echo; printf '%s\n' "$CONTEXT_BODY"; } | emit context.md

# --- ツール別 --------------------------------------------------------------------
want() { [ "$TARGET" = all ] || [ "$TARGET" = "$1" ]; }
prompts() { # prompts <title> <intro> <command-template>  ({F}=仕様ファイル)
  echo "# $1"; echo; printf '%s\n' "$2"; echo
  for f in "${CAPS[@]}"; do
    echo "## $(fm "$f" spec-id)"; echo; echo '```text'
    printf '%s\n' "$3" | sed "s|{F}|$(rel "$f")|g"
    echo '```'; echo
  done
}

if want kiro; then
  { echo "---"; echo "inclusion: always"; echo "---"; echo; echo "# 既存仕様（reverse-spec-flow）の扱い"; echo; printf '%s\n' "$CONTEXT_BODY"; } \
    | emit kiro/.kiro/steering/reverse-spec.md
  prompts "Kiro への依頼文（能力ごと）" \
    "\`kiro/.kiro/steering/reverse-spec.md\` を対象プロジェクトの \`.kiro/steering/\` に置いてから、能力ごとに新しい spec を作り、次の依頼文を渡す。" \
    "{F} を読み、この能力の再構築用の spec（requirements / design / tasks）を作ってください。
steering の reverse-spec.md の規則に従い、要求ごとに根拠の [[SPEC-...]] と path:line を残し、UNKNOWN は推測で埋めずに未確定として列挙してください。" \
    | emit kiro/prompts.md
fi

if want openspec; then
  { echo "<!-- openspec/config.yaml の context: | ブロックの中に、字下げを揃えて追記する本文（YAML のキーは含まない） -->"; echo; printf '%s\n' "$CONTEXT_BODY"; } \
    | emit openspec/config-context.md
  prompts "OpenSpec への依頼文（能力ごと）" \
    "\`openspec/config-context.md\` の本文を対象プロジェクトの \`openspec/config.yaml\` の \`context: |\` に追記してから、能力ごとに変更提案を作る。
要求は \`### Requirement:\` に SHALL / MUST で書き、各要求に \`#### Scenario:\`（WHEN / THEN）を 1 つ以上付ける（\`openspec validate\` が検査する）。" \
    "{F} を読み、この能力を再構築する変更提案（proposal・specs のデルタ・design・tasks）を作ってください。
各 Requirement の本文に根拠の [[SPEC-...]] と path:line を残し、UNKNOWN は推測で埋めずに design の未確定事項として列挙してください。" \
    | emit openspec/prompts.md
fi

if want speckit; then
  { echo "## 既存仕様（reverse-spec-flow）の扱い"; echo; printf '%s\n' "$CONTEXT_BODY"; } | emit speckit/constitution-addendum.md
  prompts "Spec Kit への依頼文（能力ごと）" \
    "\`speckit/constitution-addendum.md\` の内容を対象プロジェクトの \`.specify/memory/constitution.md\` の末尾に追記してから、能力ごとに \`/speckit.specify\` を実行する。
UNKNOWN は \`[NEEDS CLARIFICATION: …]\` に写し、\`/speckit.clarify\` で解消してから plan に進む。" \
    "/speckit.specify {F} に書かれた既存の能力を再構築する。各 FR に根拠の [[SPEC-...]] と path:line を残し、UNKNOWN は [NEEDS CLARIFICATION: ...] にする。" \
    | emit speckit/prompts.md
fi

mv "$MANIFEST.new" "$MANIFEST"
echo "handoff: ${#CAPS[@]} 件の能力を $OUT に書き出しました（要注意 ${not_ready} 件・未決の UNKNOWN ${total_block} 件）"
