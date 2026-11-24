import pathlib,plistlib,re,subprocess,tempfile
P=pathlib.Path(__file__).resolve().parents[1]
root=plistlib.loads((P/'Preferences/Root.plist').read_bytes())['items']
sliders=[x for x in root if x['cell']=='PSSliderCell'];assert len(sliders)==16
keys=[x['key'] for x in sliders];assert len(keys)==len(set(keys))
for i,row in enumerate(root):
 if row['cell']=='PSSliderCell':
  assert root[i-1]['label']==row['label'] and root[i-1]['cell']=='PSGroupCell'
  assert row['min']<=row['default']<=row['max']
assert next(x for x in sliders if x['key']=='SystemAlpha')['default']==1
choices=next(x for x in root if x['cell']=='PSLinkListCell');assert len(choices['validValues'])==7
renderer=(P/'GlassRenderer.h').read_text();model=(P/'GlassPreferences.h').read_text()
for key in keys:
 assert key in model or key=='SystemAlpha'
 if key!='SystemAlpha':assert key in renderer
s=renderer[renderer.index('static inline double NGGlassDistance'):renderer.index('static inline UIImage *NGDrawGlass')]
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
 return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 f=pathlib.Path(t)/'geometry.c';f.write_text(code);exe=pathlib.Path(t)/'check'
 subprocess.run(['cc','-Wall','-Wextra','-Werror',str(f),'-lm','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
print('PASS: 16 sliders, 7 skins, visible labels, default alpha 1.0, finite/symmetric production corner geometry and premultiplied compositing')
