# KeyboardGlass 0.1.1 — fixed keyboard background

Target: iOS 17.2.1 / RootHide. Author: Ning. Repository: SorenNing/KeyboardGlass.

This revision addresses the user's screenshots: join the candidate strip and key area into one continuous glass surface; give the outside a 3pt rim and 16pt corners; remove the candidate arrow's separate background/leading hairline while preserving its glyph, targets and hit testing. Language and dictation buttons keep their native appearance.

KeyboardSurface.m groups adjacent UIKBBackdropView/UIKBBackgroundView regions and candidate bounds within the same window and keyboard host. It installs one noninteractive fixed UIImageView beneath each connected group and suppresses background-only native views, including their separate corner images. Detached, hidden, excluded accessory, or unsupported regions restore native appearance. UIInputWindowControllerHostingItem identifies the app's accessory backdrop for exclusion. Candidate views contribute bounds without hiding candidate text. Hook installation is once per method, including late TextInputUI bundle loads.

The material is an original, build-time CPU-generated transparent PNG inspired by the requested Theseus appearance, not the Theseus shader. Material.h embeds the PNG. There are no screenshots, Metal rendering, display links or polling timers. Layout callbacks only maintain frames and visibility; the material is never regenerated in the keyboard process.

Local checks: three Objective-C translation units pass arm64e strict syntax checks with iPhoneOS16.5 SDK; portable geometry cases cover candidate/key/dock merging, rotation, one-handed widths, split-keyboard isolation, separate host identity and invalid bounds. These checks do not prove native UIKit behavior. Private interface evidence comes from the 17.2 (21C62) headers on headers.82flex.com, not a runtime dump of 17.2.1. Actual visibility, cross-app coverage, seam removal, arrow-line removal, keyboard transitions and behavior alongside other keyboard tweaks require device testing.

Manual-only macOS CI builds a native arm64e RootHide package, verifies subtype 0x80000002 and strictly verifies the signed library before and after extraction from the final deb. The package uses root Library/MobileSubstrate paths and the UIKit bundle filter, with embedded assets and no jbroot filesystem API dependency. build.py links UIKit, Foundation, CoreGraphics and QuartzCore explicitly. Every new build requires user authorization.
