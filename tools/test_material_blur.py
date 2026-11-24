from pathlib import Path
import subprocess,tempfile,plistlib
P=Path(__file__).resolve().parents[1]
code=r'''#include "MaterialBlurKernel.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 uint8_t original[33*33*4], image[sizeof(original)];
 memset(original,0,sizeof(original));
 for(int c=0;c<4;c++) original[(16*33+16)*4+c]=255;
 memcpy(image,original,sizeof(image));
 assert(NGBlurRGBA(image,33,33,33*4,0));assert(memcmp(image,original,sizeof(image))==0);
 assert(NGBlurRGBA(image,33,33,33*4,2));
 int peak=image[(16*33+16)*4+3];assert(peak>0&&peak<255);
 assert(image[(16*33+15)*4+3]>0);
 for(int y=0;y<33;y++)for(int x=0;x<33;x++) {
  int o=(y*33+x)*4;assert(image[o]<=image[o+3]&&image[o+1]<=image[o+3]&&image[o+2]<=image[o+3]);
  assert(abs(image[o+3]-image[((32-y)*33+x)*4+3])<=1);
 }
 memcpy(image,original,sizeof(image));assert(NGBlurRGBA(image,33,33,132,4));assert(image[(16*33+16)*4+3]<peak);
 memset(image,80,sizeof(image));assert(NGBlurRGBA(image,33,33,132,2));
 for(unsigned i=0;i<sizeof(image);i++)assert(image[i]==80);
 assert(!NGBlurRGBA(image,33,33,131,2));assert(!NGBlurRGBA(image,33,33,132,NAN));
 puts("PASS: production Gaussian zero identity, impulse spreading, symmetry, premultiplied color, strength, uniform preservation and invalid input");return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 f=Path(t)/'blur.c';exe=Path(t)/'blur';f.write_text(code)
 subprocess.run(['cc','-O2','-Wall','-Wextra','-Werror','-I',str(P),str(f),'-lm','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
s=(P/'KeyboardBackground.m').read_text()
assert 'NGBlurMaterial(NGCachedMaterial,NGMaterialBlurStrength)' in s
assert 'NGApplyBackgroundBlur' not in s and 'UIViewPropertyAnimator' not in s
assert not (P/'BackgroundBlur.h').exists()
assert 'static void NGInstallBackdropHook(void)' in s and s.count('NGInstallBackdropHook();')>=2
assert 'static BOOL installed=NO' in s
assert s.index('static void NGInstallBackdropHook(void)')<s.index('__attribute__((constructor))')
b=(P/'build.py').read_text()
assert "MIN_IOS='16.0'" in b
assert "('rootless','arm64','var/jb/')" in b and "('roothide','arm64e','')" in b
assert "policy['Extensions'][0]['path']=host" in b
root=plistlib.loads((P/'Preferences/Root.plist').read_bytes())['items']
assert next(v for v in root if v.get('key')=='MaterialBlurEnabled')['default'] is False
assert not any(v.get('key') in ('BlurEnabled','BlurStrength') for v in root)
print('PASS: material-only blur, no added effect layer; iOS16 minimum, distinct rootless/RootHide architecture, paths and read policies. Device behavior not yet verified.')
