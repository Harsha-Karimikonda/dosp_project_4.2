#!/usr/bin/env python3
"""Extract each submission and exercise its documented build/test/demo workflow."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
# Validation on hosts with a partial OTP install can use an external overlay.
local_crypto = root / 'build/runtime/crypto'
if local_crypto.is_dir():
    env.setdefault('PROJECT4_CRYPTO_ROOT', str(local_crypto))
for archive, mode in [('project4.zip', 'base'), ('project4-bonus.zip', 'bonus')]:
    with tempfile.TemporaryDirectory(prefix='project42-extracted-') as tmp:
        destination = Path(tmp)
        with zipfile.ZipFile(root / archive) as z:
            names = z.namelist()
            assert all(not n.endswith(('.pdf', '.pem', '.beam', '.so')) for n in names)
            assert all(not n.startswith(('build/', '/')) and '..' not in Path(n).parts for n in names)
            assert z.testzip() is None
        subprocess.run(['unzip', '-q', str(root / archive), '-d', str(destination)], check=True)
        assert f'mode=>{mode}' in (destination / 'config/default.config').read_text()
        for command in [('build',), ('test',), *([('test-bonus',)] if mode == 'bonus' else []), ('demo',)]:
            print(f'EXTRACTED {archive}: {" ".join(command)}', flush=True)
            result = subprocess.run([str(destination / 'scripts/project4'), *command], cwd=destination,
                                    env=env, capture_output=True, text=True, timeout=90)
            print(result.stdout, end='', flush=True)
            if result.returncode:
                print(result.stderr, flush=True)
                raise SystemExit(result.returncode)
        print(f'ARCHIVE PASS {archive} default={mode}', flush=True)
print('Both extracted archives passed build, applicable tests, and multi-process demos.', flush=True)
