import pathlib,plistlib,re,subprocess,tempfile
P=pathlib.Path(__file__).resolve().parents[1]
entry=plistlib.loads((P/'Preferences/entry.plist').read_bytes())['entry']
info=plistlib.loads((P/'Preferences/Info.plist').read_bytes())
assert entry.get('isController') is True, 'PreferenceLoader controller entry must enable lazy bundle loading'
assert entry['cell']=='PSLinkCell' and entry['bundle']=='KeyboardGlassPrefs'
assert entry['detail']==info['NSPrincipalClass']=='NGKeyboardGlassPrefsController'
assert info['CFBundleExecutable']=='KeyboardGlassPrefs'
assert entry['icon']=='icon.png'
import json,hashlib,struct
icons=P/'Resources/Icons'
manifest=json.loads((icons/'manifest.json').read_text())['outputs']
for name,item in manifest.items():
 data=(icons/name).read_bytes()
 assert hashlib.sha256(data).hexdigest()==item['sha256']
 assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',data,16)==(item['size'],item['size'])
policy=plistlib.loads((P/'Resources/KeyboardGlass_ReadConfig.plist').read_bytes())
assert policy['AllowedProcesses']==['*'], 'Configuration access must cover all host Apps'
assert policy['Extensions']==[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':'/rootfs/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist'}], 'Grant read-only access to the exact host file on RootHide'
root=plistlib.loads((P/'Preferences/Root.plist').read_bytes())['items']
sliders=[x for x in root if x['cell']=='PSSliderCell'];assert len(sliders)==17
keys=[x['key'] for x in sliders];assert len(keys)==len(set(keys))
for i,row in enumerate(root):
 if row['cell']=='PSSliderCell':
  assert root[i-1]['label']==row['label'] and root[i-1]['cell']=='PSGroupCell'
  assert row['min']<=row['default']<=row['max']
assert next(x for x in sliders if x['key']=='SystemAlpha')['default']==1
choices=next(x for x in root if x['cell']=='PSLinkListCell');assert len(choices['validValues'])==7
switches=[x for x in root if x['cell']=='PSSwitchCell' and x.get('key')=='HideCandidateControls']
assert len(switches)==1 and switches[0]['default'] is False
assert len(root)==50 and sum(x['cell']=='PSGroupCell' for x in root)==27
blur=next(x for x in root if x.get('key')=='MaterialBlurEnabled')
strength=next(x for x in sliders if x['key']=='MaterialBlurStrength')
assert blur['cell']=='PSSwitchCell' and blur['default'] is False
assert strength['default']==0.5 and strength['min']==0 and strength['max']==1
highlight=next(x for x in root if x.get('key')=='HideCandidateHighlight')
assert highlight['cell']=='PSSwitchCell' and highlight['default'] is False
renderer=(P/'GlassRenderer.h').read_text();model=(P/'GlassPreferences.h').read_text()
for key in keys:
 assert key in model or key in ('SystemAlpha','MaterialBlurStrength')
 if key not in ('SystemAlpha','MaterialBlurStrength'):assert key in renderer
s=(P/'GlassRaster.h').read_text().replace('#pragma once','')
code='#include <math.h>\n#include <assert.h>\n'+s+'''\nint main(void) {
 for(int r=0;r<=40;r++) for(int p=20;p<=50;p++) {
  double n=p/10.0;
  assert(NGGlassDistance(64,64,64,r,n)>0);
  assert(fabs(NGGlassDistance(64,0,64,r,n))<1e-6);
  assert(NGGlassDistance(-1,64,64,r,n)<0);
  for(int x=0;x<=128;x+=8) for(int y=0;y<=128;y+=8) {
   double a=NGGlassDistance(x,y,64,r,n),b=NGGlassDistance(128-x,y,64,r,n);
   assert(isfinite(a)&&fabs(a-b)<1e-6);
  }
 }
 double r=0,g=0,b=0,a=0;
 NGOver(&r,&g,&b,&a,1,0,0,.5);assert(fabs(r-.5)<1e-6&&a==.5);
 NGOver(&r,&g,&b,&a,0,1,0,.5);assert(fabs(a-.75)<1e-6&&r<=a&&g<=a&&b<=a);
 NGGlassRasterValues material={.radius=14,.shape=2.8,.red=1,.green=1,.blue=1,.opacity=.1,.softness=.4};
 double color[4];NGGlassSample(material,64,64,3,color);
 assert(fabs(color[3]-.1)<1e-6 && color[0]<=color[3]);
 return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 f=pathlib.Path(t)/'geometry.c';f.write_text(code);exe=pathlib.Path(t)/'check'
 subprocess.run(['cc','-Wall','-Wextra','-Werror',str(f),'-lm','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
print('PASS: 17 sliders, 7 skins, visible labels, default alpha 1.0, finite/symmetric production corner geometry and premultiplied compositing')
