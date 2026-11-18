#!/usr/bin/env python3
"""Native Xcode build: only arm64e / RootHide, fixed + on-demand Glassify."""
from pathlib import Path, PurePosixPath
import gzip
import hashlib
import io
import json
import platform
import plistlib
import shlex
import shutil
import struct
import subprocess
import tarfile

P = Path(__file__).resolve().parent
O = P / 'dist'
B = P / 'build/native64e'
V = P / 'Vendor/Glassify'
G = V / 'Sources/Glassify'
VERSION = '0.1.4'
TARGET = 'arm64e-apple-ios17.0'
LIB = Path('Library/MobileSubstrate/DynamicLibraries')
RESOURCE = LIB / 'NingKeyboardGlassResources.bundle'
PREFS = Path('Library/PreferenceBundles/KeyboardGlassPrefs.bundle')
FRAMEWORKS = ['UIKit', 'Foundation', 'CoreGraphics', 'QuartzCore', 'Metal', 'MetalKit', 'IOSurface', 'CoreVideo']
PLATFORM = ['GLSBackdrop', 'GLSContentMask', 'GLSGlassSurface', 'GLSRenderer',
            'GLSGlassView', 'GLSScrollEdgeEffectView']
# Only the original platform files needed by GLSGlassView are compiled; no
# tab-bar controller, buttons, switches, sliders, or navigation UI is linked.



def run(args, capture=False):
    args = [str(x) for x in args]
    print('$ ' + shlex.join(args), flush=True)
    return subprocess.run(args, cwd=P, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def check_vendor():
    manifest = json.loads((V / 'manifest.json').read_text())
    for name, expected in manifest['files'].items():
        path = V / name
        if digest(path.read_bytes()) != expected:
            raise RuntimeError('Glassify original changed: ' + name)
    required = [G / 'Platform' / (name + '.mm') for name in PLATFORM]
    required += sorted((G / 'Core').glob('*.cpp'))
    required += [G / 'Shaders' / name for name in
                 ('glass.metal', 'blur.metal', 'glass_shared.h', 'glass_sdf.h')]
    for path in required:
        if str(path.relative_to(V)) not in manifest['files']:
            raise RuntimeError('Missing original in Glassify manifest: ' + str(path))
    if not list((G / 'Core').glob('*.cpp')):
        raise RuntimeError('Glassify Core sources missing')
    return manifest


def compile_sources(sources, directory, sdk, extra=()):
    directory.mkdir(parents=True, exist_ok=True)
    objects = []
    includes = [P, P / 'tools', P / 'prefs', G / 'Core/include',
                G / 'Platform', G / 'include', P / 'prefs/Preferences.framework']
    for index, source in enumerate(sources):
        cpp = source.suffix in ('.mm', '.cpp')
        flags = ['-target', TARGET, '-isysroot', sdk, '-O2', '-fPIC', '-fblocks',
                 '-fmodules', '-fmodules-cache-path=' + str(B / 'ModuleCache'),
                 '-Wall', '-Wextra']
        if cpp:
            flags += ['-std=c++17', '-stdlib=libc++']
        if source.suffix in ('.m', '.mm'):
            flags += ['-fobjc-arc']
        for include in includes:
            flags += ['-I', include]
        output = directory / (str(index) + '-' + source.name + '.o')
        run(['xcrun', '--sdk', 'iphoneos', 'clang++' if cpp else 'clang',
             *flags, *extra, '-c', source, '-o', output])
        objects.append(output)
    return objects


def link(objects, output, sdk, extra=()):
    flags = [flag for name in FRAMEWORKS for flag in ('-framework', name)]
    run(['xcrun', '--sdk', 'iphoneos', 'clang++', '-target', TARGET,
         '-isysroot', sdk, '-O2', '-Wl,-undefined,error', *objects,
         *flags, *extra, '-o', output])


def sign(path):
    run(['codesign', '--force', '--sign', '-', '--timestamp=none', path])
    verify_signature(path)


def verify_signature(path):
    run(['codesign', '--verify', '--strict', '--all-architectures', path])


def check_macho(path, filetype):
    data = path.read_bytes()
    header = struct.unpack_from('<4I', data)
    if header != (0xfeedfacf, 0x0100000c, 0x80000002, filetype):
        raise RuntimeError('Expected native thin arm64e Mach-O: ' + str(path))
    return {'sha256': digest(data), 'size': len(data), 'cputype': '0x0100000c',
            'cpusubtype': '0x80000002', 'filetype': filetype}


def compile_metal(sdkname, destination):
    destination.mkdir(parents=True, exist_ok=True)
    sdk = run(['xcrun', '--sdk', sdkname, '--show-sdk-path'], True).strip()
    air = []
    for name in ('glass', 'blur'):
        target = 'air64-apple-ios17.0' if sdkname == 'iphoneos' else 'air64-apple-macos13.0'
        output = destination / (name + '.air')
        run(['xcrun', '--sdk', sdkname, 'metal', '-target', target,
             '-isysroot', sdk, '-std=ios-metal2.4' if sdkname == 'iphoneos' else '-std=macos-metal2.4',
             '-O2', '-I', G / 'Shaders', '-c', G / 'Shaders' / (name + '.metal'), '-o', output])
        air.append(output)
    library = destination / 'default.metallib'
    run(['xcrun', '--sdk', sdkname, 'metallib', *air, '-o', library])
    return library


def bake_assets(directory):
    directory.mkdir(parents=True, exist_ok=True)
    mac = B / 'baker'; mac.mkdir(parents=True, exist_ok=True)
    library = compile_metal('macosx', mac)
    executable = mac / 'glassify-bake'
    run(['xcrun', '--sdk', 'macosx', 'clang++', '-std=c++17', '-fobjc-arc', '-fblocks', '-O2',
         '-I', G / 'Core/include', P / 'tools/glassify_bake.mm',
         G / 'Core/glass_inputs.cpp', G / 'Core/pack.cpp', G / 'Core/color_matrix.cpp',
         '-framework', 'Foundation', '-framework', 'Metal', '-framework', 'CoreGraphics',
         '-framework', 'ImageIO', '-o', executable])
    run([executable, library, directory])
    result = json.loads((directory / 'material.json').read_text())
    if result['source_rgb'] != [128, 128, 128] or result['style'] != 'Clear' or result['frost'] != 'Automatic':
        raise RuntimeError('Unexpected baked material')
    if result['png_alpha_rewritten'] or result['original_input_fields_overridden']:
        raise RuntimeError('Original material was changed')
    for mode in ('Light', 'Dark'):
        data = (directory / ('GlassifyClear' + mode + '.png')).read_bytes()
        if not data.startswith(b'\x89PNG\r\n\x1a\n') or struct.unpack_from('>II', data, 16) != (576, 186):
            raise RuntimeError('Missing native baked output')
    return result


def make_resources(stage):
    resources = stage / RESOURCE; resources.mkdir(parents=True, exist_ok=True)
    baked = bake_assets(resources)
    metal = B / 'ios-metal'; metal.mkdir(parents=True, exist_ok=True)
    library = compile_metal('iphoneos', metal)
    (resources / 'default.metallib').write_bytes(library.read_bytes())
    (resources / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.ning.keyboardglass.resources',
        'CFBundleName': 'NingKeyboardGlassResources', 'CFBundleVersion': VERSION,
        'CFBundlePackageType': 'BNDL'}))
    (resources / 'Glassify-LICENSE.txt').write_bytes((V / 'LICENSE').read_bytes())
    provenance = {'revision': check_vendor()['revision'], 'original_files_unmodified': True,
                  'bake': baked, 'assets': {name: digest((resources / name).read_bytes()) for name in
                       ('GlassifyClearLight.png', 'GlassifyClearDark.png', 'default.metallib')}}
    write_json(resources / 'provenance.json', provenance)
    return provenance


def make_prefs(stage, sdk):
    destination = stage / PREFS; destination.mkdir(parents=True, exist_ok=True)
    for name in ('Root.plist', 'Info.plist'):
        value = plistlib.loads((P / 'prefs/Resources' / name).read_bytes())
        if name == 'Info.plist':
            value['CFBundleVersion'] = VERSION; value['CFBundleShortVersionString'] = VERSION
        (destination / name).write_bytes(plistlib.dumps(value))
    entry = stage / 'Library/PreferenceLoader/Preferences/KeyboardGlass.plist'
    entry.parent.mkdir(parents=True, exist_ok=True)
    entry.write_bytes((P / 'prefs/Resources/entry.plist').read_bytes())
    sources = [P / 'prefs/NGKeyboardGlassRootListController.m', P / 'prefs/NGKeyboardPreferenceStore.m']
    objects = compile_sources(sources, B / 'prefs-objects', sdk)
    executable = destination / 'KeyboardGlassPrefs'
    link(objects, executable, sdk, ['-bundle', '-F', P / 'tools', '-framework', 'Preferences'])
    sign(destination)
    check_macho(executable, 8)
    return destination

def tar_bytes(files):
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        directories = set()
        for name in files:
            directories.update(str(d) for d in PurePosixPath(name).parents if str(d) != '.')
        for name in sorted(directories, key=lambda x: (x.count('/'), x)):
            item = tarfile.TarInfo('./' + name)
            item.type = tarfile.DIRTYPE; item.mode = 0o755; item.uid = item.gid = 0
            archive.addfile(item)
        for name, (data, mode) in sorted(files.items()):
            item = tarfile.TarInfo('./' + name)
            item.size = len(data); item.mode = mode; item.uid = item.gid = 0
            archive.addfile(item, io.BytesIO(data))
    return gzip.compress(result.getvalue(), mtime=0)


def package(stage):
    files = {str(p.relative_to(stage)): (p.read_bytes(), p.stat().st_mode & 0o7777)
             for p in stage.rglob('*') if p.is_file()}
    control = ('Package: com.ning.keyboardglass\nName: Ning Keyboard Glass\nVersion: ' + VERSION +
        '\nArchitecture: iphoneos-arm64e\nMaintainer: Ning&Hung Phan\nAuthor: Ning&Hung Phan\nSection: Tweaks\n'
        'Depends: firmware (>= 17.0), mobilesubstrate, preferenceloader\n'
        'Description: Glassify keyboard background with fixed and on-demand modes.\n'
        'Installed-Size: ' + str(sum((len(data)+1023)//1024 for data, _ in files.values())) + '\n').encode()
    md5sums = ''.join(hashlib.md5(data).hexdigest() + '  ' + name + '\n'
                      for name, (data, _) in sorted(files.items())).encode()
    members = [('debian-binary', b'2.0\n'),
               ('control.tar.gz', tar_bytes({'control': (control, 0o644), 'md5sums': (md5sums, 0o644)})),
               ('data.tar.gz', tar_bytes(files))]
    result = bytearray(b'!<arch>\n')
    for name, data in members:
        header = f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n'.encode()
        assert len(header) == 60
        result += header + data
        if len(data) % 2: result += b'\n'
    deb = O / ('com.ning.keyboardglass_' + VERSION + '_iphoneos-arm64e.deb')
    deb.write_bytes(result)
    return deb


def verify_package(deb):
    data = deb.read_bytes(); assert data.startswith(b'!<arch>\n')
    offset = 8; members = {}
    while offset < len(data):
        header = data[offset:offset+60]; assert header[58:60] == b'`\n'
        size = int(header[48:58]); name = header[:16].decode().strip().rstrip('/')
        members[name] = data[offset+60:offset+60+size]
        offset += 60 + size + size % 2
    assert set(members) == {'debian-binary', 'control.tar.gz', 'data.tar.gz'}
    final = B / 'final-package'; final.mkdir()
    extracted = {}
    with tarfile.open(fileobj=io.BytesIO(members['data.tar.gz']), mode='r:gz') as archive:
        for item in archive:
            name = item.name.removeprefix('./')
            if not name or '..' in PurePosixPath(name).parts or PurePosixPath(name).is_absolute():
                raise RuntimeError('Invalid package path')
            target = final / name
            if item.isdir(): target.mkdir(parents=True, exist_ok=True)
            elif item.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                payload = archive.extractfile(item).read(); target.write_bytes(payload)
                target.chmod(item.mode); extracted[name] = payload
            else: raise RuntimeError('Unexpected package member')
    main = final / LIB / 'NingKeyboardGlass.dylib'
    prefs = final / PREFS / 'KeyboardGlassPrefs'
    binaries = {'main': check_macho(main, 6), 'prefs': check_macho(prefs, 8)}
    verify_signature(main); verify_signature(prefs); verify_signature(final / PREFS)
    root = plistlib.loads((final / PREFS / 'Root.plist').read_bytes())
    modes = [v for v in root['items'] if v.get('key') == 'RenderingMode']
    assert len(modes) == 1 and modes[0]['validValues'] == [0, 1] and modes[0]['default'] == 0
    manifest = json.loads((final / RESOURCE / 'provenance.json').read_text())
    for name, expected in manifest['assets'].items():
        assert digest((final / RESOURCE / name).read_bytes()) == expected
    assert not any(p.startswith('var/jb/') for p in extracted)
    with tarfile.open(fileobj=io.BytesIO(members['control.tar.gz']), mode='r:gz') as archive:
        for line in archive.extractfile('./md5sums').read().decode().splitlines():
            expected, name = line.split('  ', 1)
            assert hashlib.md5(extracted[name]).hexdigest() == expected
    return {'sha256': digest(data), 'size': len(data), 'cpusubtype': '0x80000002',
            'strict_signature': True, 'binaries': binaries, 'preferences_modes': [0, 1],
            'default_mode': 0, 'glassify_source_unmodified': True,
            'baked_native_gpu': manifest['bake'], 'runtime_tested': False}

def main():
    if platform.system() != 'Darwin': raise RuntimeError('Native Xcode macOS host required')
    check_vendor()
    O.mkdir(exist_ok=True); B.mkdir(parents=True, exist_ok=True)
    sdk = run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], True).strip()
    stage = B / 'stage'; stage.mkdir()
    make_resources(stage)
    sources = [P / 'KeyboardBackground.m', P / 'NGGlassMaterial.mm', P / 'NGPreferences.m']
    sources += sorted((G / 'Core').glob('*.cpp'))
    sources += [G / 'Platform' / (name + '.mm') for name in PLATFORM]
    objects = compile_sources(sources, B / 'main-objects', sdk)
    dylib = stage / LIB / 'NingKeyboardGlass.dylib'; dylib.parent.mkdir(parents=True, exist_ok=True)
    link(objects, dylib, sdk, ['-dynamiclib', '-Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib'])
    sign(dylib); check_macho(dylib, 6)
    (dylib.parent / 'NingKeyboardGlass.plist').write_bytes(plistlib.dumps({'Filter': {'Bundles': ['com.apple.UIKit']}}))
    make_prefs(stage, sdk)
    deb = package(stage)
    verification = verify_package(deb)
    write_json(O / 'verification.json', verification)
    (O / 'material-provenance.json').write_bytes((stage / RESOURCE / 'provenance.json').read_bytes())
    print(json.dumps(verification, indent=2))


if __name__ == '__main__':
    main()

