#!/usr/bin/env python3
"""Bounded Commons collector. All images enter quarantine, never training directly.
Requires Pillow. Metadata and image responses are cached locally; no credentials.
"""
import argparse, collections, hashlib, html, json, re, subprocess, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode, urlparse
from PIL import Image, ImageOps

API = 'https://commons.wikimedia.org/w/api.php'
UA = 'GRAMOResearch/0.2 (https://github.com/JJZHANG0/CONRAD_GRAMO_IOSAPP)'
LICENSES = {'CC0', 'Public domain', 'CC BY 2.0', 'CC BY 3.0', 'CC BY 4.0',
            'CC BY-SA 2.0', 'CC BY-SA 2.5', 'CC BY-SA 3.0', 'CC BY-SA 4.0'}

def plain(value):
    return html.unescape(re.sub('<[^>]+>', '', value)).strip()

class Client:
    def __init__(self, root):
        self.root = root; self.last = 0
        (root/'cache').mkdir(parents=True, exist_ok=True)
    def fetch(self, url, path):
        if urlparse(url).scheme != 'https' or urlparse(url).hostname not in {'commons.wikimedia.org','upload.wikimedia.org','thumb.wikimedia.org'}:
            raise ValueError('Unexpected download origin')
        time.sleep(max(0, 1.0-(time.monotonic()-self.last)))
        tmp = path.with_suffix(path.suffix+'.partial')
        try:
            subprocess.run(['curl','-fLsS','--max-time','35','--retry','2','--retry-max-time','45',
                            '--max-filesize','15000000','-A',UA,url,'-o',str(tmp)],check=True,capture_output=True)
            tmp.replace(path)
        except subprocess.CalledProcessError as e:
            detail=(e.stderr or b'').decode('utf-8',errors='replace')[-240:]
            raise RuntimeError(f'Download failed (curl exit {e.returncode}): {detail}') from e
        finally:
            self.last = time.monotonic()
            tmp.unlink(missing_ok=True)
    def query(self, **params):
        params.update(action='query',format='json',maxlag=5)
        key = hashlib.sha256(urlencode(sorted(params.items())).encode()).hexdigest()
        path = self.root/'cache'/(key+'.json')
        if not path.exists(): self.fetch(API+'?'+urlencode(params),path)
        result = json.loads(path.read_text())
        if 'error' in result:
            path.unlink(missing_ok=True)
            raise RuntimeError(str(result['error']))
        return result

def category_files(client, category, limit):
    result, continuation = [], {}
    while len(result) < limit:
        data = client.query(list='categorymembers',cmtitle='Category:'+category,cmtype='file',
                            cmlimit=min(50,limit-len(result)),**continuation)
        result.extend(data.get('query',{}).get('categorymembers',[]))
        continuation = data.get('continue')
        if not continuation: break
    return result[:limit]

def merge_candidate(records, page, info, dish):
    meta=info.get('extmetadata',{}); val=lambda k: meta.get(k,{}).get('value','')
    license_name=val('LicenseShortName')
    if license_name not in LICENSES or info.get('mime') not in {'image/jpeg','image/png','image/webp'}: return
    if min(info.get('width',0),info.get('height',0))<256: return
    if license_name not in {'CC0','Public domain'} and not val('Artist'): return
    key=str(page['pageid'])
    if key not in records:
        records[key]=dict(page_id=page['pageid'],title=page['title'],dish_ids=[],cuisines=[],
            source=info['descriptionurl'],download_url=info.get('thumburl',info['url']),original_url=info['url'],
            source_timestamp=info.get('timestamp'),source_sha1=info.get('sha1'),
            width=info['width'],height=info['height'],mime=info['mime'],license=license_name,
            license_url=val('LicenseUrl'),artist=plain(val('Artist')),attribution=plain(val('Attribution')),
            credit=plain(val('Credit')),description=plain(val('ImageDescription')),restrictions=plain(val('Restrictions')),
            copyright_notice=plain(val('Copyrighted')),label_source='Commons category; not a verified dish label',
            review_status='pending',training_eligible=False)
    r=records[key]
    r['dish_ids']=sorted(set(r['dish_ids']+[dish['dish_id']]))
    r['cuisines']=sorted(set(r['cuisines']+dish['cuisines']))
    if len(r['dish_ids'])>1: r['review_status']='label_conflict'

def fingerprint(path):
    with Image.open(path) as im:
        im=ImageOps.exif_transpose(im).convert('RGB')
        if min(im.size)<256: raise ValueError('Downloaded image is too small')
        gray=im.convert('L').resize((9,8),Image.Resampling.LANCZOS)
        px=list(gray.getdata()); bits=0
        for y in range(8):
            for x in range(8): bits=(bits<<1)|(px[y*9+x]>px[y*9+x+1])
        return im.size, f'{bits:016x}'

def group_images(rows):
    parent=list(range(len(rows)))
    def root(i):
        while parent[i]!=i: parent[i]=parent[parent[i]]; i=parent[i]
        return i
    for i,a in enumerate(rows):
        for j,b in enumerate(rows[:i]):
            if (a['sha256']==b['sha256'] or
                (a['artist'] and a['artist'].casefold()==b['artist'].casefold()) or
                (int(a['dhash'],16)^int(b['dhash'],16)).bit_count()<=5):
                parent[root(i)]=root(j)
    groups=collections.defaultdict(list)
    for i,r in enumerate(rows): groups[root(i)].append(r)
    for members in groups.values():
        gid='commons-group-'+str(min(r['page_id'] for r in members))
        for r in members:r['suggested_group']=gid
    # A duplicate file with different weak labels must not silently become trainable.
    exact=collections.defaultdict(list)
    for r in rows:exact[r['sha256']].append(r)
    for members in exact.values():
        labels={d for r in members for d in r['dish_ids']}
        if len(labels)>1:
            for r in members:r['review_status']='label_conflict'
        elif len(members)>1:
            for r in sorted(members,key=lambda x:x['page_id'])[1:]:r['review_status']='exact_duplicate'

def write_review(root, rows, dishes):
    names={d['dish_id']:d['name_zh'] for d in dishes}
    cards=[]
    for r in rows:
        title=' / '.join(names[k] for k in r['dish_ids'])
        cards.append('<article><img loading="lazy" src="'+html.escape(r['local_path'],quote=True)+'">'
            '<h3>'+html.escape(title)+'</h3><p>'+str(r['page_id'])+' · '+html.escape(r['review_status'])+'</p>'
            '<p>'+html.escape(r['artist'])+' · '+html.escape(r['license'])+'</p>'
            '<a href="'+html.escape(r['source'],quote=True)+'">来源与授权</a></article>')
    (root/'review.html').write_text('<!doctype html><meta charset="utf-8"><title>GRAMO 图片待审核</title>'
        '<style>body{font:15px system-ui;margin:32px;background:#eee}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}article{background:white;padding:16px;border-radius:16px}img{width:100%;height:190px;object-fit:contain}p{overflow-wrap:anywhere}</style>'
        '<h1>GRAMO · 菜品图片待审核</h1><p>全部图片尚未批准训练。核对单道菜、来源、遮挡、重复和同盘分组；多菜图需先裁剪并重新审核。</p><main>'+''.join(cards)+'</main>')

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--catalog',type=Path,default=Path('tools/training/cuisine-catalog.json'))
    p.add_argument('--output',type=Path,default=Path('artifacts/cuisine-dataset'))
    p.add_argument('--per-dish',type=int,default=10)
    p.add_argument('--metadata-limit',type=int,default=60)
    p.add_argument('--max-images',type=int,default=250)
    p.add_argument('--minutes',type=int,default=20)
    args=p.parse_args()
    if min(args.per_dish,args.metadata_limit,args.max_images,args.minutes)<1:p.error('Limits must be positive')
    root=args.output;root.mkdir(parents=True,exist_ok=True);(root/'images').mkdir(exist_ok=True)
    dishes=json.loads(args.catalog.read_text());client=Client(root);records={};errors=[];coverage={}
    start=time.monotonic()
    def expired():return time.monotonic()-start>args.minutes*60
    def checkpoint():
        (root/'candidates.json').write_text(json.dumps(list(records.values()),ensure_ascii=False,indent=2))
        (root/'errors.json').write_text(json.dumps(errors,ensure_ascii=False,indent=2))
    for dish in dishes:
        if expired():break
        ids=[]
        try:
            members=category_files(client,dish['commons_category'],args.metadata_limit)
            ids=[x['pageid'] for x in members]
            for offset in range(0,len(ids),20):
                data=client.query(pageids='|'.join(map(str,ids[offset:offset+20])),prop='imageinfo',iilimit=1,
                    iiprop='url|extmetadata|size|mime|sha1|timestamp',iiurlwidth=640)
                for page in data.get('query',{}).get('pages',{}).values():
                    if page.get('imageinfo'):merge_candidate(records,page,page['imageinfo'][0],dish)
        except Exception as e:errors.append(dict(stage='metadata',dish=dish['dish_id'],error=str(e)[:300]))
        coverage[dish['dish_id']]={'category_files_examined':len(ids)}
        checkpoint();print('METADATA',dish['dish_id'],len(ids),flush=True)
    previous=Path('artifacts/colab-pilot/results/manifest.json')
    prior={str(r['page_id']):r['split'] for r in json.loads(previous.read_text())} if previous.exists() else {}
    selected={};counts=collections.Counter()
    for dish in dishes:
        candidates=[r for r in records.values() if dish['dish_id'] in r['dish_ids'] and r['review_status']!='label_conflict']
        # Prefer different photographers before additional frames by the same author.
        authors=collections.defaultdict(list)
        for r in sorted(candidates,key=lambda x:x['page_id']):authors[r['artist']].append(r)
        ordered=[]
        while any(authors.values()):
            for author in sorted(authors):
                if authors[author]:ordered.append(authors[author].pop(0))
        for r in ordered:
            if counts[dish['dish_id']]>=args.per_dish or len(selected)>=args.max_images or expired():break
            if r['page_id'] in selected:continue
            ext={'image/jpeg':'.jpg','image/png':'.png','image/webp':'.webp'}[r['mime']]
            path=root/'images'/(str(r['page_id'])+ext)
            try:
                if not path.exists():client.fetch(r['download_url'],path)
                size,dh=fingerprint(path)
                r.update(local_path=str(path.relative_to(root)),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                         downloaded_size=list(size),dhash=dh,prior_experiment_split=prior.get(str(r['page_id'])))
                selected[r['page_id']]=r;counts[dish['dish_id']]+=1
            except Exception as e:errors.append(dict(stage='download',page_id=r['page_id'],error=str(e)[:300]))
        checkpoint()
        print('DOWNLOADED',dish['dish_id'],counts[dish['dish_id']],flush=True)
    rows=list(selected.values());group_images(rows)
    for dish in dishes:
        coverage.setdefault(dish['dish_id'],{'category_files_examined':0}).update(downloaded=counts[dish['dish_id']],name_zh=dish['name_zh'],cuisines=dish['cuisines'])
    checkpoint()
    (root/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    write_review(root,rows,dishes)
    summary=dict(created_utc=datetime.now(timezone.utc).isoformat(),catalog_sha256=hashlib.sha256(args.catalog.read_bytes()).hexdigest(),
        unique_candidates=len(records),downloaded=len(rows),unique_file_hashes=len({r['sha256'] for r in rows}),
        label_conflicts=sum(r['review_status']=='label_conflict' for r in records.values()),
        approved_for_training=0,coverage=coverage,errors=len(errors),time_budget_reached=expired(),
        seconds=round(time.monotonic()-start,1),limitations=['Category labels are weak labels; all images require review.',
        'Suggested author/hash groups are conservative, not proven plate identities.',
        'License metadata is preserved, not a blanket commercial clearance.',
        'A sample of eight regional cuisines, not exhaustive Chinese food coverage.'])
    (root/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    print('COMPLETE',json.dumps({k:v for k,v in summary.items() if k!='coverage'}),flush=True)

if __name__=='__main__':main()
