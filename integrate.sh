#!/bin/bash
#
# integrate.sh - 各ソースリポジトリからビルド成果物を収集し、統合 updates.xri を生成する
#
# 使い方: bash integrate.sh
#
# 前提: 各ソースリポジトリで事前にビルドスクリプトを実行済みであること
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ソースリポジトリの定義（パス:xriファイル名）
SOURCES=(
    "$HOME/projects/manual-image-solver/repository:updates.xri"
    "$HOME/projects/split-image-solver/repository:updates-split.xri"
)

echo "=== PixInsight スクリプト配信リポジトリ統合 ==="

# 1. 各リポジトリから zip をコピーし、<platform> ブロックを収集
ALL_PLATFORMS=""
COPIED=0

for SOURCE in "${SOURCES[@]}"; do
    REPO_DIR="${SOURCE%%:*}"
    XRI_FILE="${SOURCE##*:}"
    XRI_PATH="${REPO_DIR}/${XRI_FILE}"

    if [[ ! -f "${XRI_PATH}" ]]; then
        echo "スキップ: ${XRI_PATH} が見つかりません"
        continue
    fi

    # xri 内の全 zip fileName を取得
    ZIP_NAMES=$(sed -n 's/.*fileName="\([^"]*\.zip\)".*/\1/p' "${XRI_PATH}")

    if [[ -z "${ZIP_NAMES}" ]]; then
        echo "スキップ: ${XRI_PATH} に zip ファイルの参照がありません"
        continue
    fi

    # パッケージプレフィックスを取得（最初の zip 名から）
    FIRST_ZIP=$(echo "${ZIP_NAMES}" | head -1)
    PACKAGE_PREFIX=$(echo "${FIRST_ZIP}" | sed 's/-[0-9].*$//')

    # 全 zip をコピー
    for ZIP_NAME in ${ZIP_NAMES}; do
        ZIP_PATH="${REPO_DIR}/${ZIP_NAME}"
        if [[ ! -f "${ZIP_PATH}" ]]; then
            echo "警告: ${ZIP_PATH} が見つかりません（スキップ）"
            continue
        fi
        cp "${ZIP_PATH}" "${SCRIPT_DIR}/"
        echo "コピー: ${ZIP_NAME}"
    done

    # このパッケージの旧バージョン zip（xri に含まれないもの）を削除
    for OLD_ZIP in "${SCRIPT_DIR}/${PACKAGE_PREFIX}"-*.zip; do
        [[ -f "${OLD_ZIP}" ]] || continue
        BASENAME=$(basename "${OLD_ZIP}")
        if ! echo "${ZIP_NAMES}" | grep -qF "${BASENAME}"; then
            rm "${OLD_ZIP}"
            echo "削除: ${BASENAME}（旧バージョン）"
        fi
    done

    # <platform> ブロック全体を抽出（複数ブロック対応）
    PLATFORM_BLOCKS=$(awk '/<platform /,/<\/platform>/' "${XRI_PATH}")
    ALL_PLATFORMS="${ALL_PLATFORMS}
${PLATFORM_BLOCKS}"

    COPIED=$((COPIED + 1))
done

if [[ ${COPIED} -eq 0 ]]; then
    echo "エラー: 取り込むパッケージがありません"
    exit 1
fi

# 2. 統合 updates.xri を生成
cat > "${SCRIPT_DIR}/updates.xri" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<xri version="1.0">
   <description>
      <title>ysmr3104 PixInsight Scripts</title>
      <brief_description>PixInsight scripts by ysmr3104</brief_description>
   </description>
${ALL_PLATFORMS}
</xri>
XMLEOF

echo ""
echo "=== 統合完了 ==="
echo "  updates.xri に ${COPIED} 個のソースを統合しました"
echo ""
cat "${SCRIPT_DIR}/updates.xri"
