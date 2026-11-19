#!/usr/bin/env python3
"""Export reviewed images without silently assigning new foods to the 114-class model.
Review JSON is a list of {page_id, decision, dish_id, reviewer, plate_group, split}.
Only explicit accept decisions are exported. Missing data is an error, not a default.
"""
import argparse, hashlib, json
from pathlib import Path

def build_export(manifest, reviews, catalog):
    sources={r['page_id']:r for r in manifest}
    if len(sources)!=len(manifest):raise ValueError('Manifest contains duplicate page IDs')
    dishes={d['dish_id']:d for d in catalog}; seen=set(); accepted=[]; new_classes=[]; groups={}
    for review in reviews:
        pid=review['page_id']
        if pid in seen:raise ValueError('Duplicate review: '+str(pid))
        seen.add(pid)
        if pid not in sources:raise ValueError('Unknown page ID: '+str(pid))
        if review.get('decision')=='reject':continue
        if review.get('decision')!='accept':raise ValueError('Review decision must be accept or reject')
        r=sources[pid];dish=dishes.get(review.get('dish_id'))
        if dish is None:raise ValueError('Unknown dish ID')
        if not review.get('reviewer','').strip() or not review.get('plate_group','').strip():
            raise ValueError('Reviewer and plate_group are required')
        split=review.get('split')
        if split not in {'train','validation','test'}:raise ValueError('Explicit split is required')
        if r.get('prior_experiment_split') in {'val','test'} and split=='train':
            raise ValueError('Previously held-out image cannot become training data')
        if r.get('review_status') in {'label_conflict','exact_duplicate','rejected_visual'}:
            raise ValueError('Resolve duplicate/multi-dish source in a new audited manifest first')
        # Conservatively keep both automatic source groups and manually known plates intact.
        for key in ['source:'+r['suggested_group'],'plate:'+review['plate_group'],'sha:'+r['sha256']]:
            if key in groups and groups[key]!=split:raise ValueError('Cross-split leakage: '+key)
            groups[key]=split
        item=dict(r,confirmed_dish_id=dish['dish_id'],name_zh=dish['name_zh'],reviewer=review['reviewer'],
            plate_group=review['plate_group'],split=split,model_label_id=dish['model_label_id'],
            review_status='accepted',training_eligible=dish['model_label_id'] is not None)
        (accepted if item['training_eligible'] else new_classes).append(item)
    return accepted,new_classes

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--manifest',type=Path,required=True)
    p.add_argument('--reviews',type=Path,required=True)
    p.add_argument('--catalog',type=Path,default=Path('tools/training/cuisine-catalog.json'))
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();manifest=json.loads(a.manifest.read_text())
    accepted,new=build_export(manifest,json.loads(a.reviews.read_text()),json.loads(a.catalog.read_text()))
    for row in accepted+new:
        path=(a.manifest.parent/row['local_path']).resolve()
        if not path.is_relative_to(a.manifest.parent.resolve()):raise ValueError('Unsafe image path')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:raise ValueError('Image checksum mismatch')
    a.output.mkdir(parents=True,exist_ok=True)
    for name,rows in [('reviewed-existing-labels.json',accepted),('reviewed-needs-new-labels.json',new)]:
        (a.output/name).write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    print({'existing_model_labels':len(accepted),'needs_new_taxonomy':len(new),'ignored_unreviewed':len(manifest)-len(accepted)-len(new)})

if __name__=='__main__':main()
