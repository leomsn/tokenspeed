import Foundation

enum PanelField: String, CaseIterable, Identifiable {
    case modelVersion = "model_version"
    case liveState = "live_state"
    case decodeSpeed = "decode_speed"
    case prefillSpeed = "prefill_speed"
    case queueDepth = "queue_depth"
    case slots = "slots"
    case lastRequest = "last_request"
    case gpuUtil = "gpu_util"
    case gpuTemp = "gpu_temp"
    case gpuPower = "gpu_power"
    case vram = "vram"
    case cpu = "cpu"
    case ram = "ram"
    case totals = "totals"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modelVersion: return L("模型 / 引擎版本")
        case .liveState:    return L("忙闲状态")
        case .decodeSpeed:  return L("解码 tok/s")
        case .prefillSpeed: return L("预填充 tok/s")
        case .queueDepth:   return L("队列 (running/queued/waiting)")
        case .slots:        return L("Slots 详情")
        case .lastRequest:  return L("最近一次请求")
        case .gpuUtil:      return L("GPU 利用率")
        case .gpuTemp:      return L("GPU 温度")
        case .gpuPower:     return L("GPU 功率")
        case .vram:         return L("显存")
        case .cpu:          return "CPU"
        case .ram:          return L("内存")
        case .totals:       return L("累计统计")
        }
    }

    static let defaults: Set<PanelField> = [
        .modelVersion, .liveState, .decodeSpeed, .prefillSpeed,
        .queueDepth, .lastRequest, .gpuUtil, .vram, .ram
    ]
}

final class Settings {
    static let shared = Settings()

    private let ud = UserDefaults.standard

    private enum K {
        static let serverURL = "serverURL"
        static let refreshSeconds = "refreshSeconds"
        static let panelFields = "panelFields"
        static let unitSuffix = "unitSuffix"
        static let panelPinned = "panelPinned"
        static let appLanguage = "appLanguage"
        static let apiKey = "apiKey"
    }

    init() {
        ud.register(defaults: [
            K.serverURL: "http://10.10.1.1:8008",
            K.refreshSeconds: 1.5,
            K.unitSuffix: "t/s",
        ])
        // 老版本的默认是 " tok/s"，迁移到新默认
        if ud.string(forKey: K.unitSuffix) == " tok/s" {
            ud.removeObject(forKey: K.unitSuffix)
        }
    }

    var serverURL: String {
        get { ud.string(forKey: K.serverURL) ?? "http://10.10.1.1:8008" }
        set { ud.set(newValue, forKey: K.serverURL) }
    }

    var refreshSeconds: Double {
        get { max(0.5, ud.double(forKey: K.refreshSeconds)) }
        set { ud.set(newValue, forKey: K.refreshSeconds) }
    }

    var unitSuffix: String {
        get { ud.string(forKey: K.unitSuffix) ?? "t/s" }
        set { ud.set(newValue, forKey: K.unitSuffix) }
    }

    /// 默认跟随系统；用户在设置窗口里选了就固定用它
    var appLanguage: AppLanguage {
        get { ud.string(forKey: K.appLanguage).flatMap(AppLanguage.init(rawValue:)) ?? .system }
        set { ud.set(newValue.rawValue, forKey: K.appLanguage) }
    }

    var panelPinned: Bool {
        get { ud.bool(forKey: K.panelPinned) }
        set { ud.set(newValue, forKey: K.panelPinned) }
    }

    var enabledFields: Set<PanelField> {
        get {
            guard let arr = ud.array(forKey: K.panelFields) as? [String] else {
                return PanelField.defaults
            }
            let set = Set(arr.compactMap(PanelField.init(rawValue:)))
            return set.isEmpty ? PanelField.defaults : set
        }
        set { ud.set(Array(newValue).map { $0.rawValue }, forKey: K.panelFields) }
    }

    /// 这把 key 现在从哪来。界面上要把它说清楚，否则"输入框是空的"会被当成"没配 key"。
    enum ApiKeySource { case saved, env, unset }

    var apiKeySource: ApiKeySource {
        if !(ud.string(forKey: K.apiKey) ?? "").isEmpty { return .saved }
        return (ProcessInfo.processInfo.environment["STRATA_API_KEY"] ?? "").isEmpty ? .unset : .env
    }

    /// 设置窗口里保存的 key 优先；没保存过才回退到环境变量 STRATA_API_KEY。
    /// 保存的这把只在取数时读出来用，界面上不回显、也不提供"查看"。
    var apiKey: String? {
        let saved = ud.string(forKey: K.apiKey) ?? ""
        if !saved.isEmpty { return saved }
        let env = ProcessInfo.processInfo.environment["STRATA_API_KEY"] ?? ""
        return env.isEmpty ? nil : env
    }

    func saveApiKey(_ key: String) {
        ud.set(key, forKey: K.apiKey)
    }
}
