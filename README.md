# KeyboardGlass

照 **Laetus（键盘美化）图像主题实现方式**做的开源键盘美化插件。

## 实现原理（与 Laetus 相同的路线）

iOS 键盘在宿主 App 进程内由 UIKit 私有类渲染：

1. **注入**：Filter = `com.apple.UIKit / UIKitCore`（Laetus 同款注入面）
2. **跟踪 keyplane**：hook `UIKeyboardLayoutStar` 的 `setCurrentKeyboardLayoutStar:` / `keyPlaneDidChange:`，实时知道当前是字母/数字/Emoji/听写哪个面 + 横竖屏
3. **铺图**：把主题 PNG 插到键盘视图层级 `insertSubview:atIndex:0`（背景层）+ 可选前景层
4. **主题命名**（照系统键盘资源/Laetus 约定）：
   - `KeyboardMainBGPortrait-926h@3x.png`（字母·竖屏·15 Pro Max）
   - `KeyboardNumbersBGLandscape-896h@3x.png`（数字·横屏）
   - `KeyboardEmojiBGPortrait@3x.png` / `KeyboardDictationBGPortrait@3x.png`
   - `KeyboardPredictionBarBGPortrait@3x.png` / `KeyboardEmojiSearchBarBGPortrait@3x.png`
   - 屏高后缀可选（926h/896h/844h/667h），`@3x > @2x > 无`
5. **键帽处理**：`UIKBKeyView layoutSubviews` 里清阴影（Laetus HideKeyShadows 同款思路）
6. **即时生效**：CFPreferences 域 `com.ning.keyboardglass` + Darwin 通知 `com.ning.keyboardglass.changed`

## 主题目录

```
/var/jb/Library/KeyboardGlass/Themes/MyTheme/
  KeyboardMainBGPortrait-926h@3x.png
  KeyboardMainBGLandscape-926h@3x.png
  KeyboardNumbersBGPortrait-926h@3x.png
  ...
```

设置 → KeyboardGlass → 选择主题，重新弹出键盘生效。

## 构建

GitHub Actions（macos-15 + roothide theos + iPhoneOS16.5 SDK），产物 arm64e roothide deb。

## 作者

Ning
