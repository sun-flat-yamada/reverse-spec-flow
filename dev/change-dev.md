# change-dev: fork/custom への変更の運用（Claude などの AI エージェント向け）

この fork（`fork/custom`）に変更を入れるときの手順。参照元は `sun-flat-yamada/github-copilot-dashboard` の change-dev で、
本リポジトリは bash + Markdown・依存ゼロなので、Node スクリプトの代わりに `dev/change-dev.sh` と GitHub Actions で同じ効果を出す。
ブランチ構成と upstream の取り込みは `dev/fork-sync.md` が正本。

> この文書は fork 固有の運用文書であり、フレームワーク本体（`init.sh` が配布するもの）には含まれない。

## 1. 流れ

```text
[1. Issue（任意）] → [2. 計画を単独コミット] → [3. 実装・品質ゲート] → [4. PR（fork/custom 向け）] → [5. CI 通過で自動 Rebase Merge]
```

| 段 | やること | 機械的な担保 |
|---|---|---|
| 1 | 複数セッションにまたがる作業・後で拾う作業は Issue にする（1 Issue = 1 PR の大きさ）。PR 本文に `Closes #N` | なし（任意） |
| 2 | `.devs/changes/<YYYY-MM-DD>_<slug>/implementation_plan.md` を書き、**それだけを 1 コミット**にしてから実装に入る | `dev/change-dev.sh plan-check`（品質ゲートと自動マージの直前で検査） |
| 3 | 実装。フレームワーク本体を変えたら CLAUDE.md の「完了の 4 条件」を守る（selftest・反証レビューなど） | `quality-gate.yml` |
| 4 | 作業ブランチを `fork/custom` から切り、`fork/custom` へ PR。本文は `.github/pull_request_template.md` に沿う | — |
| 5 | Auto-Pilot が有効なら、品質ゲート成功後に `auto-merge.yml` が Rebase Merge する | `auto-merge.yml` |

## 2. 計画先行（Plan First）

- 置き場所: `.devs/changes/<YYYY-MM-DD>_<slug>/implementation_plan.md`（進捗を残すなら同じ場所に `task.md`）。
- **計画ファイルだけのコミット**が、実装ファイルに触れる最初のコミットより前にあること。計画と実装を同じコミットに入れると違反。
- 免除: 変更が `docs/`・`README*`・`.devs/` だけのブランチ、`sync/upstream-*`（upstream 取り込み）、`dependabot/*`。
  `pipeline.md` / `playbook.md` などフレームワーク本体の `.md` は免除しない（本リポジトリの実装そのものなので）。
- 確認: `dev/change-dev.sh plan-check [base] [head-branch]`（既定 base は `origin/fork/custom`）。

## 3. Auto-Pilot（`CHG_DEV_AUTO_PILOT`）

| | 有効（true。本リポジトリの既定） | 無効（false） |
|---|---|---|
| 計画レビュー | 待たない。計画をコミットし、要約を報告して続行する（PR で再レビューされる） | 承認を待つ |
| PR | ready for review で作る | draft で作る |
| PR 作成後 | 品質ゲート成功で `auto-merge.yml` が Rebase Merge する | 人がマージする |

解決順（先に値があったものを使う）: 環境変数（Actions ではリポジトリ変数 `CHG_DEV_AUTO_PILOT`）→ `.env`（git 管理外）→ `.github/change-dev.env`。
現在値は `dev/change-dev.sh mode` で確認できる。

**自動マージを一時的に止める**: PR に `hold` ラベルを付ける／PR を draft に戻す／リポジトリ変数 `CHG_DEV_AUTO_PILOT=false` を置く（全体停止）。
`hold` を外す・draft を解除すると品質ゲートが走り直し、成功すれば自動マージの判定に戻る。

## 4. 自動マージの条件（`auto-merge.yml`）

品質ゲート（`.github/workflows/quality-gate.yml`）が完了したとき、次を**すべて**満たす PR だけを Rebase Merge する。
満たさない PR はマージせず、理由をジョブのログに残す（人がマージするか、直して push する）。

1. 品質ゲートが成功し、PR の現在の head SHA がゲートを通った SHA と同じ（後から push された未検査のコミットをマージしない）。
   ゲートは**ファイルパスで**特定する（同名の別ワークフローでは発火しない）
2. base が `fork/custom`、head が同じリポジトリのブランチ、PR が draft でない、`hold` ラベルが無い
3. Auto-Pilot が有効（**既定ブランチ側の設定**で判定する。PR が自分の設定ファイルを書き換えても効かない）
4. **ゲートや検査に関わるファイルを変えていない**（`.github/`・`selftest.sh`・`dev/*.sh`）。
   品質ゲートは `pull_request` の仕様で **PR 側の定義**で走るので、ゲートを変える PR は変更後のゲートで自分を通せてしまう。こうした PR は人がマージする
5. `sync/upstream-*`・`dependabot/*` ブランチでない。merge コミットを含まない（Rebase Merge は merge コミットを落とし、
   upstream との祖先関係が切れて次回の取り込みが重複する。upstream の取り込み PR は人が **merge コミットで**マージする）
6. head が最新の `fork/custom` を含む（base が進んだ後の組み合わせは未検査なので、遅れていれば `fork/custom` へ rebase して push し直す）
7. 衝突が無い（`mergeable=true`）
8. 計画先行の検査が通る（**既定ブランチ側の `change-dev.sh`** で PR の履歴を検査する）
9. マージは head SHA を指定した REST 呼び出しで行い、ブランチ保護を迂回しない（必要承認があれば GitHub が拒否し、ジョブが失敗として残る）

**`GITHUB_TOKEN` でマージした結果の push では、他のワークフローは起動しない**（GitHub の仕様）。`fork/custom` への push で動く検査は、
自動マージの後には走らない。PR の時点で検査済みなので通常は問題にならない。

## 5. AI エージェント（Claude Code など）の振る舞い

- 作業ブランチは `fork/custom` から切る。クラウドセッションでは割り当てられたブランチをそのまま使う（改名しない）。
- Auto-Pilot 有効時、PR は **ready for review** で作る（クラウドの既定「draft で作る」より、この文書を優先する）。
  マージはワークフローが行うので、エージェントは PR を ready にした後、CI の失敗やレビュー指摘があれば直す。
- CI が赤なら原因を直して push する。テストを無効化・削除して緑にしない。
- 前の PR が Rebase Merge されたら、作業ブランチを最新の `fork/custom` から作り直してから次の変更に入る
  （Rebase Merge はコミットの SHA を変えるので、古いブランチの履歴は `fork/custom` の祖先にならない）。
  次の変更には**新しい計画ファイル**が要る（`fork/custom` に既にある計画は数えない）。
- `fork/custom` が先に進んだら、merge ではなく **rebase** で追従して push する（merge コミットを含む PR は自動マージしない）。
- ゲート・検査・ワークフローを変える PR（§4 の 4）は自動マージされない。マージは人に依頼する。

## 6. 初期設定（リポジトリ設定。人が一度だけ行う）

`dev/fork-sync.md` §3 に加えて:

| # | 設定 | 場所 | 理由 |
|---|---|---|---|
| 1 | Rebase merge と Merge commit の両方を許可する | Settings › General › Pull Requests | `auto-merge.yml` は rebase でマージし、upstream の取り込み PR は merge コミットでマージする |
| 2 | 「Automatically delete head branches」をオンにする | 同上 | マージ済みブランチを GitHub が削除する（クラウドセッションからはブランチを削除できない） |
| 3 | `hold` ラベルを作る（任意） | Issues › Labels | 自動マージを PR 単位で止めるため |
| 4 | Workflow permissions を「Read and write」にする | Settings › Actions › General | `auto-merge.yml` がマージするため（ワークフロー側でも `contents: write` を宣言している） |

## 7. 参照元との違い

| 参照元（github-copilot-dashboard） | 本リポジトリ | 理由 |
|---|---|---|
| `change-dev:finish`（セッションが REST で承認・マージ） | `auto-merge.yml`（Actions がマージ） | どのホストから PR を作っても同じに動く。セッションに GitHub CLI が無くてもよい |
| 兄弟 worktree で作業 | 作業ブランチ（クラウドはセッションのブランチ） | 単独作業が中心。並行作業時は `git worktree` を使ってよい |
| ブランチ名 `<type>/<issue>-<slug>` の強制と改名 | 強制しない | クラウドセッションは割り当てブランチ以外へ push できず、改名に毎回の許可が要る |
| 品質ゲート = npm の 5 検査 | `selftest.sh` ＋ `dev/*-test.sh` ＋ plan-check | bash + Markdown・依存ゼロ |
