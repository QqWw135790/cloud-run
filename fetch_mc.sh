#!/bin/bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ITEM=${ITEM:-minecraft-1-19-73}
VER=${VER:-1.16.221.01}

echo "=== [A] apkeep apk-pure @ $VER"
curl -sL --max-time 180 -o /tmp/apkeep "https://github.com/EFForg/apkeep/releases/latest/download/apkeep-x86_64-unknown-linux-gnu"
chmod +x /tmp/apkeep
rm -rf dl && mkdir -p dl
/tmp/apkeep -a "com.mojang.minecraftpe@$VER" -d apk-pure --acknowledge-risks-apk-pure dl 2>&1 | tail -10
ls -l dl 2>/dev/null

APK=$(ls dl/*.apk dl/*.xapk 2>/dev/null | head -1)

if [ -z "$APK" ]; then
  echo "=== [B] archive.org $ITEM : all files"
  curl -sL --max-time 90 "https://archive.org/metadata/$ITEM" -o m.json
  python3 -c "
import json
d=json.load(open('m.json'))
md=d.get('metadata',{})
print('TITLE:',md.get('title'))
print('DESC:',str(md.get('description',''))[:200].replace(chr(10),' '))
fs=d.get('files',[])
print('FILES:',len(fs))
for f in fs[:30]:
    print(' -',f.get('name'),f.get('size'),f.get('format'))
"
  F=$(python3 -c "
import json
d=json.load(open('m.json'))
c=[f for f in d.get('files',[]) if f.get('name','').lower().endswith('.apk')]
if c: print(max(c,key=lambda x:int(x.get('size') or 0))['name'])
")
  echo "PICKED=$F"
  if [ -n "$F" ]; then
    ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$F")
    curl -L --max-time 900 -A "$UA" -o out.apk "https://archive.org/download/$ITEM/$ENC"
    APK=out.apk
  fi
fi

if [ ! -s "$APK" ]; then echo "DOWNLOAD_FAILED"; exit 0; fi
SZ=$(stat -c%s "$APK"); echo "APK=$APK size=$SZ type=$(file -b "$APK" | cut -c1-40)"
if [ "$SZ" -lt 20000000 ]; then echo "TOO_SMALL"; exit 0; fi

echo "=== uploading"
FINAL=$(curl -s --max-time 900 -F "reqtype=fileupload" -F "time=72h" -F "fileToUpload=@$APK" https://litterbox.catbox.moe/resources/internals/api.php)
echo "FINAL_URL=$FINAL"
echo "MD5=$(md5sum "$APK" | cut -d' ' -f1)"
