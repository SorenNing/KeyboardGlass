# KeyboardGlass Theseus experiment

## Scope and baseline

Start: SorenNing/KeyboardGlass main commit 82d5fc92f415391a42ae6a20ca5a046dac7221f0, original version 0.1.0. Baseline/0.1.0 preserves the original KeyboardBackground.m, Material.h, GlassBackground.png and build.py byte-for-byte. This directory is archival, never compiled by the active build. Recover original files explicitly from that directory or the original Git commit; there is no automatic static fallback.

Package ID stays com.ning.keyboardglass. Active experimental version is tools/apelin_build.py VERSION (0.2.0-theseus1 initially), deliberately distinct from historical 0.1.7. Increment VERSION before each new formal build attempt.

## Material

Vendor/Theseus is upstream https://github.com/valzevul/Theseus at 71ca1c127a4e7fe3387361f160c4890dbd427f66. UPSTREAM.json records archive and per-file SHA256 values. LICENSE is Apache-2.0 and NOTICE credits Vadim Drobinin. Vendor files stay unmodified.

Sources/KeyboardMaterial.swift uses the real TheseusView/TheseusRenderer Metal pipeline. Configuration comes from that revision's TheseusTabBar background: blur18, edgeWidth0, dispersion0, neutralBodyScale1, iOS27Chrome light/dark curves, chroma and detail values. Sources/KeyboardEdges.swift adapts upstream edgeImages from capsule to rectangular distance field and retains original profiles. It is not an exact capsule visual reproduction.

The build patches temporary compilation copies only: disable TheseusView's visual-effect fallback and replace Bundle.module shader lookup with the original embedded Metal source compiled by MTLDevice at runtime. No fake static image or synthesized backdrop is allowed.

Hook only UIKBBackdropView.layoutSubviews after its original implementation. Immediately clear its native effect, host color and content color before invoking Theseus, regardless of capture availability or first GPU frame. Do not restore the native background on source loss or renderer failure: the user explicitly accepts a transparent background in those cases. Material views are noninteractive. The real Theseus pipeline still requires a same-scene app window below the keyboard; own-process layer capture cannot see another process. Remote keyboard-only processes remain an unresolved material coverage limitation; do not invent or synthesize an input to hide it.

## Build

apelin-project.json is local/ignored. Declare external script tools/apelin_build.py with interpreter python3, arguments []. Only apelin_project_build produces packages. Never invoke the producer through shell_run, build a deb manually, or execute the archived baseline packaging script. The root build.py remains disabled. Authorized GitHub Actions now runs tools/ci_compile.py on main pushes or manual dispatch using a macOS Xcode runner. It compiles and signs the arm64e dynamic library and uploads it with a verification receipt and Theseus notices; it does not produce a .deb. Only Apelin's declared external producer creates installable packages.

Requires Swift-capable compiler plus matching iPhoneOS SDK, clang, ldid and dpkg-deb in Apelin's external environment. No Theos, xcrun or hard-coded jbroot paths. Compile arm64e for roothide; arm64+arm64e for rootless. Package staging includes Theseus licensing and provenance. Current device's registered compiler folders are reported missing; its SDK27 build attempt also exposed TargetConditionals and missing UIUtilities header failures. Workspace environment binding is refused by Apelin. Local source compilation remains unverified; verified CI compilation and precompiled packaging are described below.

## Verified CI artifact packaging

CI run 44316999330 at commit d08f39616f7f0e74b21908b11ce1c530388ad197 compiled, signed and checked the arm64e dylib successfully. Download the public artifact through `https://nightly.link/SorenNing/KeyboardGlass/actions/runs/44316999330/keyboard-glass-theseus-64e.zip` to `.build/ci-artifacts/keyboard-glass-theseus-64e.zip`. `tools/package_ci.py` pins the GitHub ZIP digest and receipt/dylib digests, architecture and notices. The producer uses this artifact when present; otherwise it compiles locally. This artifact supports roothide only; rootless requires its own compilation. Apelin debug build 399552f0-f3a4-4cbd-bab6-331c80f6bb21 successfully produced version 0.2.0-theseus5. No installation or runtime validation occurred. The precompiled load marker contains the CI commit, not the packaging build ID: automatic confirmation against the packaging ID cannot prove its load. Provenance in the package records both IDs.

## Checks and device validation

Read vendor manifest and verify SHA256, compare baseline files to original Git blobs, parse Python/JSON, inspect Git diff. Then build roothide debug with apelin_project_build after environment is repaired. Runtime shader compilation is separately unverified.

No installation, push, CI execution, screen access or screenshot is authorized by the implementation request. After explicit installation authorization, use apelin_package_install then apelin_package_confirm_loaded. Live logs use com.ning.keyboardglass. Device validation must cover same-process and remote keyboards, first GPU frame, source disappearance, light/dark, rotation, repeated show/hide, letters and numbers, candidate selection, emoji, dictation and secure fields. Test performance and memory during extended typing. Visual verification requires separately authorized screenshot. Main behavior remains untested until then.
