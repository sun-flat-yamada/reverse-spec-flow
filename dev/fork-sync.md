# fork 運用と upstream 取り込み

このリポジトリ（`sun-flat-yamada/reverse-spec-flow`）は
[`aws-samples/sample-reverse-spec-flow`](https://github.com/aws-samples/sample-reverse-spec-flow)（以下 upstream）の fork である。
upstream の更新をいつでも無衝突に近い形で取り込めるよう、**ミラー＋独自ブランチの二本立て**で運用する。

> この文書は fork 固有の運用文書であり、フレームワーク本体（`init.sh` が配布するもの）には含まれない。

## 1. ブランチ構成

```text
[upstream: aws-samples/sample-reverse-spec-flow]
  main ───●───●───●
          │       │  fast-forward のみ
          ▼       ▼
[fork: sun-flat-yamada/reverse-spec-flow]
  main ───●───●───●            upstream のミラー（独自コミットを置かない）
          │       │
          ▼       ▼  merge（sync/upstream-<sha> 経由の PR）
  fork/custom ──■──■──▲──■     独自変更。既定ブランチ。Claude の PR はここへ向ける
```

| ブランチ | 役割 | 動かし方 |
|---|---|---|
| `main` | upstream `main` のミラー | `dev/fork-sync.sh sync --push` による fast-forward **だけ**。直接コミット・PR マージをしない |
| `fork/custom` | fork 独自の変更（運用整備・改善）。**既定ブランチ** | 作業ブランチからの PR、および `sync/upstream-<sha>` からの PR |
| `sync/upstream-<sha>` | 取り込み用の一時ブランチ | `fork-sync.sh` が `fork/custom` から切って upstream を merge する。PR マージ後に削除 |
| 作業ブランチ（`claude/…` など） | 個々の変更 | `fork/custom` から切り、`fork/custom` へ PR |

**原則**

1. `main` に upstream に無いコミットを置かない。`fork-sync.sh` は `main` が 1 件でも先行していると止まる（exit 2）。
2. 独自変更はすべて `fork/custom` に積む。取り込みは常に「`main` を fast-forward → `fork/custom` に merge」の順。
3. upstream へ還元したい変更は `main`（＝upstream と同一）から切ったブランチで作り、upstream へ PR を出す。
   `fork/custom` から切ると fork 独自の変更が混ざる。

## 2. 自動取り込み（GitHub Actions）

`.github/workflows/upstream-sync.yml` が毎週月曜 09:00 JST（と手動実行）に次を行う。

1. `dev/fork-sync.sh sync --push` を実行する。
   - `main` が upstream より遅れていれば、upstream の SHA へ fast-forward して push する（`fork/custom` の状態とは独立。merge が衝突しても `main` は進める）。
   - `fork/custom` が upstream を取り込み済みなら、ここで終わる。
   - 未取り込みなら `sync/upstream-<sha>` に `fork/custom` + upstream の merge を作って push する。
     **origin に同名のブランチが既にあれば作り直さない**（PR 上で積んだレビュー修正を上書きしない）。
2. `sync/upstream-<sha>` → `fork/custom` の PR を開く（同じブランチの PR が既にあれば開かない）。
   それより古い `sync/upstream-*` の PR は、新しい PR に含まれるので閉じる。
3. 取り込み PR は**人が「Create a merge commit」でマージする**（自動マージの対象外。`dev/change-dev.md` §4）。
   Rebase / Squash でマージすると upstream のコミットが別 SHA になり、upstream が `fork/custom` の祖先でなくなって次回の取り込みが重複する。

merge が衝突したときはジョブが失敗する（exit 3。GitHub から失敗通知が届く）。このとき `main` は fast-forward 済みで、
sync ブランチは作られていない。§4 の手順で手で解消する。

**upstream が `.github/workflows/` を追加・変更すると、`GITHUB_TOKEN` では push が拒否される。**
GitHub はワークフローファイルを変える push に `workflows` 権限を要求し、`GITHUB_TOKEN` にはそれを付与できない。
その時点から同期ジョブが毎週失敗するので、workflow 権限を持つ fine-grained PAT（Contents・Pull requests・Workflows の read/write）
か GitHub App のトークンを secret `SYNC_TOKEN` に登録する（ワークフローは `SYNC_TOKEN` があればそれを使う）。
現時点（2026-11-24）の upstream は `.github/` を持たないので未発生。

**注意: `GITHUB_TOKEN` で作った PR では、他のワークフロー（CI）が起動しない。**
これは GitHub の仕様（ワークフローの連鎖を防ぐため）。取り込み PR に CI を走らせたい場合は、
PR を一度 close → reopen するか、`GITHUB_TOKEN` の代わりに GitHub App / PAT のトークンを使う。

## 3. 初期設定（リポジトリ設定。人が一度だけ行う）

| # | 設定 | 場所 | 理由 |
|---|---|---|---|
| 1 | 既定ブランチを `fork/custom` にする | Settings › General › Default branch | `schedule:` は**既定ブランチにある定義**しか実行しない。`main` が既定のままだと同期ワークフローが一度も走らない |
| 2 | Actions に PR 作成を許可する | Settings › Actions › General › Workflow permissions › 「Allow GitHub Actions to create and approve pull requests」 | 取り込み PR を `GITHUB_TOKEN` で開くため |
| 3 | `main` を保護する場合は fast-forward の push を妨げない設定にする | Settings › Rules | 「PR 必須」にすると同期ジョブの `main` push が拒否される。保護するなら「force push 禁止・削除禁止」に留める |

| 4 | Actions を有効にする | Actions タブ | fork では Actions が既定で無効になっている |
| 5 | （任意）secret `SYNC_TOKEN` を登録する | Settings › Secrets and variables › Actions | §2 の `.github/workflows/` 問題への備え。PAT や App のトークンで作った PR では CI も起動する |

**公開リポジトリの `schedule:` は、リポジトリに 60 日間活動が無いと自動で無効になる。** upstream が静かな期間が続くと
同期ジョブ自身は何も push しないので止まりうる。Actions タブに無効化の表示が出たら再度有効にする。

`fork/custom` ブランチは 2026-11-24 に upstream `v2.2.1`（`main` と同一）から作成済み。

## 4. 手動での取り込み・衝突時

```bash
dev/fork-sync.sh check          # 状態を見るだけ。exit 0=同期済み / 10=取り込み待ちあり / 2=前提違反
dev/fork-sync.sh sync           # ローカルに sync/upstream-<sha> を作る（push しない）
dev/fork-sync.sh sync --push    # main の fast-forward と sync ブランチを origin へ push する
```

`upstream` remote が無ければ自動で追加する（URL は `UPSTREAM_URL` で上書き可）。作業ツリーは汚さない（一時 worktree で merge する）。

**衝突したとき（exit 3）**

```bash
git fetch upstream main && git fetch origin fork/custom
git switch -c sync/upstream-manual origin/fork/custom
git merge upstream/main          # 衝突を解消して commit
./selftest.sh                    # 本体に手を入れたので必ず通す
git push -u origin sync/upstream-manual   # fork/custom 向けに PR を作る
git push origin upstream/main:main        # main の fast-forward（sync --push 済みなら不要。check が 0 になるまでが完了）
```

衝突の解消では **upstream 側の変更を優先**し、fork 独自の変更をその上に載せ直すのを基本にする
（upstream の構造に追従しておくほど次回の取り込みが軽くなる）。

## 5. 衝突を減らすための書き方

- fork 独自の運用（CI・自動マージ・この文書など）は、upstream が持たないパス（`.github/`、`dev/fork-*`）に置く。
- upstream と共有するファイル（`CLAUDE.md`・`README*`・`selftest.sh` など）を変えるときは、既存行の書き換えより**節の追加**を選ぶ。
- フレームワーク本体の改善は、可能なら upstream へ還元して `main` 経由で戻ってくる形にする（fork 側の差分が減る）。
