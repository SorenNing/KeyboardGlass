"""Verify and package original baseline CI output inside Apelin only."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

COMMIT = '5f41d796aa8bb2dbf374ce6c18775b0d71447f45'
ZIP_SHA256 = '5577ce3231c505e65a3dfe5f793168fa1599c6033d419aa0dc7cd795a4eca991'
BASE = '82d5fc92f415391a42ae6a20ca5a046dac7221f0'

def package(root, archive, version):
    env = {k: os.environ[k] for k in ('APELIN_PROJECT_ROOT', 'APELIN_PACKAGE_DIR', 'APELIN_BOOTSTRAP', 'APELIN_ARCHITECTURE', 'APELIN_BUILD_ID', 'TMPDIR')}
    assert all(env.values())
    assert env['APELIN_BOOTSTRAP'] == 'roothide' and env['APELIN_ARCHITECTURE'] == 'iphoneos-arm64e'
    assert os.environ['APELIN_PREFIX'] == ''
    for name in ('KeyboardBackground.m', 'Material.h', 'GlassBackground.png'):
        assert (root / name).read_bytes() == (root / 'Baseline/0.1.0' / name).read_bytes()
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == ZIP_SHA256
    with zipfile.ZipFile(archive) as z:
        receipt = json.loads(z.read('verification.json'))
        data = z.read('NingKeyboardGlass.dylib')
        assert receipt['commit'] == COMMIT and receipt['sourceBaseline'] == BASE
        assert receipt['strict_signature'] is True and receipt['architecture'] == 'arm64e'
        assert hashlib.sha256(data).hexdigest() == receipt['sha256']
        assert struct.unpack_from('<I', data, 8)[0] == 0x80000002
        assert b'NGTheseusBridge' not in data and b'/usr/lib/swift/' not in data
        with tempfile.TemporaryDirectory(prefix='keyboardglass-rollback-', dir=env['TMPDIR']) as tmp:
            stage = Path(tmp) / 'stage'
            libs = stage / 'Library/MobileSubstrate/DynamicLibraries'
            libs.mkdir(parents=True)
            dylib = libs / 'NingKeyboardGlass.dylib'
            dylib.write_bytes(data)
            subprocess.run(['ldid', '-S', str(dylib)], check=True)
            (libs / 'NingKeyboardGlass.plist').write_bytes(plistlib.dumps({'Filter': {'Bundles': ['com.apple.UIKit']}}))
            docs = stage / 'usr/share/doc/com.ning.keyboardglass'
            docs.mkdir(parents=True)
            (docs / 'ci-verification.json').write_bytes(z.read('verification.json'))
            (docs / 'package-provenance.json').write_text(json.dumps({'apelinBuildID': env['APELIN_BUILD_ID'], 'compiledCommit': COMMIT, 'sourceBaseline': BASE, 'artifactSHA256': ZIP_SHA256, 'runtimeTested': False}, indent=2))
            control = stage / 'DEBIAN'
            control.mkdir()
            (control / 'control').write_text(f'''Package: com.ning.keyboardglass
Name: Ning Keyboard Glass
Version: {version}
Architecture: iphoneos-arm64e
Maintainer: Ning
Author: Ning
Section: Tweaks
Depends: firmware (>= 17.0), mobilesubstrate
Description: Original 0.1.0 static keyboard background restored.
''')
            output = Path(env['APELIN_PACKAGE_DIR']) / f'com.ning.keyboardglass_{version}_iphoneos-arm64e.deb'
            subprocess.run(['dpkg-deb', '-b', '--root-owner-group', str(stage), str(output)], check=True)
