import pathlib,plistlib
P=pathlib.Path(__file__).resolve().parents[1];D=P/'Preferences';D.mkdir(exist_ok=True)
styles=[('default','当前原版'),('clear','清透薄玻璃'),('frost','柔白磨砂'),('crystal','厚实水晶'),('ice','冷色冰晶'),('smoke','烟灰玻璃'),('liquid','液态玻璃')]
items=[]
def group(label,footer=None):
 a={'cell':'PSGroupCell','label':label}
 if footer:a['footerText']=footer
 items.append(a)
def slider(key,label,lo,hi,default):
 group(label)
 items.append({'cell':'PSSliderCell','label':label,'key':key,'defaults':'com.ning.keyboardglass','min':lo,'max':hi,'default':default,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'})
group('皮肤预设','换皮肤保留所有手动微调值；未调过的项目使用新皮肤预设。已有微调会从升级时当前皮肤迁移。')
items.append({'cell':'PSLinkListCell','label':'玻璃皮肤','detail':'PSListItemsController','key':'Skin','defaults':'com.ning.keyboardglass','default':'default','validValues':[k for k,v in styles],'validTitles':[v for k,v in styles],'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'})
group('候选栏','同时隐藏右上角向下箭头和它旁边的竖分割线。关闭后恢复系统显示状态；不改变候选文字和键盘布局。')
items.append({'cell':'PSSwitchCell','label':'隐藏候选栏收起按钮','key':'HideCandidateControls','defaults':'com.ning.keyboardglass','default':False,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'})
group('系统背景','只调整系统背景层，和玻璃素材透明度独立。默认 1 为系统原始不透明度，0 为完全透明。')
slider('SystemAlpha','系统背景透明度',0.,1.,1.)
group('背景模糊','系统原生模糊叠加在玻璃素材下方，按键和候选文字保持清晰。强度为系统效果插值，不是模糊半径；外观会受系统背景透明度和系统辅助功能影响。')
items.append({'cell':'PSSwitchCell','label':'启用背景模糊','key':'BlurEnabled','defaults':'com.ning.keyboardglass','default':False,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'})
slider('BlurStrength','背景模糊强度',0.,1.,0.5)
group('玻璃底面','颜色用红、绿、蓝三个通道调节。明暗调整底面颜色，不改变 App 画面亮度。')
for key,label,lo,hi,val in [('BodyRed','颜色 · 红',0,1,1),('BodyGreen','颜色 · 绿',0,1,1),('BodyBlue','颜色 · 蓝',0,1,1),('BodyOpacity','玻璃底面透明度',0,1,.059),('BodyBrightness','底面明暗',0,1.5,1),('GradientStrength','渐变强度',0,1,0),('GradientAngle','渐变方向（度）',0,360,90)]:slider(key,label,float(lo),float(hi),float(val))
group('边缘高光')
for k,l,lo,hi,v in [('HighlightThickness','高光粗细',0,4,1),('HighlightBrightness','高光亮度',0,1,.49),('HighlightWidth','高光扩散宽度',0,14,2)]:slider(k,l,float(lo),float(hi),float(v))
group('立体感','外阴影在现有背景裁剪范围内绘制，不扩大键盘或覆盖按键。')
for k,l,lo,hi,v in [('InnerShadow','内阴影',0,1,0),('OuterShadow','外阴影',0,1,0),('EdgeSoftness','边缘柔化',0,5,.4)]:slider(k,l,float(lo),float(hi),float(v))
group('轮廓','圆角单位为 pt；边缘形状由圆润（2）逐渐变为更方正（5）。不改变键盘大小和接缝位置。')
slider('CornerRadius','圆角大小',0.,40.,14.);slider('CornerShape','边缘形状',2.,5.,2.)
group('恢复默认','恢复材质预设会清除所有皮肤共用的手动微调，保留系统背景透明度、背景模糊和隐藏开关。恢复全部会回到原版皮肤，系统背景 alpha 恢复 1，隐藏与模糊开关关闭。')
items.extend([{'cell':'PSButtonCell','label':'恢复材质预设','action':'resetCurrentSkin'},{'cell':'PSButtonCell','label':'恢复全部默认','action':'resetAll'},{'cell':'PSGroupCell','footerText':'Ning · 静态玻璃材质，不提供实时折射。'}])
for name,data in [('Root.plist',{'title':'键盘玻璃','items':items}),('Info.plist',{'CFBundleIdentifier':'com.ning.keyboardglass.preferences','CFBundleName':'KeyboardGlassPrefs','CFBundleExecutable':'KeyboardGlassPrefs','CFBundlePackageType':'BNDL','CFBundleVersion':'0.2','CFBundleShortVersionString':'0.2','NSPrincipalClass':'NGKeyboardGlassPrefsController'}),('entry.plist',{'entry':{'bundle':'KeyboardGlassPrefs','isController':True,'icon':'icon.png','cell':'PSLinkCell','detail':'NGKeyboardGlassPrefsController','label':'键盘玻璃'}})]: (D/name).write_bytes(plistlib.dumps(data,sort_keys=False))
print('settings',len(items),'rows; sliders',sum(x['cell']=='PSSliderCell' for x in items))
