import Combine
import Foundation

/// 语言切换的通知源。文案本身走 L() 现读，这里只负责"语言变了，把界面重算一遍"，
/// 所以视图里的用法是 @ObservedObject 一个没人读的字段——它是重绘的引子，不是数据。
final class LanguageCenter: ObservableObject {
    static let shared = LanguageCenter()
    @Published private(set) var current: UILanguage = Language.current

    func reload() { current = Language.current }
}

// MARK: - 语言选择（存 UserDefaults，界面可覆盖系统语言）

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans, zhHant
    var id: String { rawValue }

    /// 语言名用各自的语言写，不随界面语言变（系统设置里的惯例）；只有"跟随系统"要翻。
    var label: String {
        switch self {
        case .system:  return L("跟随系统")
        case .en:      return "English"
        case .zhHans:  return "简体中文"
        case .zhHant:  return "繁體中文"
        }
    }
}

/// 解析后真正生效的界面语言（.system 已展开）。
enum UILanguage: String {
    case en, zhHans, zhHant

    /// 数字分组等跟着界面语言走，别出现"中文界面 + 德式千分位"
    var locale: Locale {
        switch self {
        case .en: return Locale(identifier: "en")
        case .zhHans: return Locale(identifier: "zh_CN")
        case .zhHant: return Locale(identifier: "zh_TW")
        }
    }
}

enum Language {
    static var current: UILanguage {
        switch Settings.shared.appLanguage {
        case .en:     return .en
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        case .system: return systemPreferred()
        }
    }

    private static func systemPreferred() -> UILanguage {
        for tag in Locale.preferredLanguages {
            let t = tag.replacingOccurrences(of: "_", with: "-")
            if t.hasPrefix("zh") {
                // zh-Hant / zh-HK / zh-MO / zh-Hant-TW 归繁体，其余 zh* 归简体
                if t.contains("Hant") || t.hasPrefix("zh-HK") || t.hasPrefix("zh-MO") { return .zhHant }
                return .zhHans
            }
            if t.hasPrefix("en") { return .en }
        }
        return .en
    }
}

// MARK: - 取文案
//
// key 就是代码里的简体中文原文，所以 zhHans 不需要一张表：查不到即返回 key 本身。
// 表里只有 en 与 zhHant 两列，漏译的界面会直接露出中文，一眼可查。
// 繁体按台湾用词（佇列／記憶體／伺服器／重新整理），不是逐字繁简转换——
// StringTransform 那类转换会把「母/媽」「里/裡」这类转错，术语也不对。

func L(_ src: String) -> String {
    Strings.lookup(src, in: Language.current)
}

/// 先查表再套格式，所以各语言可以自己决定语序；两个以上占位符时用 %1$@ 这种带序号的写法。
func LF(_ src: String, _ args: CVarArg...) -> String {
    String(format: L(src), arguments: args)
}

enum Strings {
    static func lookup(_ src: String, in lang: UILanguage) -> String {
        guard lang != .zhHans else { return src }
        return table[src]?[lang.rawValue] ?? src
    }

    private static let table: [String: [String: String]] = [
        // 关于窗
        "关于 TokenSpeed": ["en": "About TokenSpeed", "zhHant": "關於 TokenSpeed"],
        "版本 %@": ["en": "Version %@", "zhHant": "版本 %@"],
        "本机菜单栏显示 Strata 的解码速度、队列与硬件占用。": [
            "en": "Shows your local Strata server's decode speed, queue and hardware usage in the menu bar.",
            "zhHant": "本機選單列顯示 Strata 的解碼速度、佇列與硬體占用。",
        ],
        "开源许可": ["en": "License", "zhHant": "授權條款"],
        "MIT 许可证": ["en": "MIT License", "zhHant": "MIT 授權條款"],
        "项目主页": ["en": "Project page", "zhHant": "專案首頁"],
        // 设置窗口
        "TokenSpeed 设置": ["en": "TokenSpeed Settings", "zhHant": "TokenSpeed 設定"],
        "通用": ["en": "General", "zhHant": "一般"],
        "跟随系统": ["en": "Follow System", "zhHant": "跟隨系統"],
        "语言": ["en": "Language", "zhHant": "語言"],
        "Strata 服务端": ["en": "Strata Server", "zhHant": "Strata 伺服器"],
        "服务器 URL": ["en": "Server URL", "zhHant": "伺服器 URL"],
        "类型目前仅支持 Strata": [
            "en": "Only Strata servers are supported for now",
            "zhHant": "類型目前僅支援 Strata",
        ],
        "未设置（菜单栏会显示 ! ）": [
            "en": "Not set (menu bar shows ! )",
            "zhHant": "未設定（選單列會顯示 ! ）",
        ],
        "已保存 · 不会再次显示，输入新值可覆盖": [
            "en": "Saved — type to replace it",
            "zhHant": "已儲存 · 不會再次顯示，輸入新值可覆蓋",
        ],
        "当前来自环境变量 STRATA_API_KEY": [
            "en": "From STRATA_API_KEY env var",
            "zhHant": "目前來自環境變數 STRATA_API_KEY",
        ],
        "验证": ["en": "Verify", "zhHant": "驗證"],
        "验证中…": ["en": "Verifying…", "zhHant": "驗證中…"],
        "连接正常，已读到 /metrics": [
            "en": "Connected — /metrics read OK",
            "zhHant": "連線正常，已讀到 /metrics",
        ],
        "先在上方验证连接": [
            "en": "Verify the connection above first",
            "zhHant": "請先在上方驗證連線",
        ],
        "刷新": ["en": "Refresh", "zhHant": "重新整理"],
        "间隔": ["en": "Interval", "zhHant": "間隔"],
        "%.1f 秒": ["en": "%.1f s", "zhHant": "%.1f 秒"],
        "单位后缀": ["en": "Unit suffix", "zhHant": "單位後綴"],
        "面板字段": ["en": "Panel Fields", "zhHant": "面板欄位"],
        "恢复默认字段": ["en": "Restore Default Fields", "zhHant": "回復預設欄位"],
        "取消": ["en": "Cancel", "zhHant": "取消"],
        "保存": ["en": "Save", "zhHant": "儲存"],

        // 面板字段勾选名
        "模型 / 引擎版本": ["en": "Model / engine version", "zhHant": "模型 / 引擎版本"],
        "忙闲状态": ["en": "Busy state", "zhHant": "忙閒狀態"],
        "解码 tok/s": ["en": "Decode tok/s", "zhHant": "解碼 tok/s"],
        "预填充 tok/s": ["en": "Prefill tok/s", "zhHant": "預填充 tok/s"],
        "队列 (running/queued/waiting)": [
            "en": "Queue (running/queued/waiting)",
            "zhHant": "佇列 (running/queued/waiting)",
        ],
        "Slots 详情": ["en": "Slots detail", "zhHant": "Slots 詳細"],
        "最近一次请求": ["en": "Last request", "zhHant": "最近一次請求"],
        "GPU 利用率": ["en": "GPU utilization", "zhHant": "GPU 使用率"],
        "GPU 温度": ["en": "GPU temperature", "zhHant": "GPU 溫度"],
        "GPU 功率": ["en": "GPU power", "zhHant": "GPU 功率"],
        "显存": ["en": "VRAM", "zhHant": "VRAM"],
        "内存": ["en": "RAM", "zhHant": "記憶體"],
        "累计统计": ["en": "Totals", "zhHant": "累計統計"],

        // 右键菜单
        "立即刷新": ["en": "Refresh Now", "zhHant": "立即重新整理"],
        "暂停轮询": ["en": "Pause Polling", "zhHant": "暫停輪詢"],
        "恢复轮询": ["en": "Resume Polling", "zhHant": "繼續輪詢"],
        "显示面板": ["en": "Show Panel", "zhHant": "顯示面板"],
        "隐藏面板": ["en": "Hide Panel", "zhHant": "隱藏面板"],
        "面板驻留": ["en": "Pin Panel", "zhHant": "釘選面板"],
        "设置…": ["en": "Settings…", "zhHant": "設定…"],
        "退出 TokenSpeed": ["en": "Quit TokenSpeed", "zhHant": "結束 TokenSpeed"],

        // 浮窗
        "取消驻留": ["en": "Unpin", "zhHant": "取消釘選"],
        "驻留浮窗（驻留后可拖动）": [
            "en": "Pin the panel (draggable once pinned)",
            "zhHant": "釘選面板（釘選後可拖曳）",
        ],
        "关闭": ["en": "Close", "zhHant": "關閉"],
        "等待首次取数…": ["en": "Waiting for first fetch…", "zhHant": "等待首次取數…"],
        "等待首次取数": ["en": "Waiting for first fetch", "zhHant": "等待首次取數"],
        "服务忙": ["en": "Server busy", "zhHant": "服務忙碌"],
        "服务空闲": ["en": "Server idle", "zhHant": "服務閒置"],
        "取数失败": ["en": "Fetch failed", "zhHant": "取數失敗"],
        "速度": ["en": "Speed", "zhHant": "速度"],
        "状态": ["en": "State", "zhHant": "狀態"],
        "解码": ["en": "Decode", "zhHant": "解碼"],
        "预填充": ["en": "Prefill", "zhHant": "預填充"],
        "空闲": ["en": "Idle", "zhHant": "閒置"],
        "读取提示词": ["en": "Reading prompt", "zhHant": "讀取提示詞"],
        "生成中": ["en": "Generating", "zhHant": "生成中"],
        "排队准入": ["en": "Admitting", "zhHant": "排隊准入"],
        "模型未加载": ["en": "Model unloaded", "zhHant": "模型未載入"],
        "上次 %1$@ tok": ["en": "Last %1$@ tok", "zhHant": "上次 %1$@ tok"],
        "模型": ["en": "Model", "zhHant": "模型"],
        "%1$@  ·  引擎 %2$@  ·  ctx %3$@": [
            "en": "%1$@  ·  engine %2$@  ·  ctx %3$@",
            "zhHant": "%1$@  ·  引擎 %2$@  ·  ctx %3$@",
        ],
        "队列": ["en": "Queue", "zhHant": "佇列"],
        "%1$d 运行 · %2$d 排队 · %3$d 等待 / %4$d": [
            "en": "%1$d running · %2$d queued · %3$d waiting / %4$d",
            "zhHant": "%1$d 運行 · %2$d 排隊 · %3$d 等待 / %4$d",
        ],
        "最近请求": ["en": "Last request", "zhHant": "最近請求"],
        "温度": ["en": "Temp", "zhHant": "溫度"],
        "功率": ["en": "Power", "zhHant": "功率"],
        "累计": ["en": "Totals", "zhHant": "累計"],

        // 速度数字旁边的来源口径（必须与数字一起显示，见 CLAUDE.md 3.4）
        "当前": ["en": "now", "zhHant": "目前"],
        "本次请求": ["en": "this request", "zhHant": "本次請求"],

        // 菜单栏 tooltip
        "TokenSpeed — 取数失败：%1$@": [
            "en": "TokenSpeed — fetch failed: %1$@",
            "zhHant": "TokenSpeed — 取數失敗：%1$@",
        ],
        "TokenSpeed — 等待首次取数": [
            "en": "TokenSpeed — waiting for first fetch",
            "zhHant": "TokenSpeed — 等待首次取數",
        ],

        // 取数层报错（会进菜单栏 tooltip 与浮窗红字）
        "URL 无效: %1$@": ["en": "Invalid URL: %1$@", "zhHant": "URL 無效：%1$@"],
        "响应异常: %1$@": ["en": "Bad response: %1$@", "zhHant": "回應異常：%1$@"],
        "鉴权失败 (%1$d) — 检查 API key": [
            "en": "Auth failed (%1$d) — check the API key",
            "zhHant": "驗證失敗 (%1$d) — 檢查 API 金鑰",
        ],
        "解析失败: %1$@": ["en": "Parse failed: %1$@", "zhHant": "解析失敗：%1$@"],
        "缺 %1$@": ["en": "missing %1$@", "zhHant": "缺少 %1$@"],
        "类型 %1$@": ["en": "type %1$@", "zhHant": "類型 %1$@"],
        "值缺失 %1$@": ["en": "value missing %1$@", "zhHant": "值缺失 %1$@"],
        "损坏": ["en": "corrupted", "zhHant": "損壞"],
    ]
}
