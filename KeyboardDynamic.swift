import UIKit
import Metal

func NGDynamicLog(_ message: String) {
    let line = "[KG019 \(ProcessInfo.processInfo.processIdentifier)] \(Date()) \(message)\n"
    let path = "/var/mobile/Library/Accessibility/KeyboardGlass-dynamic-\(ProcessInfo.processInfo.processIdentifier).log"
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    if let file = FileHandle(forWritingAtPath: path) {
        file.seekToEndOfFile(); file.write(Data(line.utf8)); file.closeFile()
    }
}

extension Bundle {
    static let module: Bundle = {
        let root = String(cString: NGResourceDirectory())
        guard let bundle = Bundle(path: root + "/KeyboardGlass.bundle") else {
            fatalError("KeyboardGlass resource bundle missing")
        }
        return bundle
    }()
}

@objc(NGTheseusKeyboardView) final class NGTheseusKeyboardView: UIView {
    private let glass: TheseusView
    private weak var host: UIVisualEffectView?
    private weak var fallback: UIView?
    private var lastPresent: CFTimeInterval = 0
    private var lastGeneration: UInt64 = 0
    private var monitor: DisplayLinkDriver.Link?
    private var configuredDark: Bool?
    private var edgeKey = CGSize.zero
    private var edgeDark: Bool?
    private var lastLog: CFTimeInterval = 0
    private let shade = CALayer()
    private let glow = CALayer()
    override init(frame: CGRect) {
        var c = TheseusConfiguration()
        c.captureMethod = .layerRendering
        c.blur.radius = 18
        c.refraction.edgeWidth = 0
        c.refraction.dispersion = 0
        c.refraction.interiorAverage = 80
        c.theme.neutralBodyScale = 1
        c.outerGlow = 0
        c.edgeFeather = 1.0 / 3.0
        glass = TheseusView(configuration: c)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        glass.alpha = 0
        addSubview(glass)
        glow.compositingFilter = "plusL"
        layer.addSublayer(shade); layer.addSublayer(glow)
        glass.onPresent = { [weak self] in
            guard let self = self else { return }
            guard let host = self.host, let window = host.window,
                  self.visibleAncestors(host), UIApplication.shared.applicationState == .active,
                  let frame = NGKeyboardCapture.presented(window),
                  frame.generation > self.lastGeneration,
                  CACurrentMediaTime() - frame.time < 0.4 else { return }
            self.lastGeneration = frame.generation
            self.lastPresent = CACurrentMediaTime()
            if self.lastPresent - self.lastLog > 10 {
                NGDynamicLog("GPU present blur=18 window=\(String(describing: self.host?.window))")
                self.lastLog = self.lastPresent
            }
            self.glass.alpha = 1
            self.fallback?.alpha = 0
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc(configureHost:fallback:) func configureHost(_ host: UIVisualEffectView, fallback: UIView) {
        self.host = host; self.fallback = fallback
        glass.sourceView = host.window
        glass.continuousUpdate = false
        updateMaterial()
        setNeedsLayout()
    }
    private func updateMaterial() {
        let dark = traitCollection.userInterfaceStyle == .dark
        guard configuredDark != dark else { return }; configuredDark = dark
        var c = glass.configuration
        let curve = TheseusTabBar.iOS27Chrome(isDark: dark, spectrum: 0.5)
        c.theme.isDark = dark
        c.theme.bodyCurve = curve.knots
        c.theme.bodyCurveChromaSlope = curve.chromaSlope
        c.theme.bodyCurveSaturation = 1
        c.theme.backdropSaturation = curve.chroma
        c.theme.backdropGain = 1
        c.theme.luminanceLift = 0
        c.refraction.interiorSharpness = dark ? 0.42 : 0.48
        c.shape.cornerRadius = 14
        glass.configuration = c
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        updateMaterial()
        shade.frame = bounds; glow.frame = bounds
        if edgeKey != bounds.size || edgeDark != configuredDark {
            edgeKey = bounds.size; edgeDark = configuredDark
            let images = NGKeyboardEdges.make(size: bounds.size, scale: window?.screen.scale ?? 3, dark: configuredDark ?? false)
            shade.contents = images.shade; glow.contents = images.glow
            shade.contentsScale = window?.screen.scale ?? 3; glow.contentsScale = shade.contentsScale
        }
        glass.invalidateBackground()
    }
    private func visibleAncestors(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v.isHidden || v.alpha <= 0.01 { return false }
            current = v.superview
        }
        return true
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        monitor?.invalidate(); monitor = nil
        guard window != nil else { glass.pauseRendering(); glass.alpha = 0; fallback?.alpha = 1; return }
        glass.resumeRendering()
        monitor = DisplayLinkDriver.shared.add(framesPerSecond: .fps(10)) { [weak self] _ in
            guard let self = self else { return }
            guard let h = self.host, let w = h.window, self.visibleAncestors(h),
                  UIApplication.shared.applicationState == .active,
                  h.convert(h.bounds, to: w).intersects(w.bounds) else {
                self.glass.pauseRendering(); self.glass.alpha = 0; self.fallback?.alpha = 1; return
            }
            if self.glass.sourceView !== w { self.glass.sourceView = w; self.lastGeneration = 0 }
            self.glass.resumeRendering()
            self.glass.invalidateBackground()
            if NGKeyboardCapture.latest(w) == nil || CACurrentMediaTime() - self.lastPresent > 0.5 {
                self.glass.alpha = 0; self.fallback?.alpha = 1
            }
        }
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous); updateMaterial(); setNeedsLayout()
    }
}

// Capture runs synchronously inside the App process that owns this keyboard hook.
enum NGKeyboardCapture {
    struct Frame { let generation: UInt64; let time: CFTimeInterval; let region: CGRect }
    private static var presentedFrames: [ObjectIdentifier: Frame] = [:]
    private(set) static var frames: [ObjectIdentifier: Frame] = [:]
    private static var generation: UInt64 = 0
    static func draw(source: UIView, region: CGRect, context: CGContext) -> Bool {
        let key = ObjectIdentifier(source)
        guard AppWindowCapture.draw(source: source, region: region, context: context) else {
            frames.removeValue(forKey: key)
            return false
        }
        generation &+= 1
        frames[key] = Frame(generation: generation, time: CACurrentMediaTime(), region: region)
        return true
    }
    static func markPresented(_ source: UIView, frame: Frame) {
        presentedFrames[ObjectIdentifier(source)] = frame
    }
    static func presented(_ source: UIView) -> Frame? {
        guard frames[ObjectIdentifier(source)] != nil else { return nil }
        return presentedFrames[ObjectIdentifier(source)]
    }
    static func reject(_ source: UIView) { frames.removeValue(forKey: ObjectIdentifier(source)) }
    static func latest(_ source: UIView?) -> Frame? {
        guard let source = source else { return nil }
        return frames[ObjectIdentifier(source)]
    }
}
