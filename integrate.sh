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

# 1. 各リポジトリから zip をコピーし、package 要素を収集
PACKAGES=""
COPIED=0

for SOURCE in "${SOURCES[@]}"; do
    REPO_DIR="${SOURCE%%:*}"
    XRI_FILE="${SOURCE##*:}"
    XRI_PATH="${REPO_DIR}/${XRI_FILE}"

    if [[ ! -f "${XRI_PATH}" ]]; then
        echo "スキップ: ${XRI_PATH} が見つかりません"
        continue
    fi

    # xri から fileName を取得
    ZIP_NAME=$(sed -n 's/.*fileName="\([^"]*\)".*/\1/p' "${XRI_PATH}")
    ZIP_PATH="${REPO_DIR}/${ZIP_NAME}"

    if [[ ! -f "${ZIP_PATH}" ]]; then
        echo "スキップ: ${ZIP_PATH} が見つかりません"
        continue
    fi

    # 同じパッケージの旧バージョン zip を削除
    PACKAGE_PREFIX=$(echo "${ZIP_NAME}" | sed 's/-[0-9].*$//')
    for OLD_ZIP in "${SCRIPT_DIR}/${PACKAGE_PREFIX}"-*.zip; do
        if [[ -f "${OLD_ZIP}" && "$(basename "${OLD_ZIP}")" != "${ZIP_NAME}" ]]; then
            rm "${OLD_ZIP}"
            echo "削除: $(basename "${OLD_ZIP}")（旧バージョン）"
        fi
    done

    # zip をコピー
    cp "${ZIP_PATH}" "${SCRIPT_DIR}/"
    echo "コピー: ${ZIP_NAME}"

    # package 要素を抽出（<package> から </package> まで）
    # 元 xri のインデント（6スペース）を維持してそのまま使用
    PACKAGE=$(sed -n '/<package /,/<\/package>/p' "${XRI_PATH}")
    PACKAGES="${PACKAGES}
${PACKAGE}"

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
   <platform os="all" arch="noarch" version="1.8.9:9.9.9">
${PACKAGES}
   </platform>
</xri>
XMLEOF

echo ""
echo "=== 統合完了 ==="
echo "  updates.xri に ${COPIED} 個のパッケージを統合しました"
echo ""
cat "${SCRIPT_DIR}/updates.xri"
