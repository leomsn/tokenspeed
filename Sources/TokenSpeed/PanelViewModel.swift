import AppKit
import Combine
import SwiftUI

final class PanelViewModel: ObservableObject {
    @Published var link: LinkState = .never
    @Published var reading: Reading?
    @Published var enabledFields: Set<PanelField> = PanelField.defaults
    @Published var pinned: Bool = false
    @Published var lastUpdated: Date?
    @Published var lastError: String?
}

final class PanelController {
    static let panelWidth: CGFloat = 320
    private static let initialHeight: CGFloat = 260

    private var panel: NSPanel?
    private var viewModel: PanelViewModel
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var anchorWindow: NSWindow?

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // 面板隐藏时 AppDelegate 不往 ViewModel 推数据（隐藏的 SwiftUI 树照样逐轮重排），
    // 打开的瞬间补一次，保证看到的是最新值。
    var onShown: (() -> Void)?

    func show(relativeTo button: NSStatusBarButton) {
        let panel = ensurePanel()
        anchorWindow = button.window
        position(relativeTo: button)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 要排在 orderFront 之后：applyPinning 看 isVisible 决定是否装外部点击监视器
        applyPinning()
        onShown?()
    }

    func hide() {
        panel?.orderOut(nil)
        removeOutsideClickMonitor()
    }

    func setPinned(_ on: Bool) {
        viewModel.pinned = on
        Settings.shared.panelPinned = on
        applyPinning()
    }

    // SwiftUI 侧内容高度变了就调这里；保持顶边位置，向下生长
    func contentSizeChanged(to newSize: CGSize) {
        guard let panel = panel else { return }
        let screenFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        let maxH = max(140, (screenFrame?.height ?? 900) - 60)
        // 高度取整到整点，并要求至少差 1 点才 resize：忙时每轮数字宽度都在变，
        // 内容高度在零点几点之间来回抖；不取整就每轮触发一次整窗 setFrame（重排 + 阴影重绘）。
        let target = NSSize(width: PanelController.panelWidth,
                            height: ceil(min(newSize.height, maxH)))
        let old = panel.frame
        guard abs(old.height - target.height) > 1.0 else { return }
        let topY = old.maxY
        var originY = topY - target.height
        if let sf = screenFrame, originY < sf.minY + 8 { originY = sf.minY + 8 }
        panel.setFrame(NSRect(origin: NSPoint(x: old.origin.x, y: originY), size: target),
                       display: true, animate: false)
    }

    private func ensurePanel() -> NSPanel {
        if let p = panel { return p }
        let initial = NSSize(width: PanelController.panelWidth,
                             height: PanelController.initialHeight)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = PanelRootView(vm: viewModel,
                                 onPin: { [weak self] in self?.setPinned(!(self?.viewModel.pinned ?? false)) },
                                 onClose: { [weak self] in self?.hide() },
                                 idealWidth: PanelController.panelWidth,
                                 onSizeChange: { [weak self] s in self?.contentSizeChanged(to: s) })
        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: initial)
        p.contentView = host
        panel = p
        return p
    }

    private func position(relativeTo button: NSStatusBarButton) {
        guard let panel = panel, let btnWindow = button.window else { return }
        let btnFrame = btnWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = btnFrame.midX - PanelController.panelWidth / 2
        let topY = btnFrame.minY - 6
        // 用窗口当前真实高度，不用别处记下的内容高度：首次打开时内容高度还没测过，
        // 窗口实际高度是 SwiftUI 的拟合尺寸（比 initialHeight 估计值矮一大截），
        // 按估计值算 origin 会把整块面板压低几十个点。
        let y = max(((btnWindow.screen ?? NSScreen.main)?.visibleFrame.minY ?? 10) + 8,
                    topY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 驻留的唯一真相：只有不驻留才装"点外部就隐藏"的监视器——装了它就等于没驻留，
    /// 而图钉仍会显示实心。show / setPinned 都只走这里，不许各自记得装卸。
    private func applyPinning() {
        guard let panel = panel else { return }
        panel.level = .floating
        panel.hidesOnDeactivate = !viewModel.pinned
        if viewModel.pinned {
            removeOutsideClickMonitor()
        } else if isVisible {
            installOutsideClickMonitor()
        }
    }

    private func installOutsideClickMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] evt in
            guard let self = self, let win = self.panel?.contentView?.window else { return evt }
            if evt.window == win { return evt }
            // 左键点菜单栏图标不算"点外部"：它只负责打开浮窗，不该在 mouseDown 先把浮窗关掉
            if evt.type == .leftMouseDown, let anchor = self.anchorWindow, evt.window === anchor { return evt }
            self.hide()
            return evt
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
