# KeyboardGlass 0.1.9 experimental build

Built by the existing manual GitHub Actions workflow on macos-latest. Push does not trigger a build. The output is an iphoneos-arm64e RootHide package.

The keyboard backdrop hook already runs in the host App process (recorded in Minis and Preferences device logs). Its capture callback now calls AppWindowCapture.draw directly on the main thread. It selects an unambiguous active App window on the same screen and renders only its root content layer into the current in-memory capture buffer. Region coordinates are mapped without stretching. There is no PNG producer, image file, window screenshot, or IPC.

Frames carry a generation and monotonic timestamp. Successful GPU completion is bound to its captured frame before dynamic glass becomes visible. Capture failure, inactive/offscreen state, invalid alpha, unsupported layers, ambiguous windows, and frame expiry restore the static material. Sampled alpha, luma, and fingerprint are logged without saving pixels. Theseus blur18, chrome curves, system backdrop alpha0.8, keyboard keys, and seam geometry retain their previous values.

## Implementation limits

- Root content must belong to the same active process. A separate-process keyboard host falls back to static material.
- Core Animation CPU capture cannot reliably draw remote WebKit, Metal, video, or system backdrop layers. Intersecting unsupported layers are rejected.
- Some Apps resize their content above the keyboard. Insufficient coverage falls back instead of stretching unrelated content.
- Compilation, package structure, signatures, and coordinate tests do not establish on-device visual correctness. Test App scrolling and changing backgrounds against the input fingerprint after installation.

Version 0.1.0 remains the user-designated stable rollback baseline.
