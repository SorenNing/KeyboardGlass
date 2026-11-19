"""Original 0.1.0 material; candidate/keyboard background coordinates only."""
import gzip, hashlib, io, json, pathlib, plistlib, struct, subprocess, tarfile
P = pathlib.Path(__file__).resolve().parents[1]
O = P / 'dist'
VERSION = '0.3.2+glass1'
BASE = '82d5fc92f415391a42ae6a20ca5a046dac7221f0'

def run(a):
    subprocess.run(a, cwd=P, check=True)

def tar(files):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT) as t:
        dirs = set()
        for name in files:
            dirs.update(str(p) for p in pathlib.PurePosixPath(name).parents if str(p) != '.')
        for name in sorted(dirs, key=lambda x: (x.count('/'), x)):
            e = tarfile.TarInfo('./' + name)
            e.type = tarfile.DIRTYPE
            e.mode = 0o755
            t.addfile(e)
        for name, data in files.items():
            e = tarfile.TarInfo('./' + name)
            e.size = len(data)
            e.mode = 0o755 if name.endswith('.dylib') else 0o644
            t.addfile(e, io.BytesIO(data))
    return gzip.compress(out.getvalue(), mtime=0)

def deb(parts):
    out = bytearray(b'!<arch>\n')
    for name, data in parts.items():
        header = f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n'.encode()
        assert len(header) == 60
        out += header + data
        if len(data) % 2:
            out += b'\n'
    return bytes(out)

def main():
    O.mkdir(exist_ok=True)
    for name in ('Material.h', 'GlassBackground.png'):
        assert (P/name).read_bytes() == subprocess.check_output(['git', 'show', BASE+':'+name], cwd=P)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=P, text=True).strip()
    source_hash = hashlib.sha256((P/'KeyboardBackground.m').read_bytes()).hexdigest()
    receipts = []
    for arch, subtype, prefix in [('arm64e', 0x80000002, ''), ('arm64', 0, 'var/jb/')]:
        lib = O / ('NingKeyboardGlass-' + arch + '.dylib')
        rel = prefix + 'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass'
        run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', arch+'-apple-ios15.0',
             '-isysroot', sdk, '-dynamiclib', '-fobjc-arc', '-fblocks', '-O2', '-Wall', '-Wextra', '-Werror',
             'KeyboardBackground.m', 'KeyboardSurface.m', 'CandidateAppearance.m', '-framework', 'UIKit', '-framework', 'Foundation',
             '-framework', 'CoreGraphics', '-framework', 'QuartzCore',
             '-install_name', '/'+rel+'.dylib', '-o', str(lib)])
        run(['codesign', '--force', '--sign', '-', str(lib)])
        run(['codesign', '--verify', '--strict', '--all-architectures', str(lib)])
        data = lib.read_bytes()
        assert struct.unpack_from('<I', data, 0)[0] == 0xfeedfacf
        assert struct.unpack_from('<II', data, 4) == (0x100000c, subtype)
        files = {rel+'.dylib': data, rel+'.plist': plistlib.dumps({'Filter': {'Bundles': ['com.apple.UIKit']}})}
        control = (f'Package: com.ning.keyboardglass\nName: Ning Keyboard Glass\nVersion: {VERSION}\n'
                   f'Architecture: iphoneos-{arch}\nMaintainer: Ning\nAuthor: Ning\nSection: Tweaks\n'
                   'Depends: firmware (>= 17.0), mobilesubstrate\n'
                   'Description: Original 0.1.0 material with joined candidate and keyboard background.\n'
                   f'Installed-Size: {sum((len(v)+1023)//1024 for v in files.values())}\n').encode()
        md = ''.join(hashlib.md5(v).hexdigest()+'  '+k+'\n' for k, v in files.items()).encode()
        package = deb({'debian-binary': b'2.0\n', 'control.tar.gz': tar({'control': control, 'md5sums': md}),
                       'data.tar.gz': tar(files)})
        name = f'com.ning.keyboardglass_{VERSION}_iphoneos-{arch}.deb'
        (O/name).write_bytes(package)
        # Extract from final ar, not from pre-packaging variables.
        pos = 8
        actual_parts = {}
        while pos < len(package):
            header = package[pos:pos+60]
            size = int(header[48:58])
            actual_parts[header[:16].decode().strip().rstrip('/')] = package[pos+60:pos+60+size]
            pos += 60+size+(size%2)
        with tarfile.open(fileobj=io.BytesIO(actual_parts['data.tar.gz']), mode='r:gz') as t:
            extracted = t.extractfile('./'+rel+'.dylib').read()
            assert extracted == data
            assert t.extractfile('./'+rel+'.plist').read() == files[rel+'.plist']
        check = O/('verify-'+arch+'.dylib')
        check.write_bytes(extracted)
        run(['codesign', '--verify', '--strict', '--all-architectures', str(check)])
        check.unlink()
        receipts.append({'file': name, 'size': len(package), 'sha256': hashlib.sha256(package).hexdigest(),
                         'dylib_sha256': hashlib.sha256(data).hexdigest(), 'cpusubtype': hex(subtype),
                         'strict_signature': True, 'payload_prefix': prefix, 'runtime_tested': False})
        lib.unlink()
    result = {'commit': commit, 'source_sha256': source_hash, 'source_baseline': BASE,
              'material_unchanged': True, 'version': VERSION, 'packages': receipts}
    (O/'verification.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
