# Keyboard static glass prototype

Target: iOS 17.2.1 / RootHide, system keyboard background only.

KeyboardBackground.m hooks UIKBBackdropView layoutSubviews through MSHookMessageEx after checking class ancestry and return ABI. Original layout runs first. It puts one noninteractive stretchable UIImageView into the background contentView and clears the background effect. Resource decoding happens once; no screenshots, Metal, timers or display links.

GlassBackground.png is an original CPU-generated transparent white body and rim approximation inspired by the requested Theseus appearance. It is NOT an output baked from Theseus's shader and does not reproduce refraction. Material.h embeds the same PNG so runtime resource paths are unnecessary.

arm64 and arm64e Objective-C syntax checks passed with iPhoneOS16.5 SDK. No iOS link, signing, package, injection or runtime test has occurred. The package filter targets UIKit processes; actual keyboard-host coverage requires device testing. UIKBBackdropView is supported by the iOS17.2 header; actual 17.2.1 appearance and whether lower layers remain opaque are unverified. Clearing UIVisualEffectView.effect can change content vibrancy and must be checked on-device. This source is a prototype, not a ready-to-install package.

User selected SorenNing for the new independent KeyboardGlass repository and one 64e test build. Manual-only workflow uses native Xcode arm64e compilation, verifies subtype 0x80000002 and strictly verifies signatures again on the library extracted from the final deb. Author: Ning. This prototype uses an embedded image and UIKit only, with no jbroot filesystem API dependency.
