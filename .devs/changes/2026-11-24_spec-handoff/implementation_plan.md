# 実装計画: C1 仕様の受け渡しアダプタ（handoff）

改善候補レビュー（2026-11）の C1。生成した `specs/` を、再構築側の仕様駆動ツール（GitHub Spec Kit・OpenSpec・Kiro）へ渡す。

## 方針
- **本体（手順書・GP/SB・gates.sh・init.sh）は変えない。** 仕様生成が終わった仕様リポジトリに対して後から実行する任意の道具として
  `exporters/handoff.sh` を置く（hosts/・playbooks/ と同じく交換可能な層。依存ゼロの bash）。
- **書式の機械変換はしない。** 各ツールの書式は変わりやすく、2026-11 時点で確認できたのは一部だけ
  （Kiro steering の frontmatter `inclusion`、OpenSpec `openspec/config.yaml` の `context:`、Spec Kit の `.specify/memory/`）。
  変換を AI に任せる代わりに、**引用（path:line）・UNKNOWN・検証状態を落とさないための規則**を各ツールの「常に読まれる場所」へ置く素材と、
  能力ごとの依頼文（プロンプト）を作る。要求の抽出は各ツールの AI が `specs/` を読んで行う。
- **対象プロジェクトには書き込まない。** 出力は `--out`（既定 `<仕様リポジトリ>/handoff/`）に置き、人がコピーする（既存の constitution や config を上書きしない）。
- 確かさを誇張しない: 出力の README に各ツールについて「確認できた範囲」を書き、`SUPPORT_LEVEL=placed-unverified` 相当と明記する。

## 出力
- `handoff/README.md` — 能力（`specs/rebuild/*.md`。無ければ `specs/behavior/*.md`）の一覧: spec-id・coverage-status・verification・UNKNOWN 件数（種別ごと）・blocking の有無
- `handoff/context.md` — 共通規則（specs/ が既存挙動の正本、`[[SPEC-...]]` と path:line を設計・タスクに引き継ぐ、UNKNOWN は推測で埋めず質問か NEEDS CLARIFICATION にする、draft/unverified は確定扱いしない）
- `handoff/kiro/.kiro/steering/reverse-spec.md`（`inclusion: always`）・`handoff/kiro/prompts.md`
- `handoff/openspec/config-context.yaml`（`context:` に貼る断片）・`handoff/openspec/prompts.md`
- `handoff/speckit/constitution-addendum.md`・`handoff/speckit/prompts.md`

## 検証
- `exporters/handoff-test.sh`: フィクスチャの仕様リポジトリで、件数・UNKNOWN 集計・テンプレート除外・既存出力の扱い・対象外の入力の拒否を検査
- quality-gate に組み込む。`./selftest.sh` が既存の失敗から増えないこと
- 別コンテキストの反証レビュー
