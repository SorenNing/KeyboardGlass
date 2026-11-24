import UIKit
import QuartzCore

/// App-content layers only. No window screenshot, disk pixels, or IPC.
enum AppWindowCapture {
    private static var lastMessage: String = ""
    private static var lastMessageTime: CFTimeInterval = 0
    private static func report(_ message: String) {
        let now = CACurrentMediaTime()
        if message != lastMessage || now - lastMessageTime > 10 {
            NGDynamicLog(message); lastMessage = message; lastMessageTime = now
        }
    }
    static func draw(source: UIView, region: CGRect, context: CGContext) -> Bool {
        guard Thread.isMainThread, let keyboard = source as? UIWindow,
              UIApplication.shared.applicationState == .active,
              region.width > 1, region.height > 1,
              [region.minX, region.minY, region.width, region.height].allSatisfy({ $0.isFinite }) else { return false }
        var windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive && $0.screen === keyboard.screen }
            .flatMap { $0.windows }
        // Some keyboard windows have no scene; the App's scene still must be active.
        if let scene = keyboard.windowScene, scene.activationState == .foregroundActive {
            windows = scene.windows + windows.filter { $0.windowScene !== scene }
        }
        var seen = Set<ObjectIdentifier>()
        let candidates = windows.filter { w in
            guard seen.insert(ObjectIdentifier(w)).inserted,
                  w !== keyboard, !w.isHidden, w.alpha > 0.99,
                  w.windowLevel == .normal, w.screen === keyboard.screen,
                  w.windowScene?.activationState == .foregroundActive,
                  let root = w.rootViewController?.viewIfLoaded,
                  root.window === w, !root.isHidden, root.alpha > 0.99 else { return false }
            return !forbidden(NSStringFromClass(type(of: w)))
        }
        let keys = candidates.filter { $0.isKeyWindow }
        let app: UIWindow
        if keys.count == 1 { app = keys[0] }
        else if candidates.count == 1 { app = candidates[0] }
        else { report("app-source unavailable/ambiguous count=\(candidates.count); PNG fallback"); return false }
        guard let root = app.rootViewController?.viewIfLoaded else { return false }
        let requested = source.convert(region, to: root)
        let visible = requested.intersection(root.bounds)
        // Shader capture includes blur padding. At least the keyboard's core must
        // overlap App content; modest edge padding is extended by the capture stage.
        guard !visible.isNull, visible.width >= requested.width * 0.75,
              visible.height >= requested.height * 0.75,
              abs(requested.width - region.width) < 1,
              abs(requested.height - region.height) < 1 else {
            report("app-content insufficient coverage; PNG fallback"); return false
        }
        var remaining = 2500
        guard clean(root, region: requested, root: root, remaining: &remaining) else {
            report("app-content has unsupported/keyboard layer; PNG fallback"); return false
        }
        // Root-local -> keyboard-window affine map. No resizing to keyboard bounds.
        let p = root.convert(CGPoint.zero, to: source)
        let x = root.convert(CGPoint(x: 1, y: 0), to: source)
        let y = root.convert(CGPoint(x: 0, y: 1), to: source)
        let map = CGAffineTransform(a: x.x-p.x, b: x.y-p.y, c: y.x-p.x,
                                    d: y.y-p.y, tx: p.x, ty: p.y)
        guard [map.a, map.b, map.c, map.d, map.tx, map.ty].allSatisfy({ $0.isFinite }),
              abs(map.a * map.d - map.b * map.c) > 0.99 else { return false }
        context.saveGState()
        context.clip(to: region)
        context.concatenate(map)
        let captured = NGRenderAppContent(root, context)
        context.restoreGState()
        guard captured else { report("app-content render exception; PNG fallback"); return false }
        report("app-content layer source=\(NSStringFromClass(type(of: root))) app=\(Bundle.main.bundleIdentifier ?? "unknown") crop=\(NSCoder.string(for: requested)) pixels=in-memory; keyboard-window excluded")
        return true
    }
    private static func forbidden(_ name: String) -> Bool {
        let value = name.lowercased()
        return ["keyboard", "uikb", "inputset", "texteffects", "ngtheseus", "theseusview", "remoteview"].contains { value.contains($0) }
    }
    private static func clean(_ view: UIView, region: CGRect, root: UIView, remaining: inout Int) -> Bool {
        if view.isHidden || view.alpha <= 0.01 { return true }
        if !view.convert(view.bounds, to: root).intersects(region) && view.clipsToBounds { return true }
        remaining -= 1
        guard remaining >= 0, !forbidden(NSStringFromClass(type(of: view))) else { return false }
        // Check only intersecting layer branches, including remote WKWebView content.
        func supported(_ layer: CALayer, depth: Int) -> Bool {
            if layer.isHidden || layer.opacity <= 0.01 { return true }
            let intersects = layer.convert(layer.bounds, to: root.layer).intersects(region)
            if !intersects && layer.masksToBounds { return true }
            guard depth < 48 else { return false }
            let name = NSStringFromClass(type(of: layer)).lowercased()
            if intersects && ["metal", "eagl", "playerlayer", "contextlayer", "backdrop"].contains(where: { name.contains($0) }) { return false }
            return (layer.sublayers ?? []).allSatisfy { supported($0, depth: depth + 1) }
        }
        if view === root && !supported(root.layer, depth: 0) { return false }
        if view.convert(view.bounds, to: root).intersects(region) && view is UIVisualEffectView { return false }
        for child in view.subviews {
            if !clean(child, region: region, root: root, remaining: &remaining) { return false }
        }
        return true
    }
}
