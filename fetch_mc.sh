#!/bin/bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
echo "=== apkeep help"
curl -sL --max-time 180 -o /tmp/apkeep "https://github.com/EFForg/apkeep/releases/latest/download/apkeep-x86_64-unknown-linux-gnu"
chmod +x /tmp/apkeep
/tmp/apkeep --help 2>&1 | head -45

echo "=== archive explore"
for it in mcbe-1.1.2.5 minecraft-bedrock-edition-v1.20.x-cloned-apk-for-arm64; do
  echo "-- $it"
  curl -sL --max-time 60 "https://archive.org/metadata/$it" -o m.json
  python3 -c "
import json
try:
    d=json.load(open('m.json'))
    print('  TITLE:',d.get('metadata',{}).get('title'))
    for f in d.get('files',[])[:12]: print('  -',f.get('name'),f.get('size'))
except Exception as e: print('  ERR',e)
"
done

echo "=== archive search more"
curl -s --max-time 60 "https://archive.org/advancedsearch.php?q=minecraft+apk&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=downloads&rows=15&output=json" -o s.json
python3 -c "
import json
d=json.load(open('s.json'))
for x in d['response']['docs']: print(x.get('identifier'),'|',str(x.get('title'))[:50])
"
echo "DONE"
