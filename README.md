# ysmr3104 PixInsight スクリプト配信リポジトリ

[ysmr3104](https://github.com/ysmr3104) が開発した PixInsight スクリプトの配信リポジトリです。PixInsight のアップデートシステム経由でインストールできます。

## 収録スクリプト

### Manual Image Solver

PixInsight 向け手動プレートソルバー。画像上の星を手動でクリックしてカタログ座標を入力することで、WCS ソリューションを計算します。Python 不要、PJSR ダイアログ内で全操作が完結します。

- ソース: [ysmr3104/manual-image-solver](https://github.com/ysmr3104/manual-image-solver)
- v1.4.1: PixInsight 1.9.3 以前（SpiderMonkey エンジン）
- v2.0.0: PixInsight 1.9.4 以降（V8 エンジン）

### Split Image Solver

広角星野写真向け自動プレートソルバー。画像をタイルに分割して各タイルを astrometry.net API またはローカル solve-field でソルブし、結果を統合して全体の WCS ソリューションを生成します。

- ソース: [ysmr3104/split-image-solver](https://github.com/ysmr3104/split-image-solver)
- v1.2.0: PixInsight 1.9.3 以前（SpiderMonkey エンジン）
- v2.0.0: PixInsight 1.9.4 以降（V8 エンジン）

## インストール方法

以下の URL を PixInsight のリポジトリリストに追加してください。

```
https://raw.githubusercontent.com/ysmrastro/pixinsight-scripts/main/updates.xri
```

**手順:**

1. PixInsight を開く
2. **Resources > Updates > Manage Repositories** を開く
3. **Add** をクリックし、上記 URL を入力して **OK**
4. **Resources > Updates > Check for Updates** を実行
5. インストールしたいスクリプトを選択して **Apply**

PixInsight のバージョンに応じて適切なパッケージ（SpiderMonkey版 / V8版）が自動的に配信されます。

---

## 開発者向け: リリース手順

このリポジトリは配信専用リポジトリです。スクリプトのソースコードは各リポジトリで管理し、ビルド成果物をここに統合します。

### リポジトリ構成

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

#### 1. ソースリポジトリでの作業

各スクリプトのソースリポジトリで変更・テスト・PR マージまで完了させます。

#### 2. スクリプトへの署名

PixInsight で **Script > Development > CodeSign** を開き、変更した `.js` ファイルに署名します。これにより `.xsgn` ファイルが更新されます。

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

ビルド後、各 `repository/` ディレクトリに ZIP と中間 XRI が生成されます。生成物はソースリポジトリにコミットします。

#### 4. 統合 XRI の生成

このリポジトリで `integrate.sh` を実行し、全スクリプトの配信情報を統合した `updates.xri` を生成します。

```bash
cd ~/projects/pixinsight-scripts
bash integrate.sh
```

各ソースリポジトリの ZIP が自動的にコピーされ、`updates.xri` が更新されます。

#### 5. updates.xri への署名

PixInsight で **Script > Development > CodeSign** を開き、生成された `updates.xri` に署名します。

署名対象:
```
/Users/ysmr/projects/pixinsight-scripts/updates.xri
```

#### 6. PR 作成・マージ・プッシュ

```bash
cd ~/projects/pixinsight-scripts
git checkout -b feature/<release-name>
git add updates.xri *.zip
git commit -m "リリース: <PackageName> v<VERSION>"
git push -u origin feature/<release-name>
gh pr create ...
gh pr merge --merge --delete-branch
```

### バージョン別配布の仕組み

`updates.xri` の `<platform version="最小:最大">` 属性により、PixInsight のバージョンに応じて適切なパッケージが自動配信されます。

| version 属性 | 対象 PixInsight | JavaScript エンジン |
|---|---|---|
| `1.8.9:1.9.3` | 〜 1.9.3 | SpiderMonkey |
| `1.9.4:9.9.9` | 1.9.4 〜 | V8 |

### 署名について

- 開発者 ID: `ysmr3104`
- 鍵ファイル: `~/Documents/PixInsight/ysmr3104.xssk`
- `.js` ファイルへの署名: Execute Script での実行に必要
- `updates.xri` への署名: Check for Updates でのリポジトリ検証に必要
- 中間ファイル（各ソースリポジトリ内の `updates*.xri`）への署名は不要
