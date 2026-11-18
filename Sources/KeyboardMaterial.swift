import UIKit
import Metal
import ObjectiveC
import os.log

private let log = OSLog(subsystem: "com.ning.keyboardglass", category: "material")
private var materialKey: UInt8 = 0

@objc(NGTheseusBridge)
final class NGTheseusBridge: NSObject {
    @objc(applyTo:) static func apply(to host: UIVisualEffectView) {
        guard Thread.isMainThread else { return }
        if let material = objc_getAssociatedObject(host, &materialKey) as? KeyboardMaterial {
            material.refresh()
            return
        }
        guard host.window != nil, !host.bounds.isEmpty,
              MetalContext.shared != nil,
              let source = KeyboardMaterial.source(for: host) else { return }
        let material = KeyboardMaterial(host: host, source: source)
        objc_setAssociatedObject(host, &materialKey, material, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        host.contentView.insertSubview(material, at: 0)
        material.refresh()
    }
}

// Theseus renders only a UIView tree in the current process. Never pretend a
// keyboard-only remote window contains the app underneath it.
private final class KeyboardMaterial: UIView {
    private weak var host: UIVisualEffectView?
    private weak var captureSource: UIView?
    private let glass = TheseusView()
    private let shade = CALayer()
    private let glow = CALayer()
    private var activated = false
    private var lastSize = CGSize.zero
    private var lastDark: Bool?

    static func source(for host: UIView) -> UIView? {
        guard let keyboardWindow = host.window,
              let scene = keyboardWindow.windowScene else { return nil }
        // Restrict capture to a visible app window below the keyboard in this
        // scene. No screen capture, private cross-process API or synthetic image.
        return scene.windows.filter {
            $0 !== keyboardWindow && !$0.isHidden && $0.alpha > 0 &&
            $0.windowLevel <= keyboardWindow.windowLevel &&
            $0.rootViewController != nil &&
            !NSStringFromClass(type(of: $0)).localizedCaseInsensitiveContains("keyboard") &&
            !NSStringFromClass(type(of: $0)).localizedCaseInsensitiveContains("texteffects")
        }.sorted { $0.windowLevel > $1.windowLevel }.first
    }

    init(host: UIVisualEffectView, source: UIView) {
        self.host = host
        captureSource = source
        super.init(frame: host.contentView.bounds)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clipsToBounds = true
        glass.isUserInteractionEnabled = false
        glass.sourceView = source
        glass.continuousUpdate = true
        glass.onPresent = { [weak self] in self?.presented() }
        addSubview(glass)
        layer.addSublayer(shade)
        layer.addSublayer(glow)
        shade.compositingFilter = "multiplyBlendMode"
        glow.compositingFilter = "screenBlendMode"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func presented() {
        guard !activated, window != nil, host != nil,
              captureSource != nil else { return }
        activated = true
        os_log("Theseus first GPU frame presented", log: log, type: .default)
    }

    func refresh() {
        guard let host = host else { return }
        guard let source = Self.source(for: host), host.window != nil else {
            glass.pauseRendering()
            isHidden = true
            return
        }
        isHidden = false
        captureSource = source
        glass.sourceView = source
        frame = host.contentView.bounds
        glass.frame = bounds
        let dark = traitCollection.userInterfaceStyle == .dark
        if lastSize != bounds.size || lastDark != dark {
            lastSize = bounds.size
            lastDark = dark
            var config = TheseusConfiguration()
            config.captureMethod = .layerRendering
            config.shape.cornerRadius = 0
            config.blur.radius = 18
            config.refraction.edgeWidth = 0
            config.refraction.dispersion = 0
            config.refraction.interiorSharpness = dark ? TheseusTabBar.chromeDetailDark : TheseusTabBar.chromeDetailLight
            config.refraction.interiorAverage = TheseusTabBar.chromeAverage
            config.theme.neutralBodyScale = 1
            let chrome = TheseusTabBar.iOS27Chrome(isDark: dark, spectrum: 0.5)
            config.theme.bodyCurve = chrome.knots
            config.theme.bodyCurveChromaSlope = chrome.chromaSlope
            config.theme.bodyCurveSaturation = 1
            config.theme.backdropSaturation = chrome.chroma
            config.theme.backdropGain = 1
            config.theme.luminanceLift = 0
            config.outerGlow = 0
            config.edgeFeather = TheseusTabBar.chromeFeather
            glass.configuration = config
            // Exact upstream edgeImages profiles, adapted only from a capsule
            // distance field to the keyboard's rectangular background bounds.
            let edges = KeyboardEdges.images(size: bounds.size, scale: window?.screen.scale ?? UIScreen.main.scale, dark: dark)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shade.frame = bounds; glow.frame = bounds
            shade.contents = edges.shade; glow.contents = edges.glow
            CATransaction.commit()
        }
        glass.resumeRendering()
        glass.invalidateBackground()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            glass.pauseRendering()
        } else {
            refresh()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refresh()
    }
}
