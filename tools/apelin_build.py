"""Only apelin_project_build may invoke this package producer."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

VERSION = '0.2.0-theseus6'
ROOT = Path(__file__).resolve().parents[1]

def run(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)

def main():
    archive = ROOT / '.build/ci-artifacts/keyboard-glass-theseus-64e.zip'
    if archive.is_file():
        from package_ci import package
        package(ROOT, archive, VERSION)
        return
    required = ('APELIN_PROJECT_ROOT', 'APELIN_PACKAGE_DIR', 'APELIN_BOOTSTRAP',
                'APELIN_ARCHITECTURE', 'APELIN_BUILD_ID', 'TMPDIR', 'SDKROOT')
    env = {key: os.environ[key] for key in required}
    if not all(env.values()) or 'APELIN_PREFIX' not in os.environ:
        raise SystemExit('Missing Apelin build environment')
    bootstrap = env['APELIN_BOOTSTRAP']
    assert bootstrap in ('roothide', 'rootless')
    prefix = os.environ['APELIN_PREFIX']
    assert prefix == ('' if bootstrap == 'roothide' else '/var/jb')
    expected_arch = 'iphoneos-arm64e' if bootstrap == 'roothide' else 'iphoneos-arm64'
    assert env['APELIN_ARCHITECTURE'] == expected_arch
    architectures = ['arm64e'] if bootstrap == 'roothide' else ['arm64', 'arm64e']
    for tool in ['swiftc', 'clang', 'ldid', 'dpkg-deb'] + (['lipo'] if len(architectures) > 1 else []):
        if not shutil.which(tool):
            raise SystemExit(f'Required tool unavailable: {tool}; configure a Swift-capable toolchain')
    vendor = ROOT / 'Vendor/Theseus'
    manifest = json.loads((vendor / 'UPSTREAM.json').read_text())
    for name, digest in manifest['sha256'].items():
        assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == digest, name
    # Patch compilation copies only; preserve the fixed upstream originals.
    scratch = ROOT / '.build'
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='keyboardglass-', dir=scratch) as tmp:
        work = Path(tmp)
        src = work / 'Sources'
        shutil.copytree(vendor / 'Sources/Theseus', src)
        switch = src / 'Components/TheseusSwitch.swift'
        text = switch.read_text()
        # Direct swiftc builds do not emit a SwiftPM resource bundle.
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
        text = text[:start] + '''        // Compile the original shader, never the host application's library.
        do {
            return try device.makeLibrary(source: KeyboardShader.source, options: nil)
        } catch {
            print("KeyboardGlass: Theseus shader compilation failed: \\(error)")
            return nil
        }
    }
''' + text[end:]
        metal.write_text(text)
        shader = (src / 'Shaders/TheseusShaders.metal').read_text()
        assert '\"\"\"' not in shader
        (src / 'KeyboardShader.swift').write_text('enum KeyboardShader { static let source = #\"\"\"\n' + shader + '\n\"\"\"# }\n')
        stage = work / 'stage'
        libraries = stage / prefix.lstrip('/') / 'Library/MobileSubstrate/DynamicLibraries'
        libraries.mkdir(parents=True)
        slices = []
        # Relative compiler paths avoid roothide shell/kernel path differences.
        rel = lambda p: os.path.relpath(p, ROOT)
        for arch in architectures:
            target = f'{arch}-apple-ios17.0'
            obj = work / f'hook-{arch}.o'
            run(['clang', '-target', target, '-isysroot', env['SDKROOT'], '-c', '-fobjc-arc', '-fblocks', '-O2',
                 '-DAPELIN_BUILD_ID=' + json.dumps(env['APELIN_BUILD_ID']), 'KeyboardBackground.m', '-o', rel(obj)])
            output = work / f'material-{arch}.dylib'
            sources = sorted(src.rglob('*.swift')) + sorted((ROOT / 'Sources').glob('*.swift'))
            run(['swiftc', '-target', target, '-sdk', env['SDKROOT'], '-swift-version', '5', '-O',
                 '-module-name', 'KeyboardGlassMaterial', '-emit-library',
                 *[rel(p) for p in sources], rel(obj),
                 '-framework', 'UIKit', '-framework', 'Metal', '-framework', 'MetalKit',
                 '-framework', 'QuartzCore', '-framework', 'IOSurface', '-framework', 'CoreVideo',
                 '-Xlinker', '-install_name', '-Xlinker', '@rpath/NingKeyboardGlass.dylib', '-o', rel(output)])
            slices.append(output)
        dylib = libraries / 'NingKeyboardGlass.dylib'
        if len(slices) == 1:
            shutil.copyfile(slices[0], dylib)
        else:
            run(['lipo', '-create', *map(rel, slices), '-output', rel(dylib)])
        run(['ldid', '-S', rel(dylib)])
        (libraries / 'NingKeyboardGlass.plist').write_bytes(plistlib.dumps({'Filter': {'Bundles': ['com.apple.UIKit']}}))
        docs = stage / prefix.lstrip('/') / 'usr/share/doc/com.ning.keyboardglass'
        docs.mkdir(parents=True)
        for name in ('LICENSE', 'NOTICE', 'UPSTREAM.json'):
            shutil.copyfile(vendor / name, docs / ('Theseus-' + name))
        control = stage / 'DEBIAN'
        control.mkdir()
        (control / 'control').write_text(f'''Package: com.ning.keyboardglass
Name: Ning Keyboard Glass
Version: {VERSION}
Architecture: {expected_arch}
Maintainer: Ning
Author: Ning
Section: Tweaks
Depends: firmware (>= 17.0), mobilesubstrate
Description: Theseus Metal keyboard background material (experimental).
''')
        output = Path(env['APELIN_PACKAGE_DIR']) / f'com.ning.keyboardglass_{VERSION}_{expected_arch}.deb'
        run(['dpkg-deb', '-b', '--root-owner-group', rel(stage), str(output)])

if __name__ == '__main__':
    main()
