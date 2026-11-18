# KeyboardGlass original implementation restored

User requested rollback from Theseus to original 0.1.0. Active KeyboardBackground.m, Material.h and GlassBackground.png match commit 82d5fc92f415391a42ae6a20ca5a046dac7221f0 byte-for-byte. Baseline/0.1.0 remains archival. Sources/ and Vendor/Theseus remain historical experimental files, excluded from the active build. No Swift, Metal or Theseus is compiled into the rollback.

Package ID remains com.ning.keyboardglass. tools/apelin_build.py VERSION is 0.2.1-rollback1, deliberately higher than installed 0.2.0-theseus6 so implementation rollback can upgrade normally. Increment VERSION before each formal build attempt.

Only apelin_project_build invokes tools/apelin_build.py to produce a package. tools/ci_compile.py compiles only the original Objective-C source using the original compiler flags and frameworks, signs and verifies arm64e output, and uploads a receipt; it never produces a package. The root build.py and archived baseline build.py are never executed. CI workflow still uses historical artifact name keyboard-glass-theseus-64e, but the rollback artifact contains only the original dynamic library and verification.json.

Verified CI run 44332720926, commit 5f41d796aa8bb2dbf374ce6c18775b0d71447f45. Download https://nightly.link/SorenNing/KeyboardGlass/actions/runs/44332720926/keyboard-glass-theseus-64e.zip to .build/ci-artifacts/keyboard-glass-original-64e.zip. tools/package_ci.py pins the ZIP digest and validates receipt, baseline, architecture and lack of Swift/Theseus references. Only roothide arm64e is supported by this pinned artifact.

Apelin build 66375f93-6f34-46d6-9e48-7327269dae61 produced 0.2.1-rollback1 successfully. Installation was attempted under the user's rollback authorization but refused: installed com.ning.keyboardglass 0.2.0-theseus6 came from another source. The user must remove that externally installed package with their package manager before this artifact can be installed. Never work around this by renaming the package or deleting installed files. The device remains on theseus6 until installation succeeds.

Original source has no ApelinLoaded marker; do not claim load confirmation. Runtime appearance and keyboard interaction are untested. Ask separately before screen access or screenshots. After successful installation ask user to fully exit and reopen Settings; do not manipulate the screen without permission.
