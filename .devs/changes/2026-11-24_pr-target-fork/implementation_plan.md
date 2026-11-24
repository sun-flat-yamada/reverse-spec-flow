# 実装計画: PR の作成先を fork（sun-flat-yamada/reverse-spec-flow）に固定する

## 背景
fork では GitHub の既定の PR 作成先が親リポジトリ（upstream: aws-samples/sample-reverse-spec-flow）になる。
`gh pr create` / `gh pr list` / `gh pr close` は `--repo` を省くと fork の親を対象にするため、
`upstream-sync.yml` の取り込み PR が upstream に作られうる。人やエージェントが UI・CLI で PR を作るときも同じ。

## 変更
1. `.github/workflows/upstream-sync.yml` — `gh pr` の全呼び出しに `--repo "$GITHUB_REPOSITORY"` を付ける
2. `dev/fork-sync.md` / `dev/change-dev.md` / `CLAUDE.md` — PR の作成先は fork（base repository = sun-flat-yamada/reverse-spec-flow、base = fork/custom）と明記。
   upstream へ PR を出すのは還元を意図したときだけ（main から切ったブランチで、人の判断で）
3. `dev/change-dev-test.sh` ではなく、ワークフローの静的検査として `gh pr` 行に `--repo` があることを quality-gate で確かめる

## 検証
- quality-gate の静的検査が `--repo` の欠落を検出すること（欠落させた複製で確認）
- `dev/fork-sync-test.sh` / `dev/change-dev-test.sh`
