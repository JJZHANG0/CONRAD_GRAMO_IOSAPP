#!/usr/bin/env python3
"""Build a small public-image evaluation manifest; no private photos or credentials."""
import argparse, hashlib, json, subprocess
from pathlib import Path

CATEGORIES = {0: 'Mapo doufu', 71: 'Kung Pao chicken', 77: 'Red braised pork belly'}
LICENSES = {'CC0', 'Public domain', 'CC BY 2.0', 'CC BY 3.0', 'CC BY 4.0',
            'CC BY-SA 2.0', 'CC BY-SA 2.5', 'CC BY-SA 3.0', 'CC BY-SA 4.0'}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, default=Path('artifacts/colab-pilot/manifest.json'))
    args = p.parse_args()
    rows = []
    for label, category in CATEGORIES.items():
        params = dict(action='query', generator='categorymembers', gcmtitle='Category:'+category,
                      gcmtype='file', gcmlimit='100', prop='imageinfo', iiprop='url|extmetadata',
                      iiurlwidth='512', format='json')
        cmd = ['curl', '-fsSL', '--retry', '2', '--max-time', '60', '--get',
               'https://commons.wikimedia.org/w/api.php']
        for key, value in params.items(): cmd += ['--data-urlencode', f'{key}={value}']
        data = json.loads(subprocess.check_output(cmd))
        for page in data.get('query', {}).get('pages', {}).values():
            if 'imageinfo' not in page: continue
            info = page['imageinfo'][0]; meta = info.get('extmetadata', {})
            val = lambda key: meta.get(key, {}).get('value', '')
            if val('LicenseShortName') not in LICENSES: continue
            if not page['title'].lower().endswith(('.jpg', '.jpeg', '.png')): continue
            rows.append(dict(page_id=page['pageid'], title=page['title'], label=label,
                category=category, url=info.get('thumburl', info['url']), original_url=info['url'],
                source=info['descriptionurl'], license=val('LicenseShortName'),
                license_url=val('LicenseUrl'), artist=val('Artist'), description=val('ImageDescription'),
                label_source='Commons category; weak label, not individually verified'))
    rows.sort(key=lambda r: r['page_id'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2))
    print({c: sum(r['label']==c for r in rows) for c in CATEGORIES})
    print('manifest sha256', hashlib.sha256(args.output.read_bytes()).hexdigest())

if __name__ == '__main__': main()
