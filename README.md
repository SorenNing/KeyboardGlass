# KeyboardGlass 0.1.11

Target: iOS 17.2.1 / RootHide. Author: Ning.

System Settings → 键盘玻璃 provides the current original material plus six procedural presets: clear, frost, crystal, ice, smoke and liquid. Each preset keeps its own saved overrides. Sixteen sliders control system backdrop alpha, body RGB, opacity and brightness, gradient strength/direction, highlight thickness/brightness/width, inner/outer shadow, edge softness, corner radius and superellipse corner shape. Each slider has a separate visible group title. Restore-current clears only the current preset's overrides; restore-all restores original material and system alpha 1.0.

`GlassPreferences.h` is the shared settings model with finite-number validation and bounds. `GlassRenderer.h` creates a cached premultiplied RGBA stretchable material on the main thread. Variable corners and edge features stay inside the fixed cap areas. Outer shadows fit within the existing keyboard clipping, without expanding layout. The untouched original PNG remains the default until the original skin is customized. No image files, screenshots, remote capture, Metal, or background sampling are used.

The existing keyboard layout hook, connected-region seam alignment, and original-layout-first behavior remain. A Darwin preference notification invalidates the cached material and schedules layout on known weakly held backdrops. Closing/reopening the keyboard also applies changes. System backdrop alpha defaults to 1.0, independently of skin opacity. Preferences persist through CFPreferences under `com.ning.keyboardglass`.

Builds are manual GitHub Actions on macos-latest, arm64e only. Native Xcode builds both the engine and PreferenceLoader bundle, checks subtype 0x80000002 and verifies strict signatures on final-package executables. The Preferences bundle resolves the already-loaded private Preferences framework at runtime. The source carries its own narrow declarations instead of an SDK-private framework dependency.

Local strict arm64e syntax validation is not an on-device Settings/UI test. Confirm row visibility, parameter persistence across Apps, skin switching, reset actions, keyboard clipping and visual results after installation. These are static material controls; they do not implement real-time refraction. Stable 0.1.0 and the 0.1.10 alpha0.9 package remain separate saved releases.
