#!/bin/bash
set -euo pipefail

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ITEM=minecraft-bedrock-edition-v1.20.x-cloned-apk-for-arm64
F="Minecraft v1.20.81.01_cloned (972008101).zip"
: "${GITHUB_TOKEN:?GitHub Release 上传需要 GITHUB_TOKEN}"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd -- "$work"

echo "=== download zip"
ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$F")
curl --fail --silent --show-error --location --max-time 900 -A "$UA" -o z.zip "https://archive.org/download/$ITEM/$ENC"
size=$(stat -c%s z.zip)
echo "zip=$size"

# 只读取目标成员，不使用归档内的目录或链接作为解压路径。
APK=$(python3 - <<'PY'
import shutil
import zipfile
from pathlib import PurePosixPath

with zipfile.ZipFile("z.zip") as archive:
    for member in archive.infolist():
        if not member.is_dir() and member.filename.endswith(".apk"):
            name = PurePosixPath(member.filename).name
            if any(ord(c) < 32 or c in '"\\' for c in name):
                raise SystemExit("APK 文件名含不支持的字符")
            with archive.open(member) as src, open(name, "xb") as dst:
                shutil.copyfileobj(src, dst)
            print("./" + name)
            break
    else:
        raise SystemExit("ZIP 中没有 APK")
PY
)
size=$(stat -c%s "$APK")
digest=$(sha256sum "$APK")
echo "APK=$APK size=$size sha256=${digest%% *}"

# 服务返回的错误正文可能含有不适合写入 result.txt 的内容。
upload_link() {
  local response
  response=$(curl --fail --silent --show-error "$@") || return 1
  if [[ ! $response =~ ^https?://[^[:space:]]+$ ]]; then
    echo "上传服务没有返回下载链接" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

echo "=== upload temp.sh"
R1=$(upload_link --max-time 600 -F "file=@\"$APK\"" https://temp.sh/upload)
echo "TEMP_SH=$R1"

echo "=== upload litterbox"
R2=$(upload_link --max-time 900 -F "reqtype=fileupload" -F "time=72h" -F "fileToUpload=@\"$APK\"" https://litterbox.catbox.moe/resources/internals/api.php)
echo "LITTER=$R2"

github_post() {
  printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" |
    curl --fail --silent --show-error --max-time 900 -H @- -H "Accept: application/vnd.github+json" "$@"
}

echo "=== upload github release"
TAG=apk-$(date +%s)
github_post https://api.github.com/repos/QqWw135790/cloud-run/releases \
  -H 'Content-Type: application/json' -d "{\"tag_name\":\"$TAG\",\"name\":\"mc apk $TAG\"}" -o release.json
release_id=$(python3 - <<'PY'
import json
with open("release.json") as f:
    value = json.load(f)["id"]
if type(value) is not int or value <= 0:
    raise SystemExit("GitHub 返回了无效的 Release ID")
print(value)
PY
)
github_post -H "Content-Type: application/octet-stream" --data-binary @"$APK" \
  "https://uploads.github.com/repos/QqWw135790/cloud-run/releases/$release_id/assets?name=minecraft.apk" -o up.json
python3 - <<'PY'
import json
with open("up.json") as f:
    asset = json.load(f)
if asset.get("state") != "uploaded" or not asset.get("browser_download_url"):
    raise SystemExit("GitHub 未确认资源上传成功")
print("GH_ASSET=", asset["browser_download_url"])
PY
echo "DONE"
