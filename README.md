# KeyboardGlass — Theseus keyboard material

Experimental iOS 17+ tweak, package `com.ning.keyboardglass`, author Ning.

`KeyboardBackground.m` hooks `UIKBBackdropView.layoutSubviews` with `MSHookMessageEx`. After the original layout it immediately clears the native effect and the host/content background colors, then invokes the Theseus bridge. This does not wait for a GPU frame. No native background is restored if rendering or capture is unavailable.

`Sources/KeyboardMaterial.swift` uses the real Theseus Metal renderer and the fixed upstream tab-bar background parameters, including blur18 and light/dark chrome curves. The noninteractive material is inserted into the backdrop's content view. `KeyboardEdges.swift` adapts the upstream edge profiles to the keyboard rectangle.

Theseus is vendored unmodified from `valzevul/Theseus` revision `71ca1c127a4e7fe3387361f160c4890dbd427f66`. Its Apache-2.0 license, NOTICE and per-file hashes are under `Vendor/Theseus`. The build patches temporary compilation copies to disable the visual-effect fallback and compile the embedded original Metal shader at runtime.

Capture currently requires a same-process app window in the keyboard's scene. In remote keyboard processes without this source, the system backdrop is still cleared, but the Theseus material cannot render. This is an accepted current limitation, not verified cross-process support.

## Build and status

Only `apelin_project_build` runs the declared external producer `tools/apelin_build.py`. A compatible Swift compiler, clang and iPhoneOS SDK are required. RootHide builds arm64e; rootless builds arm64 and arm64e. The static prototype is archived under `Baseline/0.1.0` and is not compiled. The old root producer is disabled. GitHub Actions runs `tools/ci_compile.py` on pushes to main and manual dispatch using Xcode on macOS; it uploads a signed arm64e dylib, its verification receipt and upstream notices, not an installable Debian package.

CI run #21 successfully compiled and signed the arm64e material. Apelin subsequently produced roothide debug package `0.2.0-theseus5` using the pinned CI ZIP and receipt checks in `tools/package_ci.py`; place that ZIP under `.build/ci-artifacts/keyboard-glass-theseus-64e.zip` to use this route. The package records both its build ID and the compiled commit; its load marker retains the CI commit. Installation and device validation have not occurred. Local source compilation remains blocked by the registered compiler environment. Runtime shader compilation, backdrop transparency, material appearance, light/dark transitions, rotation and keyboard interactions remain untested. See `AGENTS.md` for validation requirements.
