#!/usr/bin/env python3
import argparse, pathlib, plistlib, shutil, subprocess, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
build = root / 'build'
build.mkdir(exist_ok=True)

parser = argparse.ArgumentParser()
parser.add_argument('--binary', type=pathlib.Path, default=None)
args = parser.parse_args()

if args.binary is not None:
    binary_src = args.binary
else:
    binpath = pathlib.Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip())
    binary_src = binpath / 'FokusBar'

iconset = build / 'FokusBar.iconset'
subprocess.run(['swift', str(root / 'Scripts/icon.swift'), str(iconset)], check=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(build / 'FokusBar.icns')], check=True)

with tempfile.TemporaryDirectory(dir=build, prefix='package-') as temp:
    app = pathlib.Path(temp) / 'FokusBar.app'
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    shutil.copy2(binary_src, contents / 'MacOS/FokusBar')
    subprocess.run(['/usr/bin/strip', '-S', str(contents / 'MacOS/FokusBar')], check=True)
    shutil.copy2(build / 'FokusBar.icns', contents / 'Resources/FokusBar.icns')
    shutil.copy2(root / 'Docs/ANLEITUNG.md', contents / 'Resources/ANLEITUNG.md')
    if (root / 'Resources/Sounds').is_dir():
        shutil.copytree(root / 'Resources/Sounds', contents / 'Resources/Sounds')
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleName': 'FokusBar', 'CFBundleDisplayName': 'FokusBar',
        'CFBundleIdentifier': 'de.justin.fokusbar', 'CFBundleExecutable': 'FokusBar',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
        'CFBundleIconFile': 'FokusBar', 'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True, 'NSHighResolutionCapable': True,
        'NSPrincipalClass': 'NSApplication', 'CFBundleDevelopmentRegion': 'de',
        'FokusBarLocalNotificationsOnly': True,
        'NSAppleEventsUsageDescription': 'FokusBar steuert auf Wunsch Spotify für deine Fokus-Musik und schließt während aktiver Fokus-Sitzungen blockierte Webseiten im Browser.',
        'NSHumanReadableCopyright': 'FokusBar · Lokal auf deinem Mac'
    }))
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'de.justin.fokusbar', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    target = build / 'FokusBar.app'
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(app, target)
print(target)
