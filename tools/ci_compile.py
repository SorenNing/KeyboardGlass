"""macOS CI compile check only. Does not produce a Debian package."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)

def main():
    vendor = ROOT / 'Vendor/Theseus'
    manifest = json.loads((vendor / 'UPSTREAM.json').read_text())
    for name, digest in manifest['sha256'].items():
        assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == digest, name
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    scratch = ROOT / '.build'
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch) as tmp:
        work = Path(tmp)
        src = work / 'Sources'
        shutil.copytree(vendor / 'Sources/Theseus', src)
        switch = src / 'Components/TheseusSwitch.swift'
        text = switch.read_text()
        # No SwiftPM resource bundle is emitted by this direct compiler build.
        # Preserve upstream's explicit English default accessibility values.
        for value, state in [('On', 'on'), ('Off', 'off')]:
            old = f'NSLocalizedString("{value}", tableName: nil, bundle: .module, value: "{value}", comment: "Spoken value of a switch that is {state}")'
            assert text.count(old) == 1
            text = text.replace(old, json.dumps(value))
        switch.write_text(text)
        view = src / 'Core/TheseusView.swift'
        text = view.read_text()
        old = 'let shouldUseFallback = TheseusSettings.shared.shouldUseFallback'
        assert text.count(old) == 1
        view.write_text(text.replace(old, 'let shouldUseFallback = false'))
        metal = src / 'Rendering/MetalContext.swift'
        text = metal.read_text()
        start = text.index('        let bundle = Bundle.module')
        end = text.index('\n    private func setupPipelineStates()', start)
        metal.write_text(text[:start] + '''        do {
            return try device.makeLibrary(source: KeyboardShader.source, options: nil)
        } catch {
            print("KeyboardGlass: shader compilation failed: \\(error)")
            return nil
        }
    }
''' + text[end:])
        shader = (src / 'Shaders/TheseusShaders.metal').read_text()
        assert '\"\"\"' not in shader
        (src / 'KeyboardShader.swift').write_text('enum KeyboardShader { static let source = #\"\"\"\n' + shader + '\n\"\"\"# }\n')
        target = 'arm64e-apple-ios17.0'
        obj = work / 'hook.o'
        marker = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', target, '-isysroot', sdk,
             '-c', '-fobjc-arc', '-fblocks', '-O2', '-DAPELIN_BUILD_ID=' + json.dumps(marker),
             'KeyboardBackground.m', '-o', obj])
        dylib = output / 'NingKeyboardGlass.dylib'
        sources = sorted(src.rglob('*.swift')) + sorted((ROOT / 'Sources').glob('*.swift'))
        run(['xcrun', '--sdk', 'iphoneos', 'swiftc', '-target', target, '-sdk', sdk,
             '-swift-version', '5', '-O', '-module-name', 'KeyboardGlassMaterial', '-emit-library',
             *sources, obj, '-framework', 'UIKit', '-framework', 'Metal', '-framework', 'MetalKit',
             '-framework', 'QuartzCore', '-framework', 'IOSurface', '-framework', 'CoreVideo',
             '-Xlinker', '-install_name', '-Xlinker', '@rpath/NingKeyboardGlass.dylib', '-o', dylib])
        run(['codesign', '--force', '--sign', '-', dylib])
        run(['codesign', '--verify', '--strict', '--all-architectures', dylib])
        data = dylib.read_bytes()
        assert struct.unpack_from('<I', data)[0] == 0xfeedfacf
        assert struct.unpack_from('<I', data, 8)[0] & 0xffffff == 2
        receipt = {'commit': marker, 'sha256': hashlib.sha256(data).hexdigest(),
                   'architecture': 'arm64e', 'strict_signature': True,
                   'runtime_tested': False, 'package_produced': False}
        (output / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
        for name in ('LICENSE', 'NOTICE', 'UPSTREAM.json'):
            shutil.copyfile(vendor / name, output / ('Theseus-' + name))

if __name__ == '__main__':
    main()
