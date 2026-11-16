#!/usr/bin/env python3
"""Evaluate real, consented camera samples separately. Never fit on test data.
CSV: image,camera,plate_group,split,expected_id (empty expected_id = nonfood/OOD).
Optional --threshold and --margin are reporting experiments, not a deployment policy.
"""
import argparse, csv, json, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps
from transformers import AutoImageProcessor
import coremltools as ct

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('samples',type=Path); ap.add_argument('--model',type=Path,default=Path('artifacts/chinese-food'))
    ap.add_argument('--output',type=Path,default=Path('artifacts/evaluation/camera-report.json'))
    ap.add_argument('--threshold',type=float); ap.add_argument('--margin',type=float)
    args=ap.parse_args(); rows=list(csv.DictReader(args.samples.open())); groups={}
    for row in rows:
        assert row['camera'] in ['phone','spoon','public'], 'Unknown camera source'
        assert row['split'] in ['train','validation','test'], 'Invalid split'
        key=row['plate_group']; assert key, 'Plate group is required'
        assert key not in groups or groups[key]==row['split'], 'Same plate leaks between data splits'
        groups[key]=row['split']
    model=ct.models.MLModel(str(args.model/'ChineseFood.mlpackage'), compute_units=ct.ComputeUnit.CPU_ONLY)
    processor=AutoImageProcessor.from_pretrained(args.model/'source',local_files_only=True,trust_remote_code=False,use_fast=False)
    report={'samples':[], 'cameras':{}, 'policy':'manual confirmation; no production threshold validated'}
    for row in rows:
        if row['split']=='train': continue
        path=args.samples.parent/row['image']; image=ImageOps.exif_transpose(Image.open(path)).convert('RGB')
        pixels=processor(image,return_tensors='np',do_normalize=False,do_rescale=False)['pixel_values'][0].transpose(1,2,0).astype('uint8')
        scores=model.predict({'image':Image.fromarray(pixels)})['probabilities'].reshape(-1)
        indices=np.argsort(-scores,kind='stable')[:3]; expected=int(row['expected_id']) if row['expected_id'] else None
        accepted=args.threshold is not None and args.margin is not None and scores[indices[0]]>=args.threshold and scores[indices[0]]-scores[indices[1]]>=args.margin
        entry=dict(row,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),top3=[{'id':int(i),'score':float(scores[i])} for i in indices],
                   top1_correct=expected==int(indices[0]),top3_correct=expected in indices if expected is not None else False,
                   experimental_accepted=bool(accepted))
        report['samples'].append(entry)
    for camera in ['phone','spoon','public']:
        records=[r for r in report['samples'] if r['camera']==camera]; covered=[r for r in records if r['expected_id']]; negative=[r for r in records if not r['expected_id']]
        report['cameras'][camera]={'samples':len(records), 'covered':len(covered),'negative':len(negative),
                                  'top1':sum(r['top1_correct'] for r in covered)/len(covered) if covered else None,
                                  'top3':sum(r['top3_correct'] for r in covered)/len(covered) if covered else None,
                                  'negative_false_accepts':sum(r['experimental_accepted'] for r in negative) if args.threshold is not None else None}
    args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report['cameras'],ensure_ascii=False,indent=2))
if __name__=='__main__':main()
