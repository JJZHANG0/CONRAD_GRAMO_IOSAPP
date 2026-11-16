#!/usr/bin/env python3
"""Offline-evaluation export, immutable revision, safetensors only, no remote code.
python tools/export_chinese_food_coreml.py --images real1.jpg real2.jpg --output artifacts/chinese-food
No image supplied => conversion is allowed, but parity/evaluation is explicitly unverified.
"""
import argparse, hashlib, json, importlib.metadata, platform
from pathlib import Path
import numpy as np
import torch
from PIL import Image, ImageOps
from huggingface_hub import hf_hub_download
from transformers import AutoImageProcessor, ResNetForImageClassification

REPO = 'Albertbeta123/resnet-50-chinese-food'
REVISION = '1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c'
FILES = ['model.safetensors', 'config.json', 'preprocessor_config.json', 'README.md']

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--images', nargs='*', default=[])
    ap.add_argument('--output', type=Path, default=Path('artifacts/chinese-food'))
    ap.add_argument('--download-only', action='store_true')
    args = ap.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    source = args.output / 'source'; source.mkdir(exist_ok=True)
    hashes = {}
    for name in FILES:
        path = hf_hub_download(REPO, name, revision=REVISION, local_dir=str(source))
        hashes[name] = sha(path)
    # Fail closed if pinned config differs from the reviewed inputs checked into this repo.
    reviewed = Path(__file__).parent / 'model-source'
    expected_hashes = json.loads((reviewed/'checksums.json').read_text())
    assert hashes == expected_hashes, 'Pinned source checksum mismatch'
    for name in ['config.json','preprocessor_config.json']:
        assert hashes[name] == sha(reviewed/name), f'Configuration drift: {name}'
    manifest = {'repo': REPO, 'revision': REVISION, 'sha256': hashes,
                'dependencies': {p: importlib.metadata.version(p) for p in ['torch','transformers','coremltools','safetensors','Pillow','numpy','huggingface-hub']},
                'platform': platform.platform(), 'license': 'Model card: Apache-2.0; training data rights not cleared; evaluation only',
                'normalization': 'Inside model only: (RGB / 255 - mean) / std',
                'preprocess': 'EXIF transpose, RGB, PIL bicubic shortest edge 256, center crop 224',
                'minimum_ios': '18', 'parity': 'not run'}
    (args.output/'manifest.json').write_text(json.dumps(manifest, indent=2))
    if args.download_only: return
    processor = AutoImageProcessor.from_pretrained(source, trust_remote_code=False, local_files_only=True, use_fast=False)
    model = ResNetForImageClassification.from_pretrained(source, use_safetensors=True, trust_remote_code=False, local_files_only=True).eval().cpu()
    config = json.loads((source/'config.json').read_text())
    labels = [config['id2label'][str(i)] for i in range(len(config['id2label']))]
    translations = json.loads((reviewed/'labels-zh.json').read_text())
    # Keys are numeric class IDs, not English strings: upstream IDs 6 and 7 share a label.
    assert len(translations) == len(labels)
    metadata = [{'id': str(i), 'rawLabel': label, 'name': translations[str(i)]} for i,label in enumerate(labels)]
    (args.output/'ChineseFoodLabels.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    class RGBClassifier(torch.nn.Module):
        def __init__(self):
            super().__init__(); self.net = model
            self.register_buffer('mean', torch.tensor(processor.image_mean).reshape(1,3,1,1))
            self.register_buffer('std', torch.tensor(processor.image_std).reshape(1,3,1,1))
        def forward(self, rgb):
            return torch.softmax(self.net(pixel_values=(rgb/255-self.mean)/self.std).logits, dim=-1)
    wrapped = RGBClassifier().eval()
    samples = []
    def top3(scores):
        ids = np.argsort(-scores, kind='stable')[:3]
        return [{'id': int(i), 'label': labels[int(i)], 'score': float(scores[i])} for i in ids]
    for filename in args.images:
        img = ImageOps.exif_transpose(Image.open(filename)).convert('RGB')
        raw = processor(img, return_tensors='pt', do_normalize=False, do_rescale=False)['pixel_values'].float()
        reference = processor(img, return_tensors='pt')['pixel_values']
        with torch.no_grad():
            original = torch.softmax(model(pixel_values=reference).logits, dim=-1)[0].numpy()
            wrapped_scores = wrapped(raw)[0].numpy()
        assert np.max(np.abs(original-wrapped_scores)) < 1e-5
        prepared = Image.fromarray(raw[0].permute(1,2,0).numpy().astype('uint8'))
        prepared.save(args.output/(Path(filename).stem+'-prepared.png'))
        entry = {'image': str(filename), 'sha256': sha(filename), 'pytorch': top3(original)}
        print(json.dumps(entry, ensure_ascii=False), flush=True)
        samples.append((entry, prepared, original))
    # Actual image Top 3 runs above before conversion.
    import coremltools as ct
    traced = torch.jit.trace(wrapped, torch.zeros(1,3,224,224))
    ml = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS18,
                    inputs=[ct.ImageType(name='image', shape=(1,3,224,224), color_layout=ct.colorlayout.RGB, scale=1.0)],
                    outputs=[ct.TensorType(name='probabilities')], compute_precision=ct.precision.FLOAT32,
                    compute_units=ct.ComputeUnit.CPU_ONLY)
    ml.user_defined_metadata['model_revision'] = REVISION
    ml.user_defined_metadata['source'] = REPO
    ml.user_defined_metadata['labels_json'] = json.dumps(metadata, ensure_ascii=False)
    ml.user_defined_metadata['normalization'] = manifest['normalization']
    ml.save(str(args.output/'ChineseFood.mlpackage'))
    reports = []
    for entry, image, scores in samples:
        output = ml.predict({'image': image})['probabilities'].reshape(-1)
        entry['coreml'] = top3(output); entry['max_score_difference'] = float(np.max(np.abs(output-scores)))
        entry['same_top3'] = [x['id'] for x in entry['pytorch']] == [x['id'] for x in entry['coreml']]
        reports.append(entry)
    (args.output/'parity.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2))
    manifest['parity'] = 'passed' if reports and all(x['same_top3'] and x['max_score_difference'] < 0.001 for x in reports) else 'unverified_or_failed'
    manifest['output_sha256'] = {str(p.relative_to(args.output)):sha(p) for p in (args.output/'ChineseFood.mlpackage').rglob('*') if p.is_file()}
    (args.output/'manifest.json').write_text(json.dumps(manifest, indent=2))
    if reports and manifest['parity'] != 'passed': raise RuntimeError('Parity failed; inspect crop/interpolation/normalization/class order')

if __name__ == '__main__': main()
