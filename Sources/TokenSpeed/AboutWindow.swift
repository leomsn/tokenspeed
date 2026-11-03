import AppKit
import SwiftUI

/// 关于窗。这个 app 是 `.accessory`（没有 Dock 图标也没有主菜单），
/// 所以 macOS 自带的「关于本机器」面板根本不存在，只能自己开一个。
final class AboutWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = [.preferredContentSize]
        let win = NSWindow(contentViewController: hosting)
        win.title = L("关于 TokenSpeed")
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
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

struct AboutView: View {
    // 切语言要立刻重算文案，和设置窗同一个引子
    @ObservedObject private var lang = LanguageCenter.shared

    var body: some View {
        VStack(spacing: 8) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }
            Text(AppInfo.name)
                .font(.system(size: 15, weight: .semibold))
            Text(LF("版本 %@", AppInfo.version))
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text(L("本机菜单栏显示 Strata 的解码速度、队列与硬件占用。"))
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            HStack(spacing: 4) {
                Text(L("开源许可"))
                Text("·")
                Text(L("MIT 许可证"))
            }
            .font(.system(size: 10))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            if let url = AppInfo.siteURL, let link = URL(string: url) {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Text(L("项目主页")).font(.system(size: 10))
                }
                .buttonStyle(.link)
            }
            Text(AppInfo.copyright)
                .font(.system(size: 9.5))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}
