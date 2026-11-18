"""Compile the original 0.1.0 implementation; never produce a package here."""
import hashlib
import json
from pathlib import Path
import subprocess
import struct

ROOT = Path(__file__).resolve().parents[1]
BASE = '82d5fc92f415391a42ae6a20ca5a046dac7221f0'

def run(args):
    subprocess.run(args, cwd=ROOT, check=True)

def main():
    for name in ('Material.h', 'GlassBackground.png'):
        assert (ROOT / name).read_bytes() == subprocess.check_output(['git', 'show', BASE + ':' + name], cwd=ROOT)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    out = ROOT / 'dist'
    out.mkdir(exist_ok=True)
    lib = out / 'NingKeyboardGlass.dylib'
    run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64e-apple-ios15.0', '-isysroot', sdk,
         '-dynamiclib', '-fobjc-arc', '-fblocks', '-O2', '-Wall', '-Wextra', '-Werror', 'KeyboardBackground.m',
         '-framework', 'UIKit', '-framework', 'Foundation', '-framework', 'CoreGraphics',
         '-install_name', '/Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib', '-o', str(lib)])
    run(['codesign', '--force', '--sign', '-', str(lib)])
    run(['codesign', '--verify', '--strict', '--all-architectures', str(lib)])
    data = lib.read_bytes()
    assert struct.unpack_from('<I', data, 8)[0] == 0x80000002
    receipt = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'sourceBaseline': BASE, 'sha256': hashlib.sha256(data).hexdigest(),
               'architecture': 'arm64e', 'strict_signature': True, 'runtime_tested': False}
    (out / 'verification.json').write_text(json.dumps(receipt, indent=2))

if __name__ == '__main__':
    main()
