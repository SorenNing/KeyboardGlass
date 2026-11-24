import subprocess,pathlib,struct,tarfile,io,gzip,hashlib,json,plistlib
P=pathlib.Path(__file__).resolve().parent
O=P/'dist';O.mkdir(exist_ok=True)
VERSION='0.2.2'
MIN_IOS='16.0'
def run(a):subprocess.run(a,check=True,cwd=P)
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
def tar(files,executables):
 out=io.BytesIO()
 with tarfile.open(fileobj=out,mode='w',format=tarfile.USTAR_FORMAT) as t:
  dirs=set()
  for name in files:
   for parent in pathlib.PurePosixPath(name).parents:
    if str(parent)!='.':dirs.add(str(parent))
  for name in sorted(dirs,key=lambda x:(x.count('/'),x)):
   i=tarfile.TarInfo('./'+name);i.type=tarfile.DIRTYPE;i.mode=0o755;i.uid=i.gid=0;t.addfile(i)
  for name,data in files.items():
   i=tarfile.TarInfo('./'+name);i.size=len(data);i.mode=0o755 if name in executables else 0o644;i.uid=i.gid=0;t.addfile(i,io.BytesIO(data))
 return gzip.compress(out.getvalue(),mtime=0)
def pack(parts):
 out=bytearray(b'!<arch>\n')
 for name,data in parts.items():
  h=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n'.encode();assert len(h)==60
  out+=h+data
  if len(data)%2:out+=b'\n'
 return out
def verify_macho(path,arch):
 data=path.read_bytes();assert struct.unpack_from('<I',data,0)[0]==0xfeedfacf
 assert struct.unpack_from('<I',data,8)[0]==(0x80000002 if arch=='arm64e' else 0)
 off=32;minimum=None
 for _ in range(struct.unpack_from('<I',data,16)[0]):
  cmd,size=struct.unpack_from('<II',data,off)
  if cmd==0x32:minimum=struct.unpack_from('<I',data,off+12)[0]
  if cmd==0x25:minimum=struct.unpack_from('<I',data,off+8)[0]
  off+=size
 assert minimum is not None and minimum<=0x100000,hex(minimum or 0)
 run(['codesign','--verify','--strict','--all-architectures',str(path)])
 return data
receipts=[]
for scheme,arch,prefix in [('rootless','arm64','var/jb/'),('roothide','arm64e','')]:
 B=O/scheme;B.mkdir(exist_ok=True)
 engine=B/'NingKeyboardGlass.dylib';prefs=B/'KeyboardGlassPrefs'
 flags=['xcrun','--sdk','iphoneos','clang','-target',arch+'-apple-ios'+MIN_IOS,'-isysroot',sdk,'-fobjc-arc','-fblocks','-O2','-Wall','-Wextra','-Werror','-Wunguarded-availability']
 frameworks=['-framework','UIKit','-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore']
 install='/'+prefix+'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib'
 run(flags+['-dynamiclib','KeyboardBackground.m']+frameworks+['-install_name',install,'-o',str(engine)])
 run(flags+['-bundle','Preferences/NGKeyboardGlassPrefs.m']+frameworks+['-framework','CoreFoundation','-Wl,-undefined,dynamic_lookup','-o',str(prefs)])
 for f in [engine,prefs]:run(['codesign','--force','--sign','-',str(f)])
 binaries={prefix+'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.dylib':verify_macho(engine,arch),prefix+'Library/PreferenceBundles/KeyboardGlassPrefs.bundle/KeyboardGlassPrefs':verify_macho(prefs,arch)}
 files=dict(binaries);bundle=prefix+'Library/PreferenceBundles/KeyboardGlassPrefs.bundle/'
 files[prefix+'Library/MobileSubstrate/DynamicLibraries/NingKeyboardGlass.plist']=plistlib.dumps({'Filter':{'Bundles':['com.apple.UIKit']}})
 for resource in ['Root.plist','Info.plist']:
  files[bundle+resource]=(P/'Preferences'/resource).read_bytes()
 entryPath=prefix+'Library/PreferenceLoader/Preferences/KeyboardGlass.plist'
 files[entryPath]=(P/'Preferences/entry.plist').read_bytes()
 for name in ['icon.png','icon@2x.png','icon@3x.png']:files[bundle+name]=(P/'Resources/Icons'/name).read_bytes()
 for name,suffix in [('package.png',''),('package-256.png','-256'),('package-128.png','-128')]:
  files[prefix+'usr/share/icons/com.ning.keyboardglass'+suffix+'.png']=(P/'Resources/Icons'/name).read_bytes()
 policy=plistlib.loads((P/'Resources/KeyboardGlass_ReadConfig.plist').read_bytes())
 host='/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist'
 assert policy=={'AllowedProcesses':['*'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':'/rootfs'+host}]}
 if scheme=='rootless':policy['Extensions'][0]['path']=host
 policyPath=prefix+'Library/libSandy/KeyboardGlass_ReadConfig.plist'
 files[policyPath]=plistlib.dumps(policy)
 icon='file:///'+prefix+'usr/share/icons/com.ning.keyboardglass.png'
 control=(f'Package: com.ning.keyboardglass\nName: Ning Keyboard Glass\nVersion: {VERSION}\nArchitecture: iphoneos-{arch}\nMaintainer: Ning\nAuthor: Ning\nSection: Tweaks\nIcon: {icon}\nDepends: firmware (>= {MIN_IOS}), mobilesubstrate, preferenceloader, com.opa334.libsandy\nDescription: Adjustable glass material for system keyboards on iOS 16 and 17.\nInstalled-Size: {sum((len(v)+1023)//1024 for v in files.values())}\n').encode()
 md=''.join(hashlib.md5(v).hexdigest()+'  '+k+'\n' for k,v in files.items()).encode()
 parts={'debian-binary':b'2.0\n','control.tar.gz':tar({'control':control,'md5sums':md},set()),'data.tar.gz':tar(files,set(binaries))}
 out=pack(parts);deb=O/f'com.ning.keyboardglass_{VERSION}_iphoneos-{arch}.deb';deb.write_bytes(out)
 with tarfile.open(fileobj=io.BytesIO(parts['data.tar.gz']),mode='r:gz') as t:
  info=plistlib.loads(t.extractfile('./'+bundle+'Info.plist').read());entry=plistlib.loads(t.extractfile('./'+entryPath).read())['entry']
  assert info['CFBundleVersion']==VERSION and entry.get('isController') is True and entry['icon']=='icon.png'
  assert entry['detail']==info['NSPrincipalClass']=='NGKeyboardGlassPrefsController'
  member=t.getmember('./'+policyPath);assert member.uid==member.gid==0 and member.mode==0o644
  assert plistlib.loads(t.extractfile(member).read())==policy
  for name,data in files.items():assert t.extractfile('./'+name).read()==data
  for name in binaries:
   path=B/'extracted-check';path.write_bytes(t.extractfile('./'+name).read());verify_macho(path,arch);path.unlink()
 assert len(files)==13
 if prefix:assert all(name.startswith(prefix) for name in files)
 else:assert all(not name.startswith('var/jb/') for name in files)
 receipts.append({'version':VERSION,'scheme':scheme,'architecture':'iphoneos-'+arch,'cpusubtype':hex(0x80000002 if arch=='arm64e' else 0),'minimum_ios':MIN_IOS,'file':deb.name,'size':len(out),'sha256':hashlib.sha256(out).hexdigest(),'payload_files':len(files),'strict_signature':True,'runtime_tested':False,'profile_path':policy['Extensions'][0]['path']})
(O/'verification.json').write_text(json.dumps(receipts,indent=2));print(json.dumps(receipts,indent=2))
