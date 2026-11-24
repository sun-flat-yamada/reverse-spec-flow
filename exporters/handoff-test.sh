#!/usr/bin/env bash
# handoff-test.sh — exporters/handoff.sh をフィクスチャの仕様リポジトリで検査する（ネットワーク不使用）。exit 0 = 全件通過
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H="$HERE/handoff.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "  ✅ $1"; }
ng() { echo "  ❌ $1"; fail=1; }
expect_rc() { [ "$2" -eq "$1" ] && ok "$3 (rc=$2)" || ng "$3 (want rc=$1, got rc=$2)"; }
row() { grep -F "| \`specs/$1\` |" "$R/handoff/README.md"; }

R="$T/repo"; mkdir -p "$R/specs/rebuild/sub" "$R/specs/behavior" "$R/spec-extraction/03-audit"
cap() { # cap <相対パス> <spec-id> <coverage> <本文>
  { echo "<!-- artifact-key: capability-spec -->"; echo "<!-- 前置きのコメント -->"
    echo "---"; echo "spec-id: \"$2\""; echo "coverage-status: $3   # 表示用のコメント"; echo "verification: verified"; echo "scope-exclusion: 対象外の理由"; echo "---"
    echo; echo "# $2"; echo; printf '%s\n' "$4"; } > "$R/specs/rebuild/$1"
}

"$H" "$R" >/dev/null 2>&1; expect_rc 2 $? "渡せる仕様が 0 件なら 2"
"$H" "$T/nope" >/dev/null 2>&1; expect_rc 2 $? "specs/ の無いディレクトリは 2"

cap _capability-template.md TEMPLATE-DO-NOT-INDEX draft "雛形 UNKNOWN[blocking]"
cap order.md SPEC-rebuild-order-01 verified "注文は確定できる（\`src/A.java:10\`）。<!-- UNKNOWN[blocking] コメント内は数えない -->
~~UNKNOWN[blocking] 在庫引当の順序~~ **解消済**（\`src/B.java:3\`）
凡例: \`UNKNOWN[...]\` は未確定を表す"
cap pay.md SPEC-rebuild-pay-01 draft "支払い UNKNOWN[blocking] と UNKNOWN[partial] と UNKNOWN[undecidable]
返金 UNKNOWN: 手順が未確認
<!-- 複数行の
UNKNOWN[blocking] もコメント内 -->"
cap sub/ship.md SPEC-rebuild-ship-01 verified "出荷（サブディレクトリ）"
cap legacy.md SPEC-rebuild-legacy-01 out-of-scope "母集団外"
printf '# 説明\n\n本文で artifact-key: capability-spec と書いただけの散文\n\n---\nspec-id: SPEC-rebuild-prose-01\n---\n' > "$R/specs/rebuild/prose.md"
printf '<!-- artifact-key: screen-map -->\n---\nspec-id: SPEC-rebuild-screens-01\n---\n' > "$R/specs/rebuild/screen-map.md"

out=$("$H" "$R" 2>&1); expect_rc 0 $? "能力仕様があれば成功する"
README="$R/handoff/README.md"
rows=$(grep -c '^| `specs/rebuild/[^|]*` | `SPEC' "$README")
[ "$rows" -eq 3 ] && ok "能力仕様だけを数える（雛形・画面マップ・散文の目印・out-of-scope を除き、サブディレクトリを含む。3 件）" || ng "能力の件数が違う: $rows"
row rebuild/sub/ship.md >/dev/null && ok "サブディレクトリの能力仕様も拾う" || ng "サブディレクトリの能力仕様を拾わない"
row rebuild/prose.md >/dev/null && ng "行頭でない散文の目印を拾った" || ok "行頭に無い目印（散文）は拾わない"
grep -qF '| `specs/rebuild/legacy.md` | out-of-scope | 対象外の理由 |' "$README" \
  && ok "out-of-scope は渡さず、理由と一緒に「渡さなかった仕様」に並べる" || ng "out-of-scope の扱いが違う"
grep -q '^## SPEC-rebuild-legacy-01' "$R/handoff/kiro/prompts.md" && ng "out-of-scope の依頼文を出した" || ok "out-of-scope の依頼文は出さない"

# 台帳が無いとき: verification: verified と書いてあっても要注意
row rebuild/order.md | grep -qF '| `SPEC-rebuild-order-01` | verified | 台帳なし | 0 | 0 | 0 | **要注意**（検証状態を確認できない（台帳なし）） |' \
  && ok "spec-id の引用符・値のコメントを落とし、台帳が無ければ front-matter の verification を信じず要注意" || ng "order.md の行（台帳なし）が違う: $(row rebuild/order.md)"
row rebuild/pay.md | grep -qF '| draft | 台帳なし | 2 | 1 | 1 | **要注意**（未決の UNKNOWN が残る・partial（確認範囲の外は未確定）・coverage-status=draft・検証状態を確認できない（台帳なし）） |' \
  && ok "UNKNOWN を G-FRESH と同じ規則で数える（UNKNOWN: は未決・コメント内と解消済の行と凡例は除く）" || ng "pay.md の行が違う: $(row rebuild/pay.md)"
printf '%s' "$out" | grep -q '3 件の能力.*要注意 3 件・未決の UNKNOWN 2 件' && ok "要約行の件数が一覧と一致する" || ng "要約行が違う: $out"

# 台帳あり: 列の順番に依存せず見出しで読む
printf '# 密度台帳\nverify_status\tspec_file\tfabricated_open\tblock\nverified\tspecs/rebuild/order.md\t0\tb1\nverified\t./specs/rebuild/order.md\t0\tb2\nverified\tspecs/rebuild/sub/ship.md\t0\tb1\nunverified\tspecs/rebuild/sub/ship.md\t2\tb2\n' \
  > "$R/spec-extraction/03-audit/density-ledger.tsv"
"$H" "$R" >/dev/null 2>&1; expect_rc 0 $? "台帳があっても成功する"
row rebuild/order.md | grep -qF '| verified | 2 ブロック中 未検証 0・fabricated 残 0 | 0 | 0 | 0 | 可 |' \
  && ok "台帳の全ブロックが verified・fabricated 0 なら「可」" || ng "order.md の行（台帳あり）が違う: $(row rebuild/order.md)"
row rebuild/sub/ship.md | grep -qF '2 ブロック中 未検証 1・fabricated 残 2 | 0 | 0 | 0 | **要注意**（未検証のブロックがある・fabricated が残る） |' \
  && ok "台帳に未検証・fabricated が残れば要注意" || ng "ship.md の行が違う: $(row rebuild/sub/ship.md)"
row rebuild/pay.md | grep -qF '台帳に行なし' && ok "台帳に行が無い能力は要注意" || ng "台帳に行が無い能力の扱いが違う"

for f in context.md kiro/.kiro/steering/reverse-spec.md kiro/prompts.md openspec/config-context.md openspec/prompts.md speckit/constitution-addendum.md speckit/prompts.md; do
  [ -s "$R/handoff/$f" ] || ng "出力が無い: $f"
done
ok "3 ツール分の出力がそろう（欠けていれば上に ❌）"
[ "$(head -3 "$R/handoff/kiro/.kiro/steering/reverse-spec.md" | tr '\n' '|')" = "---|inclusion: always|---|" ] \
  && ok "Kiro steering は先頭に front-matter（inclusion: always）" || ng "Kiro steering の先頭が違う"
grep -q '^context:' "$R/handoff/openspec/config-context.md" && ng "OpenSpec の断片に context: キーが入っている（既存の config.yaml と重複する）" \
  || ok "OpenSpec の断片は本文だけ（context: キーを含まない）"
grep -c '^| OpenSpec |' "$README" >/dev/null && [ "$(grep '^| OpenSpec |' "$README" | sed 's/\\|//g' | tr -cd '|' | wc -c)" -eq 5 ] \
  && ok "置き方の表の OpenSpec 行は列が崩れない（| を逃がしている）" || ng "OpenSpec 行の列数が違う"
for t in kiro openspec speckit; do
  n=$(grep -c '^## SPEC-rebuild-' "$R/handoff/$t/prompts.md")
  [ "$n" -eq 3 ] || ng "$t の依頼文の件数が違う: $n"
done
ok "依頼文は能力ごとに 1 つ（各ツール 3 件）"
for f in "$R"/handoff/context.md "$R"/handoff/kiro/.kiro/steering/reverse-spec.md "$R"/handoff/openspec/config-context.md "$R"/handoff/speckit/constitution-addendum.md; do
  grep -q 'UNKNOWN\[...\]` を推測で埋めない' "$f" || ng "規則が写っていない: $f"
  grep -q 'observed-anomalies.md' "$f" || ng "観測された異常の規則が無い: $f"
done
ok "共通規則（UNKNOWN を推測で埋めない・observed-anomalies を読む）が全置き場所に写る"

"$H" "$R" --target kiro --out "$T/only-kiro" >/dev/null 2>&1; expect_rc 0 $? "--target kiro が成功する"
[ -d "$T/only-kiro/kiro" ] && [ ! -e "$T/only-kiro/openspec" ] && [ ! -e "$T/only-kiro/speckit" ] && ok "--target は指定ツールだけを書く" || ng "--target 以外のツールも書いた"

# 再実行: 目録に載ったものだけを消す
mkdir -p "$R/handoff/openspec/specs/mine" && echo keep > "$R/handoff/openspec/specs/mine/spec.md"
echo keep > "$R/handoff/notes.md"
"$H" "$R" --target speckit >/dev/null 2>&1; expect_rc 0 $? "自分が作った出力先には再実行で書き直せる"
[ -d "$R/handoff/speckit" ] && [ ! -e "$R/handoff/kiro" ] && [ ! -e "$R/handoff/openspec/prompts.md" ] && ok "--target を変えて再実行すると前回の他ツール分は残らない" || ng "前回の他ツール分が残った"
[ "$(cat "$R/handoff/openspec/specs/mine/spec.md" 2>/dev/null)" = keep ] && [ "$(cat "$R/handoff/notes.md" 2>/dev/null)" = keep ] \
  && ok "再実行でも、利用者が足したファイルは消さない" || ng "利用者のファイルを消した"
printf '../outside\n/etc/passwd\n' >> "$R/handoff/.handoff-generated"; echo keep > "$T/outside"
"$H" "$R" >/dev/null 2>&1; expect_rc 0 $? "目録に不正な行があっても成功する"
[ "$(cat "$T/outside")" = keep ] && ok "目録の .. や絶対パスの行は無視する（出力先の外を消さない）" || ng "出力先の外を消した"

mkdir -p "$T/foreign" && echo keep > "$T/foreign/mine.txt"
"$H" "$R" --out "$T/foreign" >/dev/null 2>&1; expect_rc 2 $? "この道具が作っていない空でないディレクトリには書かない"
[ "$(cat "$T/foreign/mine.txt")" = keep ] && [ ! -e "$T/foreign/README.md" ] && ok "拒否したとき何も書かない" || ng "拒否したのに書いた"
"$H" "$R" --out "$T/foreign" --force >/dev/null 2>&1; expect_rc 0 $? "--force なら書く"
[ "$(cat "$T/foreign/mine.txt")" = keep ] && ok "--force でも既存のファイルは残す" || ng "--force で既存のファイルを変えた"
mkdir -p "$T/clash" && echo mine > "$T/clash/README.md"
"$H" "$R" --out "$T/clash" --force >/dev/null 2>&1; expect_rc 2 $? "--force でも既存のファイルと衝突したら止める"
[ "$(cat "$T/clash/README.md")" = mine ] && ok "衝突したファイルを上書きしない" || ng "衝突したファイルを上書きした"

"$H" "$R" --out "$R" --force >/dev/null 2>&1; expect_rc 2 $? "--force でも仕様リポジトリそのものには書かない"
"$H" "$R" --out "$R/specs" --force >/dev/null 2>&1; expect_rc 2 $? "--force でも specs/ には書かない"
"$H" "$R" --out "$R/specs/new/dir" --force >/dev/null 2>&1; expect_rc 2 $? "--force でも specs/ の下の新しいパスには書かない"
[ ! -e "$R/specs/new" ] && ok "拒否したとき specs/ の下にディレクトリを作らない" || ng "拒否したのに specs/ の下にディレクトリを作った"
ln -s "$R/specs" "$T/link-to-specs"
"$H" "$R" --out "$T/link-to-specs" --force >/dev/null 2>&1; expect_rc 2 $? "specs/ へのシンボリックリンクは拒否する"
ln -s "$R" "$T/link-to-repo"
"$H" "$R" --out "$T/link-to-repo/x" --force >/dev/null 2>&1; expect_rc 0 $? "リンク越しでも仕様リポジトリの下の新しいディレクトリは使える"
"$H" "$R" --out "$T/link-to-repo" --force >/dev/null 2>&1; expect_rc 2 $? "仕様リポジトリへのシンボリックリンクは拒否する"
"$H" "$R" --target nope >/dev/null 2>&1; expect_rc 2 $? "不明な --target は 2"

# 能力仕様が無いときは behavior にフォールバックする
rm -f "$R"/specs/rebuild/order.md "$R"/specs/rebuild/pay.md "$R"/specs/rebuild/sub/ship.md
printf -- '---\nspec-id: SPEC-behavior-login-01\ncoverage-status: verified\n---\n# login\n' > "$R/specs/behavior/login.md"
printf -- '---\nspec-id: TEMPLATE-DO-NOT-INDEX\n---\n' > "$R/specs/behavior/template.md"
"$H" "$R" >/dev/null 2>&1; expect_rc 0 $? "能力仕様が無ければ behavior で成功する"
grep -q 'specs/behavior（実装事実層' "$R/handoff/README.md" && [ "$(grep -c '^| `specs/behavior/[^|]*` | `SPEC' "$R/handoff/README.md")" -eq 1 ] \
  && ok "behavior へのフォールバックを明示し、雛形（TEMPLATE-DO-NOT-INDEX）を除く" || ng "behavior へのフォールバックが違う"

[ "$fail" -eq 0 ] && echo "handoff-test: PASS" || echo "handoff-test: FAIL"
exit "$fail"
