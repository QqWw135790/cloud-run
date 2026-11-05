#!/bin/bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
VER=${VER:-1.16.221.01}
echo "=== apkeep apk-pure with tty, ver=$VER"
curl -sL --max-time 180 -o /tmp/apkeep "https://github.com/EFForg/apkeep/releases/latest/download/apkeep-x86_64-unknown-linux-gnu"
chmod +x /tmp/apkeep
rm -rf dl && mkdir -p dl
printf 'y\ny\n' | script -qec "/tmp/apkeep -a com.mojang.minecraftpe@$VER -d apk-pure dl" /dev/null 2>&1 | tail -15
ls -l dl

APK=$(ls dl/*.apk dl/*.xapk 2>/dev/null | head -1)
echo "APK_FILE=$APK"

if [ -z "$APK" ]; then
  echo "=== fallback archive.org cloned 1.20.81.01"
  ITEM=minecraft-bedrock-edition-v1.20.x-cloned-apk-for-arm64
  F="Minecraft v1.20.81.01_cloned (972008101).zip"
  ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$F")
  curl -L --max-time 900 -A "$UA" -o z.zip "https://archive.org/download/$ITEM/$ENC"
  echo "zip size=$(stat -c%s z.zip 2>/dev/null || echo 0)"
  mkdir -p ex && cd ex && unzip -o -q ../z.zip 2>&1 | tail -3; cd ..
  APK=$(find ex -name '*.apk' | head -1)
  echo "APK_FILE=$APK"
fi

if [ -z "$APK" ] || [ ! -s "$APK" ]; then echo "DOWNLOAD_FAILED"; exit 0; fi
SZ=$(stat -c%s "$APK"); echo "size=$SZ type=$(file -b "$APK" | cut -c1-40)"
if [ "$SZ" -lt 20000000 ]; then echo "TOO_SMALL"; exit 0; fi

echo "=== uploading"
FINAL=$(curl -s --max-time 900 -F "reqtype=fileupload" -F "time=72h" -F "fileToUpload=@$APK" https://litterbox.catbox.moe/resources/internals/api.php)
echo "FINAL_URL=$FINAL"
echo "MD5=$(md5sum "$APK" | cut -d' ' -f1)"
