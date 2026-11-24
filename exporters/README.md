# exporters/ — 生成した仕様を、外の道具へ渡す

仕様生成（Phase 0〜4）が終わった仕様リポジトリ（`<source>-spec/`）に対して、**後から**実行する任意の道具を置く。
フレームワーク本体（手順書・`pipeline.md` / `playbook.md`・`gates.sh`・`init.sh`）はこの層を知らない。

> この層は fork（`sun-flat-yamada/reverse-spec-flow`）で追加したもの。upstream への還元は未定。

## handoff.sh — 仕様駆動ツールへの受け渡し

```bash
exporters/handoff.sh <仕様リポジトリ> [--target kiro|openspec|speckit|all] [--out <dir>] [--force]
```

再構築側で仕様駆動開発のツール（Kiro・OpenSpec・GitHub Spec Kit）を使うときに、`specs/` を正しく使わせるための素材を作る。

- **能力仕様**（`specs/rebuild/` 以下で、行頭に `artifact-key: capability-spec` の目印を持つもの。サブディレクトリも探す）を渡す単位にする。
  無ければ `specs/behavior/` を使い、そう明示する。雛形（`_*`・`TEMPLATE-DO-NOT-INDEX`）は除き、`coverage-status` が
  `out-of-scope` / `generated` のものは渡さずに一覧の「渡さなかった仕様」に理由（`scope-exclusion`）と並べる。
- **能力の一覧**（`README.md`）に、`coverage-status`・密度台帳の検証状態・UNKNOWN の件数と「渡してよいか」を出す。
  - 検証状態の正本は密度台帳（`spec-extraction/03-audit/density-ledger.tsv` の `verify_status`・`fabricated_open`）。front-matter の `verification:` は表示なので使わない。台帳が無い・行が無い能力は要注意。
  - UNKNOWN は `gates.sh` の G-FRESH と同じ規則で数える（`UNKNOWN[blocking]`・タグなしの `UNKNOWN:` を未決とし、HTML コメント内と取り消し線の「解消済」行を除く）。
  - 未決の UNKNOWN・partial・未検証ブロック・fabricated の残る能力は**要注意**として、再構築側で確定扱いしないよう促す。
- **共通規則**（`context.md`）を、各ツールの「常に読まれる場所」の形で出す。根拠（`[[SPEC-...]]`・`path:line`）を要求・設計・タスクに引き継ぐこと、
  `UNKNOWN` を推測で埋めずにそのツールの「未確定」の書き方に写すこと、未検証の仕様を確定扱いしないこと。
- **能力ごとの依頼文**（`<tool>/prompts.md`）を出す。要求の抽出と書式への変換は、各ツールの AI が `specs/` を読んで行う。
- `spec-extraction/03-audit/observed-anomalies.md`（仕様どおりに直すと壊れる箇所）も一緒に置くよう案内する。

**書式の機械変換はしない。** 各ツールの書式は変わりやすく、bash で要求を抽出すると根拠が落ちる。
**対象プロジェクトには書き込まない。** 出力を人が置く（既存の constitution や config を上書きしないため）。

**出力先の扱い。** 出力先には目録（`.handoff-generated`）を置き、再実行ではこの目録に載ったファイルだけを消して書き直す（利用者が足したファイルは残る）。
目録の無い空でないディレクトリは `--force` のときだけ使い、その場合も既存のファイルは上書きしない（衝突したら止まる）。
仕様リポジトリそのもの・`specs/` の中・`specs/` を持つディレクトリは、シンボリックリンク越しでも出力先にできない。

### 対応表

| ツール | 置くもの → 置き先 | 確認できた範囲（2026-11） | SUPPORT_LEVEL |
|---|---|---|---|
| Kiro | `kiro/.kiro/steering/reverse-spec.md` → `.kiro/steering/` | steering の置き場所と `inclusion: always`。spec の置き場所・書式は未確認 | `placed-unverified` |
| OpenSpec | `openspec/config-context.md` の本文 → `openspec/config.yaml` の `context: \|` ブロックの中に字下げして追記 | `context:` の注入、`### Requirement:` ＋ `#### Scenario:` と `openspec validate` | `placed-unverified` |
| GitHub Spec Kit | `speckit/constitution-addendum.md` → `.specify/memory/constitution.md` の末尾に追記 | constitution の置き場所、spec 雛形の書式（`FR-001`・`[NEEDS CLARIFICATION: …]`） | `placed-unverified` |

**`placed-unverified`** は、各ツールで「依頼文 → 生成物 → 根拠と UNKNOWN が残ったか」の往復を実測していないことを表す
（`hosts/README.md` と同じ規則。実測したら版・日付・回数を記録して更新する）。

検査: `exporters/handoff-test.sh`（品質ゲートで実行される）。
