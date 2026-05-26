# ysmr3104 PixInsight Scripts

PixInsight scripts by [ysmr3104](https://github.com/ysmr3104), distributed via the PixInsight Update System.

## Scripts

### Manual Image Solver

Manual plate solver for PixInsight. Interactively identify stars on your image, enter their catalog coordinates, and compute a full WCS solution — all within a native PJSR dialog, no Python required.

- Source: [ysmr3104/manual-image-solver](https://github.com/ysmr3104/manual-image-solver)
- v1.4.1: PixInsight ≤ 1.9.3 (SpiderMonkey runtime)
- v2.0.0: PixInsight ≥ 1.9.4 (V8 runtime)

### Split Image Solver

Automatic plate solver for wide-field images. Splits the image into tiles, solves each tile via astrometry.net API or local solve-field, and merges the results into a single WCS solution.

- Source: [ysmr3104/split-image-solver](https://github.com/ysmr3104/split-image-solver)
- v1.2.0: PixInsight ≤ 1.9.3 (SpiderMonkey runtime)
- v2.0.0: PixInsight ≥ 1.9.4 (V8 runtime)

## Installation

Add the following URL to PixInsight's update repository list:

```
https://raw.githubusercontent.com/ysmrastro/pixinsight-scripts/main/updates.xri
```

**Steps:**

1. Open PixInsight
2. Go to **Resources > Updates > Manage Repositories**
3. Click **Add**, enter the URL above, and click **OK**
4. Go to **Resources > Updates > Check for Updates**
5. Select the scripts you want to install and click **Apply**

PixInsight will automatically serve the appropriate version for your installation (SpiderMonkey or V8).

---

## 開発者向け: リリース手順

このリポジトリは配信専用リポジトリです。スクリプトのソースコードは各リポジトリで管理し、ビルド成果物をここに統合します。

### 構成

```
pixinsight-scripts/
├── updates.xri                    # 統合配信 XRI（署名済み）
├── integrate.sh                   # 統合スクリプト
├── ManualImageSolver-1.4.1.zip    # SpiderMonkey版
├── ManualImageSolver-2.0.0.zip    # V8版
├── SplitImageSolver-1.2.0.zip     # SpiderMonkey版
└── SplitImageSolver-2.0.0.zip     # V8版
```

### リリースフロー

新バージョンをリリースする際の手順です。

#### 1. ソースリポジトリでの作業

各スクリプトのソースリポジトリで変更・テスト・PR マージまで完了させます。

```bash
# manual-image-solver の場合
cd ~/projects/manual-image-solver

# split-image-solver の場合
cd ~/projects/split-image-solver
```

#### 2. スクリプトへの署名

PixInsight で Script > Development > CodeSign を開き、変更した `.js` ファイルに署名します。これにより `.xsgn` ファイルが更新されます。

#### 3. 配布パッケージのビルド

各ソースリポジトリでビルドスクリプトを実行します。

```bash
# ManualImageSolver
cd ~/projects/manual-image-solver
bash build-release.sh

# SplitImageSolver
cd ~/projects/split-image-solver
bash build-split-release.sh
```

ビルド後、各 `repository/` ディレクトリに以下が生成されます：
- `<PackageName>-<VERSION>.zip` — V8版配布パッケージ
- `updates*.xri` — プラットフォーム別配信 XRI（未署名）

生成物はソースリポジトリにコミットします。

#### 4. 統合 XRI の生成

このリポジトリで `integrate.sh` を実行し、全スクリプトの `<platform>` ブロックを統合した `updates.xri` を生成します。

```bash
cd ~/projects/pixinsight-scripts
bash integrate.sh
```

各ソースリポジトリの zip が自動的にこのリポジトリにコピーされ、`updates.xri` が更新されます。

#### 5. updates.xri への署名

PixInsight で Script > Development > CodeSign を開き、生成された `updates.xri` に署名します。

署名対象ファイル:
```
/Users/ysmr/projects/pixinsight-scripts/updates.xri
```

#### 6. コミット・プッシュ

```bash
cd ~/projects/pixinsight-scripts
git add updates.xri *.zip
git commit -m "リリース: <PackageName> v<VERSION>"
git push
```

### バージョン別配布の仕組み

`updates.xri` の `<platform version="最小:最大">` 属性により、PixInsight のバージョンに応じて自動的に適切なパッケージが配信されます。

| version 属性 | 対象 PixInsight | エンジン |
|---|---|---|
| `1.8.9:1.9.3` | 〜 1.9.3 | SpiderMonkey |
| `1.9.4:9.9.9` | 1.9.4 〜 | V8 |

### 署名について

- 開発者 ID: `ysmr3104`
- 鍵ファイル: `~/Documents/PixInsight/ysmr3104.xssk`
- `.js` ファイル（スクリプト本体）への署名は、ユーザーが Execute Script で実行する際に必要
- `updates.xri` への署名は、PixInsight が Check for Updates でリポジトリを検証する際に必要
- 中間ファイル（各ソースリポジトリの `updates*.xri`）への署名は不要
