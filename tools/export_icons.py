from pathlib import Path
from PIL import Image
import hashlib,json
P=Path(__file__).resolve().parents[1];R=P/'Resources/Icons';R.mkdir(parents=True,exist_ok=True)
im=Image.open(R/'master.png').convert('RGBA');assert im.size==(512,512)
outputs={'icon.png':29,'icon@2x.png':58,'icon@3x.png':87}
manifest={}
for name,size in outputs.items():
 image=im.resize((size,size),Image.Resampling.LANCZOS)
 image.putdata([(0,0,0,0) if p[3]<3 else p for p in image.getdata()])
 image.save(R/name)
 check=Image.open(R/name);assert check.size==(size,size) and check.mode=='RGBA' and check.getpixel((0,0))[3]==0
 manifest[name]={'size':size,'sha256':hashlib.sha256((R/name).read_bytes()).hexdigest()}
(R/'manifest.json').write_text(json.dumps({'style':'A ice-blue approved','outputs':manifest},indent=2))
print(json.dumps(manifest,indent=2))
