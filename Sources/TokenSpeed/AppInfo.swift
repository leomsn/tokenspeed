import Foundation

/// 版本与项目信息的唯一来源。`tools/make_app.sh` 从这里取值写进 `Info.plist`，
/// 所以关于窗、Finder「显示简介」和 bundle 里的版本一定是同一个字符串。
enum AppInfo {
    static let name = "TokenSpeed"
    static let version = "1.0.2"
    static let build = "1"
    static let copyright = "© 2026 TokenSpeed contributors"

    /// bundle 标识、LaunchAgent 的 label 与 plist 文件名、`UserDefaults` 的域名三处共用这一个值，
    /// `tools/` 里的脚本也从这里取值——别在脚本里再写一遍。改它等于换设置域名，要搬 `UserDefaults`。
    static let bundleID = "com.eroeasy.tokenspeed"

    /// 关于窗「项目主页」那一行。站点还没上线，这一行暂时是死链；真要发版就先改回 `nil`。
    static let siteURL: String? = "https://tokenspeed.eroeasy.com"
}
