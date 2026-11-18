# Ning Keyboard Glass

The active implementation is restored byte-for-byte to original 0.1.0 at commit `82d5fc92f415391a42ae6a20ca5a046dac7221f0`: `KeyboardBackground.m`, `Material.h` and `GlassBackground.png`. Theseus experiments remain in Git history and inactive source directories.

The rollback package version is `0.2.1-rollback1` to supersede experimental packages. This is a packaging version; implementation remains original 0.1.0.

GitHub Actions compiles only the original Objective-C implementation and signs/verifies arm64e output. Apelin's declared producer `tools/apelin_build.py` packages a pinned verified CI ZIP. Neither archived `build.py` is executed. See AGENTS.md for the exact artifact and build procedure.

The rollback package built successfully. Installation was blocked because the currently installed `0.2.0-theseus6` came from another source; the user must remove it with their package manager before Apelin can install the rollback artifact. Appearance and input behavior remain untested.
