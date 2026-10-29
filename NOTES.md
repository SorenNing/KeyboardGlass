## KeyboardGlass — 键盘美化插件（照 Laetus 图像主题方式）

目标：iOS 15+（用户机 iPhone 15 Pro Max / iOS 17.2.1 RootHide），rootless+roothide 双架构发布。

## 实现方式（Laetus 证据还原）
- 注入 Filter: com.apple.UIKit + UIKitCore（键盘在宿主 App 进程渲染）
- hook keyPlaneDidChange:/rawKeyPlaneDidChange: 跟踪当前 keyplane（KeyboardMain/Numbers/Emoji/Dictation/PredictionBar × 横竖屏 × 机型屏高）
- 主题图命名 = keyplane 名（KeyboardMainBG-896h@3x.png 等），放 /var/jb/Library/KeyboardGlass/Themes/<name>.theme/Images/
- backgroundImageForKeyplaneName:/foregroundImageForKeyplaneName: 查表 → 插入 laetus_themeBackgroundImageView/laetus_themeForegroundImageView 双 UIImageView
- HideKeyCaps/HideKeyShadows 隐藏原键帽阴影；UIKBCachedImage setImage:cachedWidth:keyplane: 拦缓存贴图
- Darwin 通知刷新；CFPreferences 域 com.ning.keyboardglass

## 构建环境（本机，2026-10-29 验证可用）
- clang-19: `/usr/bin/clang-19 -target arm64[e]-apple-ios15.0 -isysroot /root/sdks/iPhoneOS16.5.sdk`
- 链接必须 -fuse-ld=/usr/bin/ld64.lld（clang 内置调 GNU ld 会报 emulation 错）
- ld64.lld 手动链接：`-arch arm64 -platform_version ios 15.0 17.0 -dylib -fixup_chains -syslibroot SDK t.o -o out.dylib -lSystem`
- arm64e 不支持 -fixup_chains（直接省略，输出仍可加载）；arm64 必须加
- theos-rh 在 /root/theos-rh（vendor/lib/libroothide.tbd、CydiaSubstrate.h 可用）
- 历史经验：MarkFont 用 -target arm64 + ARCHS=arm64 输出（包 metadata 仍标 arm64e 也能加载）
- file_write 对 /var/minis/workspace 有 touch 时间戳报错（无害，文件实际写入成功）
