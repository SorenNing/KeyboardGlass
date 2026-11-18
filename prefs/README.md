# 键盘玻璃偏好模块

只提供一个 `mode` / `PSLinkListCell`；偏好域 `com.ning.keyboardglass`，唯一读写 key 为 `RenderingMode`，Darwin 通知 `com.ning.keyboardglass.changed`。没有总开关、图标、重启按钮、颜色或圆角设置，也没有 UIKit 文本监控。

- `0`（默认）：固定玻璃。中性场景 `128/255` 由 Glassify 原版 shader 离线预烘焙为图片；手机仅显示图片。
- `1`：按需玻璃。原版 `GLSGlassView` 只在 show、尺寸或外观变化时更新，不持续刷新。

## 源码与安装映射

| 源码 / 输入 | 安装位置 |
| --- | --- |
| `prefs/NGKeyboardGlassRootListController.m` 编译产物 | `Library/PreferenceBundles/KeyboardGlassPrefs.bundle/KeyboardGlassPrefs` |
| `prefs/Resources/Info.plist` | `Library/PreferenceBundles/KeyboardGlassPrefs.bundle/Info.plist` |
| `prefs/Resources/Root.plist` | `Library/PreferenceBundles/KeyboardGlassPrefs.bundle/Root.plist` |
| `prefs/Resources/entry.plist` | `Library/PreferenceLoader/Preferences/KeyboardGlass.plist` |

Rootless / RootHide 仅对上述安装位置采用打包系统已有的前缀/重定位；偏好数据始终优先读真实用户路径 `/var/mobile/Library/Preferences/com.ning.keyboardglass.plist`，不拼接 `/var/jb` 或随机越狱根。读文件缺 key 时才回退到同步后的 `CFPreferencesCopyAppValue`。不存在、类型错误或未知值均按 `0` 处理。

设置面板只接受数值 `0/1`，拒绝 bool、字符串和分数；先执行 `CFPreferencesSetAppValue` 与 `CFPreferencesAppSynchronize`，再保留该域其他数据并原子写入真实用户文件。成功写入或确认 CFPreferences 回读为所选模式后发送 Darwin 通知。安装包不应预置用户偏好 plist。

## 主进程 API 接入

将 `NGPreferences.m` 编译进主 dylib。公开头 `NGPreferences.h` 无 UIKit 依赖，可由 C / Objective-C / C++ 使用：

```c
int NGKeyboardRenderingMode(void);
void NGKeyboardPreferencesReload(void);
void NGKeyboardPreferencesObserve(void (*callback)(void));
```

在主进程初始化时调用一次：

```objc
#import "NGPreferences.h"

static void NGKeyboardModeDidChange(void) {
    // 已在主线程，缓存也已更新。在这里刷新已显示键盘并重设模式。
    // 渲染模块从 NGKeyboardRenderingMode() 读取 0 / 1。
}

// 放进主进程现有初始化入口：
NGKeyboardPreferencesObserve(NGKeyboardModeDidChange);
```

`NGKeyboardRenderingMode()` 第一次读取加载偏好，之后返回原子缓存；`NGKeyboardPreferencesReload()` 显式重载但不调用 callback。`Observe` 通过 `dispatch_once` 每进程只注册一次，注册后立即加载偏好，通知触发主队列重载再 callback；初始加载不 callback。首次传入的 callback 在该进程生命周期内保持有效，后续 `Observe` 不替换；允许传 `NULL`。没有轮询、定时器或 respring 操作。

本模块未改主渲染文件和打包脚本；即时切换还依赖主渲染调用方接入上述初始化与刷新回调。

## 依赖与资源 seal

- 主偏好模块：Foundation、CoreFoundation、libSystem（dispatch / 原子操作）；不依赖 UIKit 或 Preferences 私有框架。
- Settings bundle：UIKit、Foundation、CoreFoundation，以及系统私有 `Preferences.framework`（链接时加 `-F <SDK>/System/Library/PrivateFrameworks -framework Preferences`）；Darwin `notify_post` 来自 libSystem。
- 设备运行时由 PreferenceLoader 加载 bundle；包依赖需要已有 `preferenceloader`。不引入 Cephei / AppList / 其他设置框架。
- `Info.plist` 的 executable 必须为 `KeyboardGlassPrefs`，principal class 必须为 `NGKeyboardGlassRootListController`。`entry.plist` 放在 PreferenceLoader 目录，不是 bundle 内的资源。
- 必须先组装完整 `KeyboardGlassPrefs.bundle`（可执行文件、`Info.plist`、`Root.plist`），再对整个 bundle 签名并执行 strict 验签，不能只签可执行文件。资源 seal 产生后，不可再修改 plist 或资源；修改后须重签整个 bundle。最终包内和解包后的资源也应保持一致。

## 本地语法检查

在 `source` 目录执行；仅检查语法，不生成目标文件或实际构建：

```sh
clang -target arm64e-apple-ios15.0 \
  -isysroot /var/minis/shared/sdks/iPhoneOS16.5.sdk \
  -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -fsyntax-only \
  NGPreferences.m prefs/NGKeyboardGlassRootListController.m
```

此检查已通过（无 warning / error）。设备加载、真实写入权限及 UI 即时切换需在主模块接入后另行验证；本次未构建、未安装、未运行远端或 CI。
