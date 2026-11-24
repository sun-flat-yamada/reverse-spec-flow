# 実装計画: Claude 更新作業の運用（change-dev）と自動マージ

参照: `sun-flat-yamada/github-copilot-dashboard` の change-dev（Issue → 計画コミット → 品質ゲート → PR → Rebase Merge、`CHG_DEV_AUTO_PILOT`）。
本リポジトリは bash + Markdown・依存ゼロなので、Node スクリプトは移植せず bash と GitHub Actions で同等の効果を出す。

## 方針

- **自動マージは Actions 側で行う。** 参照は `change-dev:finish`（セッションから REST で承認・マージ）だが、
  クラウドセッションは GitHub CLI を使えないことがある。PR を ready にすれば、品質ゲート通過後に
  ワークフローが Rebase Merge する形にすれば、どのホスト（Claude Code ローカル／クラウド、他の AI ツール、人）からでも同じに動く。
- **Auto-Pilot の正本は `.github/change-dev.env` の `CHG_DEV_AUTO_PILOT`（既定 true）。** 上書き順は
  プロセス環境変数 → リポジトリ変数（Actions の vars）→ `.github/change-dev.env`。
- **計画先行（Plan First）を機械検査にする。** 実装ファイルに触れる前に `.devs/changes/<日付>_<slug>/implementation_plan.md`
  だけのコミットがあることを `dev/change-dev.sh plan-check` が確かめ、自動マージ前にも再検査する。
- **ブランチ名の改名規則は今回は移植しない。** クラウドセッションは割り当てブランチ以外へ push できないため
  （改名には毎回の許可が要る）。必要になったら別の変更で扱う。

## 変更するファイル

1. `dev/change-dev.sh` — `mode`（Auto-Pilot の解決と分岐の表示）、`plan-check [base]`
2. `dev/change-dev-test.sh` — フィクスチャでの検査（ネットワーク不使用）
3. `.github/change-dev.env` — `CHG_DEV_AUTO_PILOT=true`
4. `.github/workflows/quality-gate.yml` — `fork/custom` 向け PR と push で `selftest.sh`・fork-sync / change-dev のテスト・plan-check
5. `.github/workflows/auto-merge.yml` — 品質ゲート成功後、条件を満たす PR を head SHA 指定で Rebase Merge
6. `.github/pull_request_template.md` — 計画・検証・Closes の欄
7. `dev/change-dev.md` — 運用手順の正本。`CLAUDE.md` に要約節を追加

## 自動マージの条件（すべて満たすときだけ）

- base が `fork/custom`、head が同じリポジトリ、PR が draft でない
- Auto-Pilot が有効、`hold` ラベルが無い
- 品質ゲートが head SHA で成功している（`workflow_run` の head_sha と PR の head SHA が一致）
- `plan-check` が通る、マージ可能（衝突なし）
- ブランチ保護を迂回しない（必要承認があればマージせず止まる）

## 検証

- `dev/change-dev-test.sh`、`dev/fork-sync-test.sh`、`./selftest.sh`（既存の失敗件数が増えないこと）
- 別コンテキストのサブエージェントによる反証レビュー
