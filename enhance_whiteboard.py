"""Deterministic scan-style enhancement; never reconstruct missing strokes.

Usage: python enhance_whiteboard.py image.jpg --corners x,y x,y x,y x,y
Corners: top-left, top-right, bottom-right, bottom-left, in source pixels.
"""
import argparse
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('image', type=Path)
p.add_argument('--corners', nargs=4, required=True)
p.add_argument('--output', type=Path, default=Path('enhancements'))
p.add_argument('--comparison', action='store_true', help='Also export rectified and comparison images')
args = p.parse_args()
corners = np.array([[float(v) for v in s.split(',')] for s in args.corners], np.float32)
src = cv2.imread(str(args.image))
if src is None or corners.shape != (4, 2):
    raise SystemExit('Invalid source or corners')
width = round(max(np.linalg.norm(corners[1]-corners[0]), np.linalg.norm(corners[2]-corners[3])))
height = round(max(np.linalg.norm(corners[3]-corners[0]), np.linalg.norm(corners[2]-corners[1])))
dst = np.array([[0,0],[width-1,0],[width-1,height-1],[0,height-1]], np.float32)
matrix = cv2.getPerspectiveTransform(corners, dst)
rectified = cv2.warpPerspective(src, matrix, (width, height), flags=cv2.INTER_CUBIC)
# Broad illumination estimate. Channel-wise division also removes color cast.
smooth = cv2.bilateralFilter(rectified, 5, 15, 15)
background = cv2.GaussianBlur(smooth.astype(np.float32), (0,0), 35)
normalized = np.clip(smooth.astype(np.float32) / np.maximum(background, 1), 0, 1)
color = np.uint8(np.clip(255 - (1-normalized)*255*1.65, 0, 255))
args.output.mkdir(parents=True, exist_ok=True)
out = args.output / args.image.stem
out.mkdir(exist_ok=False)
shutil.copyfile(args.image, out / ('original' + args.image.suffix.lower()))
cv2.imwrite(str(out / 'color.png'), color)
# Darkest normalized channel retains red ink in the B/W reference copy.
ink_gray = np.min(color, axis=2)
bw = cv2.adaptiveThreshold(ink_gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                           cv2.THRESH_BINARY, 41, 12)
cv2.imwrite(str(out / 'bw.png'), bw)
if args.comparison:
    cv2.imwrite(str(out / 'rectified.png'), rectified)
    tiles=[]
    for name,img in [('ORIGINAL',src),('RECTIFIED',rectified),('COLOR ENHANCED',color),('BLACK & WHITE',bw)]:
        pil=Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB) if img.ndim==3 else img).convert('RGB')
        pil.thumbnail((760,560))
        tile=Image.new('RGB',(800,620),'#ededed')
        tile.paste(pil,((800-pil.width)//2,50+(560-pil.height)//2))
        ImageDraw.Draw(tile).text((20,18),name,fill='black')
        tiles.append(tile)
    sheet=Image.new('RGB',(1600,1240),'white')
    for i,tile in enumerate(tiles): sheet.paste(tile,((i%2)*800,(i//2)*620))
    sheet.save(out/'comparison.jpg',quality=93)
(out/'processing.json').write_text(json.dumps({
    'source':str(args.image.resolve()),'corners':corners.tolist(),
    'preferred_output':'color.png','comparison_exported':args.comparison,
    'saved_images':['original'+args.image.suffix.lower(),'color.png','bw.png'],
    'corners_selection':'manual for this photo; recalibrate if camera or board moves',
    'output_size':[width,height],'opencv':cv2.__version__,
    'background_sigma':35,'ink_gain':1.65,'adaptive_block_size':41,'adaptive_C':12,
    'limitations':['No recovery of erased or glare-obscured strokes',
                  'Enhancement can emphasize erasure residue or remove faint ink',
                  'Aspect ratio estimated from projected edges, not measured board dimensions']
},ensure_ascii=False,indent=2))
print(out.resolve())
