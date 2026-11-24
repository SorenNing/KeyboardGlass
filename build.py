import subprocess, pathlib, struct, tarfile, io, gzip, hashlib, json, plistlib
P=pathlib.Path(__file__).resolve().parent
O=P/'dist'; O.mkdir(exist_ok=True)
def run(a): subprocess.run(a,check=True,cwd=P)
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
f=O/'NingKeyboardGlass.dylib'
build=P/'build'; build.mkdir(exist_ok=True)
metal=build/'default.metallib'
run(['xcrun','--sdk','iphoneos','metal','-mios-version-min=15.0','-c',str(P/'Vendor/Theseus/Shaders/TheseusShaders.metal'),'-o',str(build/'glass.air')])
run(['xcrun','--sdk','iphoneos','metallib',str(build/'glass.air'),'-o',str(metal)])
obj=build/'KeyboardBackground.o'
run(['xcrun','--sdk','iphoneos','clang','-target','arm64e-apple-ios15.0','-isysroot',sdk,'-c','-fobjc-arc','-fblocks','-O2','-Wall','-Wextra','-Werror','KeyboardBackground.m','-o',str(obj)])
sources=sorted(str(x) for x in (P/'Vendor/Theseus').rglob('*.swift'))+[str(P/'KeyboardDynamic.swift'),str(P/'KeyboardEdges.swift')]
args=['xcrun','--sdk','iphoneos','swiftc','-swift-version','5','-strict-concurrency=minimal','-target','arm64e-apple-ios15.0','-sdk',sdk,'-O','-whole-module-optimization','-parse-as-library','-emit-library','-module-name','NingKeyboardGlassDynamic','-import-objc-header',str(P/'SwiftBridge.h'),'-Xlinker','-install_name','-Xlinker','/Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib','-Xlinker','-rpath','-Xlinker','/usr/lib/swift','-o',str(f)]
for framework in ['UIKit','Foundation','QuartzCore','CoreGraphics','CoreVideo','Metal','MetalKit','Accelerate','IOSurface']: args+=['-framework',framework]
run(args+sources+[str(obj)])
run(['codesign','--force','--sign','-',str(f)])
run(['codesign','--verify','--strict','--all-architectures',str(f)])
b=f.read_bytes(); assert struct.unpack_from('<I',b,8)[0]==0x80000002
control=b'Package: com.ning.keyboardglass\nName: Ning Keyboard Glass\nVersion: 0.1.7\nArchitecture: iphoneos-arm64e\nMaintainer: Ning&valzevul\nAuthor: Ning&valzevul\nSection: Tweaks\nDepends: firmware (>= 17.0), mobilesubstrate\nDescription: Experimental Theseus dynamic keyboard glass with alpha-0.8 compositor input.\n'
flt=plistlib.dumps({'Filter':{'Bundles':['com.apple.UIKit']}})
files={'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib':b,'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.plist':flt}
resource='Library/MobileSubstrate/DynamicLibraries/KeyboardGlass.bundle/'
files[resource+'default.metallib']=metal.read_bytes()
files[resource+'Info.plist']=plistlib.dumps({'CFBundleIdentifier':'com.ning.keyboardglass.resources','CFBundlePackageType':'BNDL','CFBundleVersion':'0.1.7'})
files['usr/share/doc/com.ning.keyboardglass/LICENSE-Theseus']=(P/'Vendor/LICENSE-Theseus').read_bytes()
files['usr/share/doc/com.ning.keyboardglass/NOTICE']=(P/'NOTICE').read_bytes()
def tar(files):
 out=io.BytesIO()
 with tarfile.open(fileobj=out,mode='w',format=tarfile.USTAR_FORMAT) as t:
  dirs=set()
  for name,data in files.items():
   for parent in pathlib.PurePosixPath(name).parents:
    if str(parent)!='.': dirs.add(str(parent))
  for name in sorted(dirs,key=lambda x:(x.count('/'),x)):
   i=tarfile.TarInfo('./'+name);i.type=tarfile.DIRTYPE;i.mode=0o755;i.uid=i.gid=0;t.addfile(i)
  for name,data in files.items():
   i=tarfile.TarInfo('./'+name);i.size=len(data);i.mode=0o755 if name.endswith('.dylib') else 0o644;i.uid=i.gid=0;t.addfile(i,io.BytesIO(data))
 return gzip.compress(out.getvalue(),mtime=0)
control+=f'Installed-Size: {sum((len(v)+1023)//1024 for v in files.values())}\n'.encode()
md=''.join(hashlib.md5(v).hexdigest()+'  '+k+'\n' for k,v in files.items()).encode()
parts={'debian-binary':b'2.0\n','control.tar.gz':tar({'control':control,'md5sums':md}),'data.tar.gz':tar(files)}
out=bytearray(b'!<arch>\n')
for name,data in parts.items():
 h=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n'.encode();assert len(h)==60
 out+=h+data
 if len(data)%2:out+=b'\n'
deb=O/'com.ning.keyboardglass_0.1.7_iphoneos-arm64e.deb';deb.write_bytes(out)
# Verify bytes in final package, not only pre-package library.
with tarfile.open(fileobj=io.BytesIO(parts['data.tar.gz']),mode='r:gz') as t:
 actual=t.extractfile('./Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib').read()
 assert actual==b
 check=O/'extracted.dylib';check.write_bytes(actual)
 run(['codesign','--verify','--strict','--all-architectures',str(check)])
 check.unlink()
receipt={'sha256':hashlib.sha256(out).hexdigest(),'size':len(out),'cpusubtype':'0x80000002','strict_signature':True,'runtime_tested':False}
(O/'verification.json').write_text(json.dumps(receipt,indent=2));print(receipt)
