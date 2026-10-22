from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import shutil
import subprocess
import sys

work = Path('D:/.codexfile/work/player-jump-eyes')
assets = Path('D:/Project/HD-2DMap/demoWithMeowa/1/assets/meowa/player')
cli = 'C:/Users/PC/.codex/skills/game-assets/meowart_api.py'
backup = work/'originals'
backup.mkdir(parents=True, exist_ok=True)
for name in ['air_00.png','air_03.png','idle_00.png','animations.tres','sources.json']:
    shutil.copy2(assets/name, backup/name)

prompt = '修正第一张人物的眼睛，参照第二张站立图的眼睛，将眼白收回到原来的像素大小和形状，保持相同的瞳孔与朝向。只改眼部，保持第一张的动作、头发、脸型、衣服、像素大小和画布位置。'
def edit(index):
    args = [sys.executable,cli,'image-edit-run','--reference-image',str(backup/f'air_{index:02}.png'),'--reference-image',str(backup/'idle_00.png'),'--prompt',prompt,'--mode','pixel','--strict','--generation-model','nano-banana','--generation-speed','normal','--resolution','1K','--remove-bg-method','standard','--output-dir',str(work/f'edit-{index:02}')]
    print(f'START eye edit {index}',flush=True)
    result = subprocess.run(args,cwd='D:/Project/HD-2DMap',capture_output=True,text=True,encoding='utf-8',errors='replace')
    print(f'FINISH eye edit {index} exit={result.returncode}\n{result.stdout}\n{result.stderr}',flush=True)
    return result.returncode
with ThreadPoolExecutor(max_workers=2) as pool:
    codes = list(pool.map(edit,[0,3]))
sys.exit(0 if not any(codes) else 1)
