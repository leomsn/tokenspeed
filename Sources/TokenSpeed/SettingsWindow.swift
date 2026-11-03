import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        // 窗口尺寸跟着内容的理想尺寸走：换语言、勾多勾少时自己伸缩，既不留空白也不出滚动条
        hosting.sizingOptions = [.preferredContentSize]
        let win = NSWindow(contentViewController: hosting)
        win.title = L("TokenSpeed 设置")
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        // 别让窗口一打开就把焦点塞进第一个输入框：那里是全选状态，误按一个键整条地址就被替换掉
        win.initialFirstResponder = win.contentView
        win.center()
        self.init(window: win)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 布局全部自己排：以前用 Form，macOS 会让整张表单共用一条"标签列"，
/// 列宽取全表单最宽的标签——于是标签一变动（拖动间隔那条最明显），全窗每一行跟着横向抖。
/// 这里标签列宽度写死，抖的根就没了；高度交给内容，窗口按 preferredContentSize 贴合。
struct SettingsView: View {
    // 语言选完立刻生效，所以这里也得跟着重算，不然切了语言这个窗口还是旧文案
    @ObservedObject private var lang = LanguageCenter.shared

    @State private var language: AppLanguage = Settings.shared.appLanguage
    @State private var serverURL: String = Settings.shared.serverURL
    @State private var keyDraft: String = ""
    @State private var verify: Verify = .idle
    /// 只在"这次要存一把新 key"时要求先验证：没填 key 就没什么可验的，
    /// 否则改个间隔、勾个栏位也得先打一次 /metrics 才让保存。
    /// 填了 key 之后改动 URL 会让验证作废——那是"验的是旧地址、存的是新地址"。
    @State private var verified = false
    @State private var refresh: Double = Settings.shared.refreshSeconds
    @State private var unit: String = Settings.shared.unitSuffix
    @State private var fields: Set<PanelField> = Settings.shared.enabledFields

    private enum Verify: Equatable {
        case idle, running, ok(String), failed(String)
    }

    private static let labelWidth: CGFloat = 86

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                card(L("通用")) {
                    row(L("语言")) {
                        Picker(selection: $language, label: EmptyView()) {
                            ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: language) { newValue in
                            // 立刻写盘并生效：不点"保存"也要马上看到自己选的那门语言长什么样，
                            // 所以这条不受下面的"保存"约束。
                            Settings.shared.appLanguage = newValue
                            (NSApp.delegate as? AppDelegate)?.applyLanguageChange()
                        }
                    }
                }

                card(L("Strata 服务端")) {
                    row(L("服务器 URL")) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: serverURL) { _ in verified = false }
                            Text(L("类型目前仅支持 Strata"))
                                .font(.system(size: 9.5))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                    row("API key") {
                        HStack(spacing: 8) {
                            SecureField(keyPlaceholder, text: $keyDraft)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: keyDraft) { _ in verified = false }
                            Button(verify == .running ? L("验证中…") : L("验证")) { verifyNow() }
                                .disabled(verify == .running)
                        }
                    }
                    verifyLine
                }

                card(L("刷新")) {
                    row(L("间隔")) {
                        // 不给 step：SwiftUI 在 macOS 上会把 step 画成一排刻度，46 道很吵。
                        // 连续滑动 + 存盘时取整到 0.1，显示和落库都是 0.1 的倍数。
                        Slider(value: $refresh, in: 0.5...5.0)
                        Text(LF("%.1f 秒", refresh))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                    row(L("单位后缀")) {
                        TextField("", text: $unit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }

                card(L("面板字段")) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 5) {
                        ForEach(PanelField.allCases) { f in
                            Toggle(f.label, isOn: Binding(
                                get: { fields.contains(f) },
                                set: { on in if on { fields.insert(f) } else { fields.remove(f) } }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(20)

            Divider()
            HStack(spacing: 10) {
                Button(L("恢复默认字段")) { fields = PanelField.defaults }
                Spacer()
                Button(L("取消")) { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
                Button(L("保存")) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .help(L("改过 API key 才需要先在上方验证连接"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
    }

    /// 输入框空着 = 不打算换 key = 这次保存没有凭据要验，直接让存。
    private var canSave: Bool {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || verified
    }

    /// 输入框空着的时候，占位文字说明这把 key 现在到底从哪来。
    private var keyPlaceholder: String {
        switch Settings.shared.apiKeySource {
        case .saved: return L("已保存 · 不会再次显示，输入新值可覆盖")
        case .env:   return L("当前来自环境变量 STRATA_API_KEY")
        case .unset: return L("未设置（菜单栏会显示 ! ）")
        }
    }

    private var verifyLine: some View {
        Group {
            if case let .ok(msg) = verify { statusLine(msg, bad: false) }
            if case let .failed(msg) = verify { statusLine(msg, bad: true) }
        }
    }

    @ViewBuilder
    private func statusLine(_ msg: String, bad: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(bad ? Color.red : Color.green).frame(width: 6, height: 6)
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(bad ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Self.labelWidth + 8)
    }

    /// 只读一次 /metrics 来验：连得上、key 对、返回能解析，才算通过。
    private func verifyNow() {
        let urlText = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText) else {
            verify = .failed(LF("URL 无效: %1$@", urlText))
            verified = false
            return
        }
        let draft = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = draft.isEmpty ? Settings.shared.apiKey : draft
        verify = .running
        let client = StrataClient(baseURL: url, apiKey: key)
        Task { @MainActor in
            do {
                _ = try await client.fetchMetrics()
                verify = .ok(L("连接正常，已读到 /metrics"))
                verified = true
            } catch {
                let msg = (error as? StrataError)?.errorDescription ?? error.localizedDescription
                verify = .failed(msg)
                verified = false
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    /// 一行 = 定宽标签 + 控件。标签定宽是这条布局不起抖的关键，别改回自适应。
    @ViewBuilder
    private func row<Content: View>(_ label: String,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func apply() {
        Settings.shared.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { Settings.shared.saveApiKey(draft) }
        // 存完就把手里的明文丢掉：这窗口之后再也显示不出这把 key
        keyDraft = ""
        Settings.shared.refreshSeconds = (refresh * 10).rounded() / 10
        Settings.shared.unitSuffix = unit
        Settings.shared.enabledFields = fields
        (NSApp.delegate as? AppDelegate)?.reloadSettings()
        NSApp.keyWindow?.close()
    }
}
