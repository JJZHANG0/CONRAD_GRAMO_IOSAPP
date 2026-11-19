"""Bounded, research-only head fine-tuning. Never deploys or edits the iOS model.
Input: manifest.json from prepare_commons_manifest.py (public Commons images only).
Output: results.zip with checkpoint, provenance, splits, predictions and metrics.
"""
import copy, hashlib, html, io, json, os, platform, random, re, shutil, subprocess, time
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image, ImageOps
import imagehash
from transformers import AutoImageProcessor, ResNetForImageClassification
from huggingface_hub import hf_hub_download

BASE = 'Albertbeta123/resnet-50-chinese-food'
REV = '1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c'
SEED = 20261119
CLASSES = [0, 71, 77]
EXPECTED = {0: 'Mapo Tofu', 71: 'Kung Pao Chicken', 77: 'Braised pork'}
OUT = Path('gramo-pilot'); OUT.mkdir(exist_ok=True)
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
assert torch.cuda.is_available(), 'Free GPU unavailable; stop instead of starting paid compute.'
DEVICE = 'cuda'
torch.backends.cudnn.benchmark = False
started = time.monotonic()
manifest = json.loads(Path('manifest.json').read_text())
# A multi-dish photograph can belong to several Commons categories. It is not
# valid single-label training evidence: exclude all occurrences before sampling.
labels_by_page = {}
for row in manifest:
    labels_by_page.setdefault(row['page_id'], set()).add(row['label'])
conflicting_page_ids = sorted(k for k, labels in labels_by_page.items() if len(labels) > 1)
manifest = list({r['page_id']: r for r in manifest if r['page_id'] not in conflicting_page_ids}.values())
print('EXCLUDED_CONFLICTING_PAGES', conflicting_page_ids, flush=True)

manifest_sha256 = hashlib.sha256(Path('manifest.json').read_bytes()).hexdigest()
source = OUT / 'source'; source.mkdir(exist_ok=True)
for name in ['config.json', 'preprocessor_config.json', 'model.safetensors']:
    hf_hub_download(BASE, name, revision=REV, local_dir=source)
expected_hashes = {'model.safetensors': '301c5262348a25beeb782d11cbd083dfad8d478f92672ef5a237b4f557d79849', 'config.json': '19cc85be4edd124800b69b04c2f882314327b91a079ebbd4f1d6d3ac31f6dd7b', 'preprocessor_config.json': '9ef34d18dbf7909143a91f05ad23457180fcfed05034bf94843f300e32a9b968'}
for name, expected in expected_hashes.items():
    assert hashlib.sha256((source/name).read_bytes()).hexdigest() == expected, name+' checksum mismatch'
processor = AutoImageProcessor.from_pretrained(source, local_files_only=True, trust_remote_code=False, use_fast=False)
model = ResNetForImageClassification.from_pretrained(source, local_files_only=True,
    trust_remote_code=False, use_safetensors=True).eval().to(DEVICE)
assert len(model.config.id2label) == 114
assert all(model.config.id2label[k] == v for k, v in EXPECTED.items())
print('MODEL_READY', REV, torch.cuda.get_device_name(0), flush=True)

# Bounded download, preserving author/license/source. Never use prediction as ground truth.
rows, pixels, hashes, failed = [], [], [], []
images = OUT / 'images'; images.mkdir(exist_ok=True)
for r in sorted(manifest, key=lambda r: hashlib.sha256(str(r['page_id']).encode()).hexdigest()):
    if sum(x['label'] == r['label'] for x in rows) >= 45: continue
    if time.monotonic() - started > 900: break
    path = images / f"{r['page_id']}.jpg"
    try:
        subprocess.run(['curl', '-fLsS', '--max-time', '20', '--retry', '1', r['url'], '-o', str(path)],
                       check=True, capture_output=True)
        raw = path.read_bytes()
        with Image.open(io.BytesIO(raw)) as im:
            im = ImageOps.exif_transpose(im).convert('RGB')
            ph = imagehash.phash(im)
            tensor = processor(images=im, return_tensors='pt')['pixel_values'][0]
        rows.append(dict(r, sha256=hashlib.sha256(raw).hexdigest(), phash=str(ph)))
        pixels.append(tensor); hashes.append(ph)
        if len(rows) % 20 == 0: print('IMAGES', len(rows), flush=True)
    except Exception as e:
        failed.append({'page_id': r['page_id'], 'error': str(e)[:180]})
print('DOWNLOAD_DONE', {c: sum(r['label']==c for r in rows) for c in CLASSES}, flush=True)

# Group all pictures by author AND near-duplicate appearance before splitting.
# This conservatively keeps an author's plate/burst photos together.
parent = list(range(len(rows)))
def root(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]; i = parent[i]
    return i
for i in range(len(rows)):
    author = html.unescape(re.sub('<[^>]+>', '', rows[i]['artist'])).strip().lower()
    rows[i]['author_group'] = author or 'unknown-author'
    for j in range(i):
        if (rows[i]['author_group'] == rows[j]['author_group'] or hashes[i]-hashes[j] <= 6):
            parent[root(i)] = root(j)
for i, r in enumerate(rows): r['group'] = str(root(i))
groups = sorted({r['group'] for r in rows})
for attempt in range(1000):
    shuffled = groups.copy(); random.Random(SEED+attempt).shuffle(shuffled)
    n = len(shuffled); lookup = {g: ('train' if i < int(n*.6) else 'val' if i < int(n*.8) else 'test') for i,g in enumerate(shuffled)}
    splits = {s: [i for i,r in enumerate(rows) if lookup[r['group']]==s] for s in ['train','val','test']}
    if all(sum(rows[i]['label']==c for i in splits[s]) >= (8 if s=='train' else 3) for s in splits for c in CLASSES): break
else: raise RuntimeError('Insufficient independent groups: do not train or weaken split to force results.')
for s, indices in splits.items():
    for i in indices: rows[i]['split'] = s
assert not ({rows[i]['group'] for i in splits['train']} & {rows[i]['group'] for i in splits['test']+splits['val']})
(OUT/'manifest.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2))
print('SPLITS', {s: len(i) for s,i in splits.items()}, flush=True)
x = torch.stack(pixels); y = torch.tensor([r['label'] for r in rows], device=DEVICE)
features = []
with torch.inference_mode():
    for batch in x.split(16): features.append(model.resnet(batch.to(DEVICE)).pooler_output.flatten(1))
features = torch.cat(features)
head = copy.deepcopy(model.classifier)
for p in model.parameters(): p.requires_grad_(False)
for p in head.parameters(): p.requires_grad_(True)
with torch.no_grad(): baseline_logits = head(features).detach().clone()

def metrics(logits, indices):
    z, target = logits[indices], y[indices]
    t3 = z.topk(3, dim=1).indices
    return {'n': len(indices), 'top1': float((t3[:,0]==target).float().mean()),
        'top3': float((t3==target[:,None]).any(1).float().mean()),
        'loss': float(F.cross_entropy(z, target)),
        'macro_top1': float(torch.stack([(t3[target==c,0]==c).float().mean() for c in CLASSES]).mean())}

baseline = {s: metrics(baseline_logits, ids) for s,ids in splits.items()}
print('BASELINE', json.dumps(baseline), flush=True)
optimizer = torch.optim.AdamW(head.parameters(), lr=0.0001, weight_decay=0.01)
best = copy.deepcopy(head.state_dict()); best_val = baseline['val']; best_epoch = 0; history = []
# Only adjust the three covered output rows; preserve all other class rows exactly.
for epoch in range(1, 13):
    order = splits['train'].copy(); random.Random(SEED+epoch).shuffle(order)
    for start in range(0, len(order), 16):
        ids = order[start:start+16]
        logits = head(features[ids])
        loss = F.cross_entropy(logits, y[ids]) + .5*F.kl_div(
            F.log_softmax(logits/2,dim=1), F.softmax(baseline_logits[ids]/2,dim=1), reduction='batchmean')*4
        optimizer.zero_grad(); loss.backward()
        for p in head.parameters():
            if p.grad is not None:
                mask = torch.zeros_like(p.grad); mask[CLASSES] = 1; p.grad.mul_(mask)
        optimizer.step()
        # AdamW applies weight decay even to zero gradients; restore uncovered rows.
        with torch.no_grad():
            for p, base in zip(head.parameters(), model.classifier.parameters()):
                keep = torch.ones(p.shape[0], dtype=torch.bool, device=DEVICE); keep[CLASSES] = False
                p[keep] = base[keep]
    with torch.no_grad(): val = metrics(head(features), splits['val'])
    history.append(dict(epoch=epoch, **val))
    if (val['macro_top1'], -val['loss']) > (best_val['macro_top1'], -best_val['loss']):
        best = copy.deepcopy(head.state_dict()); best_val = val; best_epoch = epoch
    print('EPOCH', epoch, json.dumps(val), flush=True)
head.load_state_dict(best)
with torch.no_grad(): candidate_logits = head(features).detach()
candidate = {s: metrics(candidate_logits, ids) for s,ids in splits.items()}
model.classifier.load_state_dict(best)
model.config.gramo_base_revision = REV
model.config.gramo_experiment = 'commons-head-pilot-20261119'
model.save_pretrained(OUT/'candidate', safe_serialization=True)
processor.save_pretrained(OUT/'candidate')
report = dict(excluded_conflicting_page_ids=conflicting_page_ids, input_manifest_sha256=manifest_sha256, base=BASE, revision=REV, seed=SEED, selected_epoch=best_epoch,
    baseline=baseline, candidate=candidate, history=history, failed_downloads=failed,
    gpu=torch.cuda.get_device_name(0), python=platform.python_version(), torch=torch.__version__,
    seconds=time.monotonic()-started, classes=EXPECTED,
    deployment_approved=False,
    limitations=['Three weakly labelled Commons categories only; not a 114-class accuracy estimate.',
       'Base pretraining overlap unknown; these are not proven unseen images.',
       'No spoon-camera domain test, no non-food rejection calibration, no commercial data clearance.',
       'Frozen feature extractor: no inference latency improvement expected.',
       'Author and perceptual-hash grouping is conservative, not proof of plate identity.'])
(OUT/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
predictions = []
for i,r in enumerate(rows):
    predictions.append(dict(page_id=r['page_id'], label=r['label'], split=r['split'],
        baseline_top3=baseline_logits[i].topk(3).indices.tolist(),
        candidate_top3=candidate_logits[i].topk(3).indices.tolist()))
(OUT/'predictions.json').write_text(json.dumps(predictions, indent=2))
(OUT/'requirements-resolved.txt').write_bytes(subprocess.check_output(['python','-m','pip','freeze']))
(OUT/'checksums.json').write_text(json.dumps({str(p.relative_to(OUT)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (OUT/'candidate').glob('*') if p.is_file()},indent=2))
# Package only model/report/provenance, not public image binaries or duplicate base weights.
package = Path('gramo-pilot-results'); package.mkdir(exist_ok=True)
for name in ['candidate','report.json','predictions.json','manifest.json','checksums.json','requirements-resolved.txt']:
    src = OUT/name; dst = package/name
    if src.is_dir(): shutil.copytree(src,dst,dirs_exist_ok=True)
    else: shutil.copy2(src,dst)
shutil.make_archive('gramo-pilot-results','zip',package)
print('COMPLETE', json.dumps({'baseline_test':baseline['test'],'candidate_test':candidate['test'],
    'selected_epoch':best_epoch,'deployment_approved':False}), flush=True)
