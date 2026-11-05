#!/bin/bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ITEM=${ITEM:-minecraft-1-19-73}

echo "=== [A] apkeep correct syntax"
curl -sL --max-time 180 -o /tmp/apkeep "https://github.com/EFForg/apkeep/releases/latest/download/apkeep-x86_64-unknown-linux-gnu"
chmod +x /tmp/apkeep
rm -rf dl && mkdir -p dl
/tmp/apkeep -a "com.mojang.minecraftpe@1.16.221.01" -d apkpure dl 2>&1 | tail -8
ls -l dl 2>/dev/null

APK=$(ls dl/*.apk dl/*.xapk 2>/dev/null | head -1)

if [ -z "$APK" ]; then
  echo "=== [B] archive.org item: $ITEM"
  curl -sL --max-time 90 "https://archive.org/metadata/$ITEM" -o m.json
  python3 -c "
import json
d=json.load(open('m.json'))
md=d.get('metadata',{})
print('TITLE:',md.get('title'),'|',md.get('description','')[:150].replace(chr(10),' '))
for f in d.get('files',[]):
    n=f.get('name','')
    if n.lower().endswith(('.apk','.xapk','.zip','.7z')):
        print('FILE:',n,f.get('size'))
"
  F=$(python3 -c "
import json
d=json.load(open('m.json'))
for f in d.get('files',[]):
    n=f.get('name','')
    if n.lower().endswith('.apk'):
        print(n); break
")
  echo "PICKED_FILE=$F"
  if [ -n "$F" ]; then
    ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$F")
    curl -L --max-time 900 -A "$UA" -o out.apk "https://archive.org/download/$ITEM/$ENC"
    echo "size=$(stat -c%s out.apk 2>/dev/null || echo 0) type=$(file -b out.apk | cut -c1-50)"
    APK=out.apk
  fi
fi

if [ ! -s "$APK" ]; then echo "DOWNLOAD_FAILED"; exit 0; fi
SZ=$(stat -c%s "$APK")
echo "APK=$APK size=$SZ"
if [ "$SZ" -lt 20000000 ]; then echo "TOO_SMALL"; head -c 200 "$APK"; echo; exit 0; fi

echo "=== uploading"
FINAL=$(curl -s --max-time 900 -F "reqtype=fileupload" -F "time=72h" -F "fileToUpload=@$APK" https://litterbox.catbox.moe/resources/internals/api.php)
echo "FINAL_URL=$FINAL"
echo "MD5=$(md5sum "$APK" | cut -d' ' -f1)"
