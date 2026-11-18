# KeyboardGlass 0.1.7 (native Glassify Regular candidate)

Target: iOS 17.2.1 RootHide. This tweak affects only system keyboard background views. Keys, candidate text, Dock controls, language switching and dictation are left to UIKit. Author: Ning&Hung Phan.

The material is the unmodified Glassify GLSGlassView: default Regular, Automatic frost, nil tint, original shader. There is no fixed PNG, build-host bake, settings mode selector or static fallback. The glass is inserted into the keyboard's UIInputSetHostView, interaction-disabled. A non-keyboard UIView in the same app scene is used as the original renderer's backdrop source. The native background remains visible until a real Metal output texture produces an opaque centre pixel; it is restored if the keyboard detaches. This is a development candidate, not device-verified.

The keyboard may run in a separate process without access to the target App's layer tree. In that case the native background remains: no substitute wallpaper or fake glass is shown. UIKBBackdropView presence and view ordering on iOS 17.2.1 have not been verified at runtime. Vendor/Glassify inputs are checked against upstream revision a8e52aa9c015502fb68d5f81687698f11df6977d. The complete original shader metallib is bundled. No source or CI check proves on-device rendering, performance or cross-process capture.
