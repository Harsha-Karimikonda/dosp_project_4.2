#!/usr/bin/env python3
"""Create self-contained source archives; never include report PDF or private keys."""
import argparse
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--final', action='store_true')
args = p.parse_args()
metadata = json.loads((root / 'config/submission.json').read_text())
missing = []
for name in ('main', 'bonus'):
    if not (root / 'videos' / f'{name}.mp4').is_file():
        missing.append(f'videos/{name}.mp4')
    if not metadata.get(f'{name}_youtube_url', '').startswith(('https://youtu.be/', 'https://www.youtube.com/')):
        missing.append(f'{name}_youtube_url in config/submission.json')
if missing:
    print('Video materials pending: ' + ', '.join(missing))
    if args.final:
        raise SystemExit('Final packaging refused: add the recordings and YouTube links first.')

files = []
for directory in ('src', 'test', 'scripts', 'config', 'docs', 'evidence'):
    files.extend(x for x in (root / directory).rglob('*') if x.is_file()
                 and x.suffix not in ('.pem', '.pdf', '.pyc') and '__pycache__' not in x.parts)
files.extend(root / x for x in ('README.md', 'SUBMISSION_COMMENT.txt', '.gitignore'))
for mode, archive in (('base', 'project4.zip'), ('bonus', 'project4-bonus.zip')):
    temp = root / (archive + '.tmp')
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(files):
            relative = path.relative_to(root).as_posix()
            if relative == 'config/default.config':
                z.writestr(relative, '#{mode=>' + mode + '}.\n')
            else:
                z.write(path, relative)
        video = root / 'videos' / ('main.mp4' if mode == 'base' else 'bonus.mp4')
        if video.is_file():
            z.write(video, f'videos/{video.name}')
    temp.replace(root / archive)
    print(f'Created {archive} ({(root / archive).stat().st_size:,} bytes), default mode={mode}')
