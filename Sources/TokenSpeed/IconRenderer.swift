import AppKit

enum MenuBarState: Equatable {
    case never          // 尚未取到数据
    case idle           // 连接正常，空闲
    case busy           // 连接正常，忙
    case failed         // 连接/服务/鉴权失败
}

enum IconRenderer {
    static let size = NSSize(width: 18, height: 18)

    // 四个态各只画一次、之后复用同一个实例。drawingHandler 造的 NSImage 没有可缓存的位图，
    // 每轮轮询再现画一个的话，菜单栏按钮会被逐帧重画——实测浮窗关着、服务空闲时也占 12% CPU，
    // 忙时更是 15%，sample 里全落在 NSStatusBarButtonCell drawWithFrame。
    // 忙态的脉冲环不在这里画：它改成 button.layer 上的 CALayer 动画（见 MenuBarButton.startPulse），
    // 逐帧插值交给 WindowServer，进程侧每帧零开销。
    private static var staticCache: [MenuBarState: NSImage] = [:]

    static let dotRadius: CGFloat = 4.5

    static func image(state: MenuBarState) -> NSImage {
        if let hit = staticCache[state] { return hit }
        let img = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let r = dotRadius

            switch state {
            case .never:
                drawRing(center: center, radius: r, color: NSColor.systemGreen, lineWidth: 1.5)

            case .idle, .busy:
                fillCircle(center: center, radius: r, color: NSColor.systemGreen)

            case .failed:
                fillCircle(center: center, radius: r, color: NSColor.systemRed)
            }
            return true
        }
        img.isTemplate = false
        staticCache[state] = img
        return img
    }

    static func failedBlinkImage(on: Bool) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 4.5
            let color: NSColor = on ? .systemRed : .systemRed.withAlphaComponent(0.25)
            fillCircle(center: center, radius: r, color: color)
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func fillCircle(center: NSPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2)).fill()
    }

    private static func drawRing(center: NSPoint, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        let p = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
        p.lineWidth = lineWidth
        p.stroke()
    }
}
