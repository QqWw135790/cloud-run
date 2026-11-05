#!/bin/bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ITEM=minecraft-bedrock-edition-v1.20.x-cloned-apk-for-arm64
F="Minecraft v1.20.81.01_cloned (972008101).zip"

echo "=== download zip"
ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$F")
curl -L --max-time 900 -A "$UA" -o z.zip "https://archive.org/download/$ITEM/$ENC" -s
echo "zip=$(stat -c%s z.zip 2>/dev/null || echo 0)"
rm -rf ex && mkdir -p ex && (cd ex && unzip -o -q ../z.zip)
APK=$(find ex -name '*.apk' | head -1)
echo "APK=$APK size=$(stat -c%s "$APK") sha256=$(sha256sum "$APK" | cut -d' ' -f1)"

echo "=== upload temp.sh"
R1=$(curl -s --max-time 600 -F "file=@$APK" https://temp.sh/upload)
echo "TEMP_SH=$R1"

echo "=== upload litterbox retry"
R2=$(curl -s --max-time 900 -F "reqtype=fileupload" -F "time=72h" -F "fileToUpload=@$APK" https://litterbox.catbox.moe/resources/internals/api.php)
echo "LITTER=$R2"

echo "=== upload github release"
TAG=apk-$(date +%s)
REL=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/QqWw135790/cloud-run/releases \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"mc apk $TAG\"}")
UP=$(echo "$REL" | python3 -c "import sys,json;print(json.load(sys.stdin).get('upload_url','').split('{')[0])" 2>/dev/null)
echo "UPLOAD_URL=$UP"
if [ -n "$UP" ]; then
  curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" \
    --data-binary @"$APK" "$UP?name=minecraft.apk" -o up.json
  python3 -c "
import json
d=json.load(open('up.json'))
print('GH_ASSET=',d.get('browser_download_url'))
"
fi
echo "DONE"
