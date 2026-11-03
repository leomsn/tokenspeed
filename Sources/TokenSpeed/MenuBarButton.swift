import AppKit
import Combine
import QuartzCore

final class MenuBarButton {
    let statusItem: NSStatusItem
    private(set) var current: MenuBarState = .never

    private var animTimer: Timer?
    private var blinkOn: Bool = true

    // 数字用 condensed + monospacedDigit 的 SF，右下角标用小一号同族字体
    // 数字用系统菜单栏默认字体（SF Text, systemFontSize, monospacedDigit）；右下角标用小一号同族字体
    static let numberFont: NSFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize, weight: .regular)
    static let unitFont: NSFont = NSFont.systemFont(ofSize: 8.5, weight: .regular)

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.imagePosition = .imageLeading
            b.image = IconRenderer.image(state: .never)
            b.attributedTitle = Self.attributed(core: Self.titleCore(for: .never).text, unit: "")
            b.target = self
            b.action = #selector(handleClick)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = "TokenSpeed"
        }
    }

    static func attributed(core: String, unit: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: core, attributes: [
            .font: numberFont,
            .foregroundColor: NSColor.labelColor,
        ])
        if !unit.isEmpty {
            s.append(NSAttributedString(string: unit, attributes: [
                .font: unitFont,
                .baselineOffset: -1.5,
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        return s
    }

    // 数字/关键字/占位符；unit 通过 attributed(core:unit:) 作为右下角标附加。
    // numeric 必须回传：右下角标是吞吐单位，只能贴数字。忙但拿不到解码速度时核心回落成
    // 状态词，那时再挂 "t/s" 就是把一个词显示成吞吐，违反 3.4 口径纪律。
    static func titleCore(for state: MenuBarState, tok: Double? = nil,
                          busyLabel: String? = nil) -> (text: String, numeric: Bool) {
        switch state {
        case .never:  return (padLeft("—"), false)
        case .idle:   return (padLeft("idle"), false)
        case .failed: return (padLeft("!"), false)
        case .busy:
            if let t = tok, t > 0 {
                return (String(format: "%5.1f", min(t, 999.9)), true)
            } else if let label = busyLabel, !label.isEmpty {
                return (label, false)
            } else {
                return (padLeft("—"), false)
            }
        }
    }

    private static func padLeft(_ s: String) -> String {
        if s.count >= 5 { return String(s.prefix(5)) }
        return String(repeating: " ", count: 5 - s.count) + s
    }

    var button: NSStatusBarButton? { statusItem.button }

    func update(link: LinkState, reading: Reading?) {
        let newState: MenuBarState
        switch link {
        case .failed:
            newState = .failed
        case .never:
            newState = .never
        case .ok:
            if let r = reading {
                newState = (r.serverState == .busy) ? .busy : .idle
            } else {
                newState = .never
            }
        }
        current = newState
        apply(state: newState, reading: reading, link: link)
        if newState == .busy { startPulse() } else { stopPulse() }
        if newState == .failed && animTimer == nil { startBlink() }
        if newState != .busy && newState != .failed { stopAnimation() }
    }

    func setClickHandlers(onLeft: @escaping () -> Void, onRight: @escaping (NSEvent) -> Void) {
        self.onLeft = onLeft
        self.onRight = onRight
    }

    private var onLeft: (() -> Void)?
    private var onRight: ((NSEvent) -> Void)?

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { onLeft?(); return }
        if event.type == .rightMouseUp {
            onRight?(event)
        } else {
            onLeft?()
        }
    }

    // 值没变就不赋值。每轮轮询都换一个"新" image / 新 attributedTitle，等于每轮都把状态项
    // 标脏一次，菜单栏随之重画；空闲时没有任何动画，界面却一直在重绘（实测 12% CPU）。
    private var lastImage: NSImage?
    private var lastCore = ""
    private var lastUnit = ""

    private func setImage(_ img: NSImage) {
        if img === lastImage { return }
        lastImage = img
        button?.image = img
    }

    private func apply(state: MenuBarState, reading: Reading?, link: LinkState) {
        guard let b = button else { return }
        setImage(icon(for: state))
        let core = Self.titleCore(for: state,
                                   tok: reading?.decodeTokS,
                                   busyLabel: reading?.snapshot.live.state)
        let unit = core.numeric ? Settings.shared.unitSuffix : ""
        if core.text != lastCore || unit != lastUnit {
            lastCore = core.text
            lastUnit = unit
            b.attributedTitle = Self.attributed(core: core.text, unit: unit)
            // 标题一变，按钮就变宽，图标（连同脉冲环）跟着右移
            if pulseLayer != nil { layoutPulse() }
        }
        let tip = tooltipText(link: link, reading: reading)
        if tip != lastTip { lastTip = tip; b.toolTip = tip }
    }

    private var lastTip = ""

    private func icon(for state: MenuBarState) -> NSImage {
        switch state {
        case .never:         return IconRenderer.image(state: .never)
        case .idle:          return IconRenderer.image(state: .idle)
        case .busy:          return IconRenderer.image(state: .busy)
        case .failed:        return IconRenderer.failedBlinkImage(on: blinkOn)
        }
    }

    private func tooltipText(link: LinkState, reading: Reading?) -> String {
        switch link {
        case .failed(let msg): return LF("TokenSpeed — 取数失败：%1$@", msg)
        case .never:           return L("TokenSpeed — 等待首次取数")
        case .ok:
            if let r = reading {
                let model = r.snapshot.engine.model ?? "?"
                let ver = r.snapshot.engine.version ?? "?"
                let server = Settings.shared.serverURL
                return "TokenSpeed · \(model) v\(ver)\n\(server)"
            }
            return "TokenSpeed"
        }
    }

    // 忙态的脉冲环。之前是 20 Hz 定时器每帧现画一个 dynamic NSImage 再赋给按钮：
    // 每帧都把状态项标脏，AppKit 按显示帧率重画整个按钮（sample 里全在
    // NSStatusBarButtonCell drawWithFrame → NSCustomImageRep draw），服务一忙就 15% CPU，
    // 跟浮窗开不开无关。改成 button.layer 上的 CAShapeLayer + 无限循环动画：
    // 逐帧插值由 WindowServer 做，进程侧每帧零开销。
    private var pulseLayer: CAShapeLayer?
    private static let pulsePeriod = 1.0 / 1.2               // 与旧实现 phase 每秒推进 1.2 圈一致
    private static let ringInner: CGFloat = IconRenderer.dotRadius + 2.0
    private static let ringGrow: CGFloat = 4.5

    private func startPulse() {
        guard pulseLayer == nil, let b = button else { return }
        b.wantsLayer = true
        guard let host = b.layer else { return }
        let ring = CAShapeLayer()
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.systemGreen.cgColor
        ring.lineWidth = 1.5
        ring.allowsEdgeAntialiasing = true
        pulseLayer = ring
        beginWithoutAnimation { layoutPulse() }
        ring.opacity = 0.85
        host.insertSublayer(ring, at: 0)
        addPulseAnimation(to: ring)
    }

    private func layoutPulse() {
        guard let b = button, let ring = pulseLayer, let cell = b.cell as? NSButtonCell else { return }
        var rect = cell.imageRect(forBounds: b.bounds)
        if rect.width < 4 || rect.height < 4 {
            rect = NSRect(x: 4,
                          y: (b.bounds.height - IconRenderer.size.height) / 2,
                          width: IconRenderer.size.width,
                          height: IconRenderer.size.height)
        }
        let rIn = Self.ringInner
        let side = (rIn + Self.ringGrow) * 2 + ring.lineWidth
        ring.contentsScale = b.window?.backingScaleFactor ?? 2
        ring.bounds = NSRect(x: 0, y: 0, width: side, height: side)
        ring.anchorPoint = NSPoint(x: 0.5, y: 0.5)
        ring.position = NSPoint(x: rect.midX, y: rect.midY)
        ring.path = CGPath(ellipseIn: NSRect(x: side / 2 - rIn, y: side / 2 - rIn,
                                             width: rIn * 2, height: rIn * 2), transform: nil)
    }

    private func addPulseAnimation(to ring: CAShapeLayer) {
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = (Self.ringInner + Self.ringGrow) / Self.ringInner
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Self.pulsePeriod
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "pulse")
    }

    // CALayer 改 frame/path 默认带 0.25 秒隐式动画：栏位每轮变宽都会让脉冲环抖一下
    private func beginWithoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private func stopPulse() {
        guard let ring = pulseLayer else { return }
        ring.removeAllAnimations()
        ring.removeFromSuperlayer()
        pulseLayer = nil
    }

    private func startBlink() {
        animTimer?.invalidate()
        blinkOn = true
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.blinkOn.toggle()
            self.setImage(IconRenderer.failedBlinkImage(on: self.blinkOn))
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
        setImage(IconRenderer.image(state: current == .idle ? .idle : .never))
    }
}
