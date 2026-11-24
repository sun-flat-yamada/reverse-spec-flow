# OpenAI Codex — セッションを開く前に済ませること

このリポジトリを Codex で開いて作業する前に、**人が 1 回だけ**確かめる手順。
**この harness は何も実測していない**（フレームワーク側の `hosts/codex/MEASURED.md`。このファイルは `HOST-SETUP.md` として
生成先に写されるので、相対パスでは辿れない）。確かめた結果はフレームワークへ還元する。

## 1. リポジトリのルートで開く

```bash
cd <このリポジトリのルート>   # spec-extraction/ や specs/ ではなく
codex
```

skill は `.agents/skills/` に置いてある（`density-verify` / `spec-adversarial-audit`）。Codex は作業ディレクトリから
リポジトリのルートまでの `.agents/skills` を探す（文書による）。`ls .agents/skills/` の各ディレクトリが skill の一覧に出ることを確かめる。

## 2. 規範が切り詰められないようにする

Codex はルートから作業ディレクトリまでの `AGENTS.md` を連結して読み、合計が `project_doc_max_bytes`（既定 32 KiB）を
超えると**末尾が黙って落ちる**（解説による。未実測）。ルートの `AGENTS.md` は小さいが、`spec-extraction/AGENTS.md` は大きい。
**`spec-extraction/` で開く場合**は、合計を確かめ、超えるなら自分の Codex の設定で上限を上げる:

```bash
wc -c AGENTS.md spec-extraction/AGENTS.md   # 合計を確かめる
```

```toml
# ~/.codex/config.toml（キー名と置き場所は使っている版の文書で確かめる）
project_doc_max_bytes = 65536
```

上限はリポジトリからは入れない（利用者の設定であり、版で変わりうる）。**ルートで開いていれば不要。**

## 3. 検証官の隔離は縮退で行う

このホストでは、検証官の読み取りを解析対象の配下に機械で制限する手段を確かめていない（`HOST.md` §5）。
密度ブロックの Verify・高影響宣言の反証は、通常のサブエージェントで行って台帳に `prompt-isolated` と残すか（`HOST.md` §5）、隔離を確かめたホストで行う。

## 4. 別のホストへ切り替えたら

`.agents/skills/` は Agent Skills を読む他のツールも探す場所なので、codex から別のホストへ切り替えたら消す（古い写しが読まれうる）。
