#!/bin/bash
#
# sign.sh - ダイアログを開かずにスクリプトと updates.xri に署名する
#
# 使い方:
#   tools/sign.sh <対象パス> [<対象パス> ...]
#
# 対象は PixInsight が入っているマシン上の絶対パスです。拡張子で処理が
# 分かれます。
#
#   .js / .scp  ->  隣に .xsgn を生成する（#feature-id を持つものだけ）
#   .xri        ->  ファイル自体に署名を埋め込む（書き換わる）
#
# 例:
#   tools/sign.sh '~/projects/pixinsight/meteor-composer/javascript/MeteorComposer.js'
#   tools/sign.sh '~/projects/pixinsight/pixinsight-scripts/updates.xri'
#
# ~ を含むパスはシングルクォートで囲んでください。展開は署名機側で行います
# （編集機と署名機でユーザー名が違うため）。
#
# --- パスワードの持ち方 ------------------------------------------------------
#
# 既定は macOS の Keychain です。GCP の Secret Manager に相当するもので、
# 保存時に暗号化され、ログインセッションで復号されます。登録は一度だけ、
# 署名機の上で自分で行います。作業を自動化する側（人でも道具でも）は
# パスワードを一度も見ません。
#
#   security add-generic-password -U \
#       -s pixinsight-signing -a ysmr3104 \
#       -D "PixInsight signing keys password" -w
#
# -w を値なしで渡すと対話的に入力を求められ、画面にも履歴にも残りません。
#
# 重要 — Keychain を使う場合、このスクリプトは署名機のターミナルから
# 実行してください（PI_SIGN_HOST=local）。ssh 経由では読めません。
#
# ssh セッションは GUI ログインセッションのセキュリティ文脈に属さないため、
# ログインキーチェーンへのアクセスが拒否されます。ロックの問題ではなく、
# show-keychain-info すら通りません。実測:
#
#   $ ssh <署名機> security show-keychain-info ~/Library/Keychains/login.keychain-db
#   security: SecKeychainCopySettings ...: User interaction is not allowed.
#   $ ssh <署名機> security find-generic-password -w -s ... -a ...
#   終了コード 36
#
# 回避するには security unlock-keychain -p <ログインパスワード> が必要で、
# 「パスワードを知らずに済ませる」という目的と矛盾します。ssh から駆動したい
# 場合は PI_SIGN_FILE を使ってください（保存時の保護は落ちます）。
#
# --- 環境変数 ----------------------------------------------------------------
#
#   PI_SIGN_HOST      PixInsight が入っているホスト（既定: mbp4ysmr）
#                     署名機の上で直接動かすなら PI_SIGN_HOST=local
#   PI_SIGN_KEYS      署名鍵ファイル
#                     （既定: ~/Documents/PixInsight/ysmr3104.xssk）
#   PI_SIGN_SERVICE   Keychain のサービス名（既定: pixinsight-signing）
#   PI_SIGN_ACCOUNT   Keychain のアカウント名（既定: ysmr3104）
#   PI_SIGN_FILE      これを指定すると Keychain ではなくこのファイルから
#                     パスワードを読む。Keychain が使えない環境向けの退路で、
#                     平文なので 600 と暗号化ディスクが前提
#   PI_SIGN_ENTITLEMENTS  カンマ区切り。既定は無し
#
# 鍵ファイルとパスワードの両方を取られると、その開発者 ID として署名できて
# しまいます。Keychain を既定にしているのはそのためです。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HOST="${PI_SIGN_HOST:-mbp4ysmr}"
PI_APP="/Applications/PixInsight/PixInsight.app/Contents/MacOS/PixInsight"
REPORT="/tmp/pixinsight-sign-report.txt"

if [[ $# -eq 0 ]]; then
    echo "使い方: tools/sign.sh <対象パス> [...]" >&2
    exit 2
fi

remote() {
    if [[ "$HOST" == "local" ]]; then
        bash -c "$1"
    else
        # shellcheck disable=SC2029  # 展開はリモートで行わせたい
        ssh "$HOST" "$1"
    fi
}

KEYS="${PI_SIGN_KEYS:-~/Documents/PixInsight/ysmr3104.xssk}"

if [[ -n "${PI_SIGN_FILE:-}" ]]; then
    PASSWORD_JSON="{\"file\": \"${PI_SIGN_FILE}\"}"
else
    PASSWORD_JSON="{\"keychain\": {\"service\": \"${PI_SIGN_SERVICE:-pixinsight-signing}\", \"account\": \"${PI_SIGN_ACCOUNT:-ysmr3104}\"}}"
fi

ENTITLEMENTS_JSON="[]"
if [[ -n "${PI_SIGN_ENTITLEMENTS:-}" ]]; then
    ENTITLEMENTS_JSON="[$(echo "$PI_SIGN_ENTITLEMENTS" \
        | awk -F, '{for(i=1;i<=NF;++i) printf "%s\"%s\"", (i>1?",":""), $i}')]"
fi

# パスに " を含めさせない。JSON を組み立てるので素通しにはできない。
TARGETS_JSON=""
for t in "$@"; do
    case "$t" in
        *\"*) echo "エラー: パスに \" を含められません: $t" >&2; exit 2 ;;
    esac
    TARGETS_JSON="${TARGETS_JSON}${TARGETS_JSON:+, }\"${t}\""
done

echo "=== 署名 ==="
echo "  ホスト: ${HOST}"
for t in "$@"; do echo "  対象:   $t"; done
echo

# sign.js は毎回コピーする。署名機側のチェックアウトが古いことがある。
if [[ "$HOST" == "local" ]]; then
    REMOTE_SIGN_JS="${SCRIPT_DIR}/sign.js"
else
    REMOTE_SIGN_JS="/tmp/pixinsight-sign.js"
    scp -q "${SCRIPT_DIR}/sign.js" "${HOST}:${REMOTE_SIGN_JS}"
fi

# ジョブファイルを書く。入るのは「秘密の在り処」だけで、秘密そのものは
# 入らない。~ は署名機の python で展開する（PJSR は ~ を解釈しない）。
remote "rm -f '${REPORT}'
python3 - <<'PYEOF'
import json, os
job = {
    \"keysFile\": os.path.expanduser(\"${KEYS}\"),
    \"password\": ${PASSWORD_JSON},
    \"entitlements\": ${ENTITLEMENTS_JSON},
    \"targets\": [os.path.expanduser(p) for p in [${TARGETS_JSON}]],
    \"report\": \"${REPORT}\",
}
if \"file\" in job[\"password\"]:
    job[\"password\"][\"file\"] = os.path.expanduser(job[\"password\"][\"file\"])
with open(os.path.expanduser(\"~/.pixinsight-sign-job.json\"), \"w\") as f:
    json.dump(job, f, ensure_ascii=False, indent=2)
PYEOF"

# --no-attach は他プロセスからのアタッチとコアダンプを止める。署名の最中は
# 鍵とパスワードがメモリにあるので、指定しない理由が無い。
remote "'${PI_APP}' -n --automation-mode --no-splash --no-attach \
    -r='${REMOTE_SIGN_JS}' --force-exit >/dev/null 2>&1 || true"

echo "--- 結果 ---"
if ! remote "test -f '${REPORT}'"; then
    echo "レポートが生成されませんでした。" >&2
    echo "PixInsight が起動できているか、sign.js が読めているかを確認してください。" >&2
    remote "cat \"\$TMPDIR/pixinsight-sign-error.txt\" 2>/dev/null" || true
    exit 1
fi
remote "cat '${REPORT}'"

# 失敗が 1 件でもあれば非ゼロで返す。呼び出し側（build-*.sh やリリース手順）
# がそのまま続くと、署名なしのまま配布物が出来てしまう。
if remote "grep -qE '^(FAILED|MISSING|INVALID)' '${REPORT}'"; then
    echo
    echo "エラー: 署名できなかった対象があります。" >&2
    exit 1
fi
