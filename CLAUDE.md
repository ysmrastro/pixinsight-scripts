# CLAUDE.md

**アカウント方針・PJSR コーディング規約・配布フローの全体像は、上位の [`../CLAUDE.md`](../CLAUDE.md) を参照してください。** ここにはこのリポジトリ固有の内容のみを書きます。

---

## このリポジトリの役割

PixInsight スクリプトの**配信専用リポジトリ**です。スクリプトのソースコードは各リポジトリ（`ysmr3104/*`）で管理し、ビルド成果物（zip）と統合 `updates.xri` をここに集約します。

ユーザーが PixInsight のリポジトリリストに追加する URL:

```
https://ysmrastro.github.io/pixinsight-scripts/
```

GitHub Pages で配信しています。

## リリース手順

`README.md` の「開発者向け: リリース手順」に手順を記載しています。作業時はそちらを参照してください。

要点だけ挙げると:

1. ソースリポジトリで変更・テスト・PR マージまで完了させる
2. PixInsight の **Script > Development > CodeSign** で `.js` に署名する
3. ソースリポジトリで `build-*.sh` を実行し、`repository/` に zip と中間 XRI を生成してコミットする
4. このリポジトリで `integrate.sh` を実行し、統合 `updates.xri` を生成する
5. CodeSign で `updates.xri` に署名する
6. PR を作成してマージする

## 署名

- 開発者 ID: `ysmr3104`（CPD 登録済み・署名運用中）
- 鍵ファイル: `~/Documents/PixInsight/ysmr3104.xssk`
- `.js` ファイルへの署名: Execute Script での実行に必要
- `updates.xri` への署名: Check for Updates でのリポジトリ検証に必要
- 中間ファイル（各ソースリポジトリ内の `updates*.xri`）への署名は不要

## integrate.sh の保守

`integrate.sh` はソースリポジトリのパスを `SOURCES` 配列でハードコードしています。**新しいスクリプトを追加したら、この配列への追記が必要**です。

```bash
SOURCES=(
    "$HOME/projects/pixinsight/manual-image-solver/repository:updates.xri"
    "$HOME/projects/pixinsight/split-image-solver/repository:updates-split.xri"
)
```

パスは `~/projects/pixinsight/` 配下を前提としています。リポジトリの配置を変える場合はここも更新してください。

## バージョン別配布

`updates.xri` の `<platform version="最小:最大">` 属性により、PixInsight のバージョンに応じたパッケージが自動配信されます。

| version 属性 | 対象 PixInsight | JavaScript エンジン |
|---|---|---|
| `1.8.9:1.9.3` | 〜 1.9.3 | SpiderMonkey |
| `1.9.4:9.9.9` | 1.9.4 〜 | V8 |

既存 2 本（ManualImageSolver / SplitImageSolver）は両エンジン向けに 2 パッケージを配信しています。これは SpiderMonkey で書いたものを V8 に移植した経緯によるものです。新規スクリプトで両対応するかはスクリプトごとに判断してください（MeteorComposer は V8 専用と決定済み）。

## 収録スクリプト

| スクリプト | ソース | 状況 |
|---|---|---|
| ManualImageSolver | [ysmr3104/manual-image-solver](https://github.com/ysmr3104/manual-image-solver) | v1.4.1 (SpiderMonkey) / v2.0.0 (V8) |
| SplitImageSolver | [ysmr3104/split-image-solver](https://github.com/ysmr3104/split-image-solver) | v1.2.0 (SpiderMonkey) / v2.0.0 (V8) |
| MeteorComposer | [ysmr3104/meteor-composer](https://github.com/ysmr3104/meteor-composer) | 開発中（Phase 1 完成時に公開予定） |

MeteorComposer の公開時には、既存 2 本の `#feature-id` も `ysmrastro` カテゴリへの同時掲載に変更する予定です。詳細は meteor-composer の `docs/requirements.md` 8.3 を参照。
