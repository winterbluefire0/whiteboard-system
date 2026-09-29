"""Local USB capture pipeline. JSON output is consumed by Whiteboard Capture.app."""
import argparse
import datetime
import fcntl
import json
from pathlib import Path
import subprocess
import sys
import uuid

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / 'quick-capture/state'


def validate_corners(corners, width, height):
    pts = np.asarray(corners, dtype=np.float32)
    if pts.shape != (4, 2) or not np.isfinite(pts).all():
        raise ValueError('请选择四个有效角点。')
    if (pts < 0).any() or (pts[:, 0] >= width).any() or (pts[:, 1] >= height).any():
        raise ValueError('角点超出图片范围，请重新调试。')
    if not cv2.isContourConvex(pts) or cv2.contourArea(pts, oriented=True) <= width * height * 0.1:
        raise ValueError('请依次选择左上、右上、右下、左下，且覆盖完整白板。')
    return pts


def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['preview', 'capture'])
    p.add_argument('--calibration', type=Path, default=STATE/'calibration.json')
    args = p.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE/'capture.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('已有拍照任务正在进行，请稍等。')
        config = None
        if args.mode == 'capture':
            if not args.calibration.is_file():
                raise RuntimeError('请先打开“调试位置”并确认白板四角。')
            config = json.loads(args.calibration.read_text())
        stamp = datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S-%f')
        original = ROOT/'captures'/f'quick-{stamp}-{uuid.uuid4().hex[:6]}.jpg'
        cmd = [sys.executable, str(ROOT/'camera_usb.py'), 'photo', '--output', str(original)]
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=55)
        if proc.returncode:
            raise RuntimeError('XIAO 拍照失败，请检查 USB 连接。\n'+(proc.stderr or proc.stdout)[-1200:])
        image = cv2.imread(str(original))
        if image is None:
            raise RuntimeError('无法解码本次照片。')
        height, width = image.shape[:2]
        result = {'original':str(original), 'width':width, 'height':height,
                  'mode':args.mode, 'saved_at':datetime.datetime.now().astimezone().isoformat()}
        if config:
            if config['image_size'] != [width,height]:
                raise RuntimeError('相机尺寸变化，请重新调试位置。原图已保留。')
            corners = validate_corners(config['corners'],width,height)
            # Fixed calibration is a user-confirmed setup, not automatic board tracking.
            dest = ROOT/'enhancements/quick-capture'
            cmd = [sys.executable,str(ROOT/'enhance_whiteboard.py'),str(original),
                   '--output',str(dest),'--corners'] + [f'{x},{y}' for x,y in corners]
            proc = subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=40)
            if proc.returncode:
                raise RuntimeError('照片已保存，但增强失败。\n'+proc.stderr[-1000:])
            folder = dest/original.stem
            result.update({'color':str(folder/'color.png'),'bw':str(folder/'bw.png'),
                           'folder':str(folder),'calibration_id':config.get('id'),
                           'corners':config['corners']})
            (folder/'capture.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
        print(json.dumps(result,ensure_ascii=False),flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'error':str(exc)},ensure_ascii=False),flush=True)
        sys.exit(1)
