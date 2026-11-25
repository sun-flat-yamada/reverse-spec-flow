# 実装計画: 凍結記録の履歴検査で、upstream から取り込んだ変更を区別する

C6（#6）で入れた「ハッシュ表を変えたら再凍結の履歴を足す」検査は、upstream の取り込み（`sync/upstream-*`）で
upstream 側がハッシュを変えた記録が入ると、fork が書いていない変更まで fork の違反として数え、ゲートが赤になる。
これを、fork の作業者が履歴を書き足さなくても正しく通るようにする（オーナーの指示 2026-11-25）。

## 方針
- **upstream の版の正本は fork の `main`（upstream のミラー）。** 参照名の解決は fork 固有なので `dev/fork-upstream-ref.sh` に置き、
  `selftest.sh` は「あれば呼ぶ」だけにする（upstream が同じ `selftest.sh` を使っても、このファイルが無ければ従来どおり全件を数える）。
- 版の変化（前の版 → 次の版）ごとに、変わった行がすべて「その版と upstream の合流点（`git merge-base <版> <upstream>`）にある記録」と
  一致していれば upstream から来たものとして数えない。upstream のコミットそのもの・取り込みの merge コミット・取り込み後の作業ツリーのいずれも、
  この規則で同じに扱える（内容で判定するので、日付順の並びや merge の形に依らない）。
- 履歴行も同じ規則で分ける: 増えた履歴行のうち upstream の記録にある行は fork の追記として数えない（upstream の追記で fork の変更を相殺させない）。
  消えた履歴行のうち、upstream 自身が消した行（upstream のどこかの版にあり、今の upstream に無い）は fork の違反にしない。
- 除外した回数は ok の文言に出す（黙って外さない）。

## 検証（selftest に足す）
- 使い捨てのリポジトリで `main`（upstream）と `custom`（fork）を作り、次を確かめる:
  upstream がハッシュだけ変えて merge で取り込む → 通る／取り込みと同じ PR で fork もハッシュを変えて履歴を書かない → 赤／
  upstream が履歴行を足しても fork のハッシュ変更は相殺されない → 赤／参照を渡さない → 従来どおり赤。
- `dev/fork-upstream-ref.sh` の解決順（`upstream/main` → `origin/main`）と、どちらも無いときに何も出さないこと。
- `./selftest.sh` が base より失敗を増やさない。別コンテキストの反証レビュー。`dev/fork-sync.md` に取り込み時の扱いを書く。
