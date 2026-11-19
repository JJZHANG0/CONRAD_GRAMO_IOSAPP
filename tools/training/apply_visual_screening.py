#!/usr/bin/env python3
"""Apply recorded visual exclusions. Never changes an image to training-approved."""
import argparse,json
from pathlib import Path
from collect_cuisine_images import write_review

def main():
    p=argparse.ArgumentParser();p.add_argument('root',type=Path)
    p.add_argument('--catalog',type=Path,default=Path('tools/training/cuisine-catalog.json'))
    a=p.parse_args();rows=json.loads((a.root/'manifest.json').read_text())
    decisions=json.loads((a.root/'visual-screening.json').read_text())
    excluded={r['page_id']:r for r in decisions if r['decision']=='exclude_whole_image'}
    for row in rows:
        if row['page_id'] in excluded:
            row['review_status']='rejected_visual';row['visual_review']=excluded[row['page_id']]
            row['training_eligible']=False
    (a.root/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    write_review(a.root,rows,json.loads(a.catalog.read_text()))
    s=json.loads((a.root/'summary.json').read_text());s['visually_excluded']=sum(r['review_status']=='rejected_visual' for r in rows)
    s['pending_review']=sum(r['review_status']=='pending' for r in rows)
    s['approved_for_training']=0
    (a.root/'summary.json').write_text(json.dumps(s,ensure_ascii=False,indent=2))
    print({'visually_excluded':s['visually_excluded'],'pending_review':s['pending_review'],'approved_for_training':0})

if __name__=='__main__':main()
