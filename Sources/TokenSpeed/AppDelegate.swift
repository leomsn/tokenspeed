import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuButton: MenuBarButton!
    private var panelVM = PanelViewModel()
    private var panelController: PanelController!
    private var settingsController: SettingsWindowController?
    private var aboutController: AboutWindowController?
    private var pollTask: Task<Void, Never>?
    private var client: StrataClient?

    private(set) var lastLink: LinkState = .never
    private(set) var lastReading: Reading?
    private var paused: Bool = false
    private var healthOnce = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuButton = MenuBarButton()
        panelController = PanelController(viewModel: panelVM)
        panelVM.enabledFields = Settings.shared.enabledFields
        panelVM.pinned = Settings.shared.panelPinned
        panelController.onShown = { [weak self] in self?.publish() }

        menuButton.setClickHandlers(
            onLeft: { [weak self] in
                guard let self = self, let b = self.menuButton.button, !self.panelController.isVisible else { return }
                self.panelController.show(relativeTo: b)
            },
            onRight: { [weak self] _ in
                self?.showMenu()
            }
        )

        rebuildClient()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
    }

    func reloadSettings() {
        panelVM.enabledFields = Settings.shared.enabledFields
        rebuildClient()
        startPolling()
    }

    /// 语言是即时生效的（不点"保存"也要立刻看到自己选的那门语言长什么样），
    /// 所以单开一条：重算 SwiftUI 面板、改设置窗口标题。右键菜单每次现建，不用管。
    func applyLanguageChange() {
        LanguageCenter.shared.reload()
        settingsController?.window?.title = L("TokenSpeed 设置")
    }

    private func rebuildClient() {
        guard let url = URL(string: Settings.shared.serverURL) else {
            lastLink = .failed(LF("URL 无效: %1$@", Settings.shared.serverURL))
            publish()
            client = nil
            return
        }
        client = StrataClient(baseURL: url, apiKey: Settings.shared.apiKey)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if !self.paused { await self.pollOnce() }
                let s = max(0.5, Settings.shared.refreshSeconds)
                try? await Task.sleep(nanoseconds: UInt64(s * 1e9))
            }
        }
    }

    @MainActor
    private func pollOnce() async {
        guard let client = client else { return }
        if !healthOnce {
            if case let .ok(model, ctx, keyReq, loaded) = try? await client.fetchHealth() {
                NSLog("[TokenSpeed] health ok: model=\(model) ctx=\(ctx) key=\(keyReq) loaded=\(loaded)")
                healthOnce = true
            }
        }
        do {
            let snap = try await client.fetchMetrics()
            let reading = buildReading(from: snap)
            NSLog("[TokenSpeed] metrics ok state=%@ tok_s=%@ slot0=%@",
                  snap.live.state,
                  snap.live.tok_s.map { String(format: "%.1f", $0) } ?? "nil",
                  snap.live.slots?.first.map { "\($0.state)/\(slotValue($0))" } ?? "-")
            self.lastLink = .ok
            self.lastReading = reading
            self.publish()
        } catch {
            let msg = (error as? StrataError)?.errorDescription ?? error.localizedDescription
            NSLog("[TokenSpeed] metrics FAIL: %@", msg)
            self.lastLink = .failed(msg)
            self.publish()
        }
    }

    private func publish() {
        menuButton.update(link: lastLink, reading: lastReading)
        // 浮窗关着就别往 ViewModel 推：隐藏的 SwiftUI 树照样逐轮重排（sample 里
        // LayoutEngineBox.sizeThatFits / StackLayout.placeChildren 一样在跑），纯浪费。
        // @Published 一变整棵树全部失效，服务忙时浮窗开着就是 12-16% CPU 的来源。
        guard panelController.isVisible else { return }
        panelVM.link = lastLink
        panelVM.reading = lastReading
        panelVM.lastUpdated = Date()
        if case .failed(let m) = lastLink { panelVM.lastError = m } else { panelVM.lastError = nil }
    }

    // MARK: - Right-click menu

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let refresh = NSMenuItem(title: L("立即刷新"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let pause = NSMenuItem(title: paused ? L("恢复轮询") : L("暂停轮询"),
                               action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let togglePanel = NSMenuItem(title: panelController.isVisible ? L("隐藏面板") : L("显示面板"),
                                     action: #selector(togglePanelAction), keyEquivalent: "d")
        togglePanel.target = self
        togglePanel.keyEquivalentModifierMask = [.command]
        menu.addItem(togglePanel)

        let pin = NSMenuItem(title: L("面板驻留"), action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.state = panelVM.pinned ? .on : .off
        menu.addItem(pin)

        menu.addItem(.separator())

        let about = NSMenuItem(title: L("关于 TokenSpeed"), action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let settings = NSMenuItem(title: L("设置…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("退出 TokenSpeed"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        if let b = menuButton.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: b.bounds.maxY + 4),
                       in: b)
        }
    }

    @objc private func refreshNow() {
        Task { await self.pollOnce() }
    }

    @objc private func togglePause() {
        paused.toggle()
    }

    @objc private func togglePanelAction() {
        if panelController.isVisible {
            panelController.hide()
        } else if let b = menuButton.button {
            panelController.show(relativeTo: b)
        }
    }

    @objc private func togglePin() {
        panelController.setPinned(!panelVM.pinned)
    }

    @objc private func openAbout() {
        if aboutController == nil { aboutController = AboutWindowController() }
        aboutController?.show()
    }

    @objc private func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.show()
    }
}
