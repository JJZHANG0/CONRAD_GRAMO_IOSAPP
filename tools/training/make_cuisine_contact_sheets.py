#!/usr/bin/env python3
"""Create numbered local review sheets. This does not approve labels for training."""
import argparse,json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageOps
p=argparse.ArgumentParser();p.add_argument('root',type=Path);args=p.parse_args()
rows=json.loads((args.root/'manifest.json').read_text())
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',13) if Path('/System/Library/Fonts/Supplemental/Arial.ttf').exists() else ImageFont.load_default()
out=args.root/'contact-sheets';out.mkdir(exist_ok=True)
for start in range(0,len(rows),24):
 batch=rows[start:start+24];sheet=Image.new('RGB',(960,math.ceil(len(batch)/6)*175),'white');draw=ImageDraw.Draw(sheet)
 for i,r in enumerate(batch):
  x,y=(i%6)*160,(i//6)*175
  with Image.open(args.root/r['local_path']) as im:
   im=ImageOps.exif_transpose(im).convert('RGB');im.thumbnail((152,125));sheet.paste(im,(x+(160-im.width)//2,y))
  draw.text((x+3,y+127),str(r['page_id']),font=font,fill='black')
  draw.text((x+3,y+145),r['dish_ids'][0][:23],font=font,fill='black')
 sheet.save(out/f'review-{start//24+1:02d}.jpg',quality=90)
print('Review sheets:',out)
