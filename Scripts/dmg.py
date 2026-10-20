#!/usr/bin/env python3
"""Build a Universal (arm64 + x86_64) FokusBar.app release and package it into a reproducible DMG."""
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
prefix_args = ['-Xswiftc', '-file-prefix-map', '-Xswiftc', f'{root}=.']
subprocess.run(['swift', 'build', '--product', 'FokusBar', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64', *prefix_args], cwd=root, check=True)
bin_path = subprocess.check_output(['swift', 'build', '--product', 'FokusBar', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64', *prefix_args, '--show-bin-path'], cwd=root, text=True).strip()
subprocess.run(['python3', 'Scripts/package.py', '--binary', str(Path(bin_path) / 'FokusBar')], cwd=root, check=True)

binary = root / 'build/FokusBar.app/Contents/MacOS/FokusBar'
archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
assert set(archs) == {'arm64', 'x86_64'}, archs

with tempfile.TemporaryDirectory(prefix='dmg-', dir=root / 'build') as temp:
    stage = Path(temp)
    shutil.copytree(root / 'build/FokusBar.app', stage / 'FokusBar.app')
    (stage / 'Programme').symlink_to('/Applications')
    shutil.copyfile(root / 'Docs/ANLEITUNG.md', stage / 'ANLEITUNG.md')
    dmg = root / 'build/FokusBar-1.0.0.dmg'
    subprocess.run(['hdiutil', 'create', '-ov', '-format', 'UDZO', '-fs', 'HFS+', '-volname', 'FokusBar', '-srcfolder', str(stage), str(dmg)], check=True)
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
print(dmg)
