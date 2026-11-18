"""Package the pinned CI artifact only when invoked by Apelin's producer."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile

COMMIT = '84ae41a5a8e73ed5c7c838338aae53687ec10d95'
ZIP_SHA256 = '528dba50aa11504e2afb41a805fa4b11bade68164401980dd434ffb402a95001'
DYLIB_SHA256 = '29ede482ec30b98596f32a2a4a1c831b8fd4fb2daec8c5446f5485af90356f92'

def package(root, archive, version):
    required = ('APELIN_PROJECT_ROOT', 'APELIN_PACKAGE_DIR', 'APELIN_BOOTSTRAP',
                'APELIN_ARCHITECTURE', 'APELIN_BUILD_ID', 'TMPDIR')
    env = {key: os.environ[key] for key in required}
    assert all(env.values()) and 'APELIN_PREFIX' in os.environ
    if env['APELIN_BOOTSTRAP'] != 'roothide':
        raise SystemExit('Pinned CI artifact is arm64e only; rootless requires a separate multi-architecture build')
    assert env['APELIN_ARCHITECTURE'] == 'iphoneos-arm64e'
    assert os.environ['APELIN_PREFIX'] == ''
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == ZIP_SHA256
    with zipfile.ZipFile(archive) as z:
        receipt = json.loads(z.read('verification.json'))
        data = z.read('NingKeyboardGlass.dylib')
        assert receipt['commit'] == COMMIT
        assert receipt['sha256'] == DYLIB_SHA256 == hashlib.sha256(data).hexdigest()
        assert receipt['architecture'] == 'arm64e' and receipt['strict_signature'] is True
        magic, cpu, subtype = struct.unpack_from('<III', data)
        assert magic == 0xfeedfacf and cpu == 0x100000c and subtype & 0xffffff == 2
        assert b'ApelinLoaded %{public}s' in data and COMMIT.encode() in data
        for name in ('LICENSE', 'NOTICE', 'UPSTREAM.json'):
            assert z.read('Theseus-' + name) == (root / 'Vendor/Theseus' / name).read_bytes()
        with tempfile.TemporaryDirectory(prefix='keyboardglass-ci-', dir=env['TMPDIR']) as tmp:
            stage = Path(tmp) / 'stage'
            libs = stage / 'Library/MobileSubstrate/DynamicLibraries'
            libs.mkdir(parents=True)
            dylib = libs / 'NingKeyboardGlass.dylib'
            dylib.write_bytes(data)
            subprocess.run(['ldid', '-S', str(dylib)], check=True)
            (libs / 'NingKeyboardGlass.plist').write_bytes(plistlib.dumps({'Filter': {'Bundles': ['com.apple.UIKit']}}))
            docs = stage / 'usr/share/doc/com.ning.keyboardglass'
            docs.mkdir(parents=True)
            for name in ('LICENSE', 'NOTICE', 'UPSTREAM.json'):
                (docs / ('Theseus-' + name)).write_bytes(z.read('Theseus-' + name))
            (docs / 'ci-verification.json').write_bytes(z.read('verification.json'))
            provenance = {'apelinBuildID': env['APELIN_BUILD_ID'], 'compiledCommit': COMMIT,
                          'compiledLoadMarker': 'ApelinLoaded ' + COMMIT,
                          'artifactSHA256': ZIP_SHA256, 'inputDylibSHA256': DYLIB_SHA256,
                          'packagedDylibSHA256': hashlib.sha256(dylib.read_bytes()).hexdigest(),
                          'runtimeTested': False}
            (docs / 'package-provenance.json').write_text(json.dumps(provenance, indent=2))
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
Description: Theseus Metal keyboard background material (experimental).
''')
            output = Path(env['APELIN_PACKAGE_DIR']) / f'com.ning.keyboardglass_{version}_iphoneos-arm64e.deb'
            subprocess.run(['dpkg-deb', '-b', '--root-owner-group', str(stage), str(output)], check=True)
            print('Packaged verified CI artifact; load marker remains compiled commit ' + COMMIT)
