import Foundation

/// 服务端对同一个槽位有两种形状（2026-10-31 实测 0.1.52）：
/// 空闲 = {slot, state:"idle", held_tokens}；忙 = {slot, state:"reading"|"decoding",
/// prompt_tokens, prompt_read, generated, elapsed_s, tok_s}，**没有 held_tokens**。
/// 所以每个字段都得可空——写成非可空的话，任一槽位一变忙，整段 live 就解析失败。
struct LiveSlot: Decodable {
    let slot: Int
    let state: String
    let held_tokens: Int?
    let prompt_tokens: Int?
    let prompt_read: Int?
    let generated: Int?
    let elapsed_s: Double?
    let tok_s: Double?
}

struct LiveState: Decodable {
    let state: String
    let queued: Int?
    let running: Int?
    let waiting: Int?
    let admitting: Int?
    let parallel: Int?
    let outside_slots: Int?
    let phase: String?
    let prompt_tokens: Int?
    let prompt_read: Int?
    let prompt_total: Int?
    let generated: Int?
    let max_tokens: Int?
    let elapsed_s: Double?
    let tok_s: Double?
    let tok_s_mean: Double?
    let prefill_tok_s_mean: Double?
    let tok_s_window_s: Double?
    let slots: [LiveSlot]?
}

struct GPUInfo: Decodable, Identifiable {
    let index: Int
    let name: String
    let util: Double?
    let mem_used: Double?
    let mem_total: Double?
    let temp: Double?
    let power: Double?
    var id: Int { index }
}

struct Hardware: Decodable {
    let tok_s: Double?
    let tok_s_mean: Double?
    let prefill_tok_s_mean: Double?
    let gpu_util: Double?
    let gpu_temp: Double?
    let gpu_power: Double?
    let gpu_mem_used: Double?
    let gpu_mem_total: Double?
    let cpu: Double?
    let ram_used: Double?
    let ram_total: Double?
    let gpus: [GPUInfo]?

    init() {
        tok_s = nil; tok_s_mean = nil; prefill_tok_s_mean = nil
        gpu_util = nil; gpu_temp = nil; gpu_power = nil
        gpu_mem_used = nil; gpu_mem_total = nil
        cpu = nil; ram_used = nil; ram_total = nil; gpus = nil
    }
}

struct EngineInfo: Decodable {
    let model: String?
    let version: String?
    let max_context: Int?
    let kv: String?
    let drafting: String?
    let batch_slots: Int?

    init() {
        model = nil; version = nil; max_context = nil
        kv = nil; drafting = nil; batch_slots = nil
    }
}

struct RequestEntry: Decodable, Identifiable {
    let id: String
    let time: Double
    let duration_s: Double?
    let finish: String?
    let prompt_tokens: Int?
    let reused: Int?
    let output_tokens: Int?
    let first_engine_token_s: Double?
    let prompt_ms: Double?
    let decode_ms: Double?
    let decode_tok_s: Double?
    let hit_rate: Double?
    let drafts_offered: Int?
    let drafts_accepted: Int?
}

struct Totals: Decodable {
    let requests: Int?
    let prompt_tokens: Int?
    let reused: Int?
    let output_tokens: Int?
    let drafts_offered: Int?
    let drafts_accepted: Int?
}

/// 服务端保留的最近 60 个采样，速度行的 sparkline 用它（对齐 Strata web Monitor）。
/// 没有采样的点是 null，不是 0，画线时按 0 处理。
struct History: Decodable {
    let tok_s: [Double?]?
    let prefill_tok_s_mean: [Double?]?

    init() {
        tok_s = nil; prefill_tok_s_mean = nil
    }
}

struct MetricsSnapshot: Decodable {
    let live: LiveState
    let hardware: Hardware
    let engine: EngineInfo
    let totals: Totals?
    let history: History
    let requests: [RequestEntry]
    let time: Double

    enum CodingKeys: String, CodingKey {
        case live, hardware, engine, totals, history, requests, time
    }

    // 服务端偶发返回缺字段的中间态；这里对每段独立容错，requests 逐条解码，
    // 单条坏数据不影响整体渲染。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // live 是唯一不能容错的一段：容错成"空闲"就等于把"解析不了"伪装成"服务闲着"，
        // 实测服务端一有槽位在忙就换 live.slots 的字段形状，旧代码整段丢掉后，
        // 菜单栏正在生成时照样显示 idle。解析失败必须抛到上层，按第三节落到 ! 。
        self.live = try c.decode(LiveState.self, forKey: .live)
        self.hardware = (try? c.decode(Hardware.self, forKey: .hardware)) ?? Hardware()
        self.engine = (try? c.decode(EngineInfo.self, forKey: .engine)) ?? EngineInfo()
        self.totals = try? c.decode(Totals.self, forKey: .totals)
        self.history = (try? c.decode(History.self, forKey: .history)) ?? History()
        self.time = (try? c.decode(Double.self, forKey: .time)) ?? 0
        if let raw = try? c.decode([JSONValue].self, forKey: .requests) {
            var arr: [RequestEntry] = []
            arr.reserveCapacity(raw.count)
            for v in raw {
                if let data = try? JSONEncoder().encode(v),
                   let e = try? JSONDecoder().decode(RequestEntry.self, from: data) {
                    arr.append(e)
                }
            }
            self.requests = arr
        } else {
            self.requests = []
        }
    }
}

// 用于逐条解码 requests：先拿到通用 JSON，再逐条转成 RequestEntry
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown JSON value")
    }

    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

enum ServerState: Equatable {
    case busy
    case idle
}

/// 数字的来源口径。必须是枚举而不是文案：视图要按它把历史值标灰（见 PanelRootView），
/// 存字符串再比较的话，界面一换语言判定就全错。
enum MetricSource: Equatable {
    case now, thisRequest, lastRequest

    var label: String {
        switch self {
        case .now:         return L("当前")
        case .thisRequest: return L("本次请求")
        case .lastRequest: return L("最近请求")
        }
    }
}

/// 一个可展示的数值及其来源口径。来源必须与数字一起显示（对齐 Strata 的
/// "Decode now" / "Decode last request" 标注），否则空闲时的旧值会被当成当前值。
struct SpeedMetric: Equatable {
    let value: Double
    let source: MetricSource
}

struct Reading {
    let snapshot: MetricsSnapshot
    let serverState: ServerState
    let decodeTokS: Double?
    let lastRequest: RequestEntry?

    /// 与 Strata web Monitor 的 Speed 卡同一取数与标注逻辑，空闲时回退到最近请求。
    let decodeMetric: SpeedMetric?
    let prefillMetric: SpeedMetric?
}

enum HealthStatus: Equatable {
    case ok(model: String, maxContext: Int, keyRequired: Bool, loaded: Bool)
    case unreachable(String)
}

enum LinkState: Equatable {
    case never
    case ok
    case failed(String)
}

func buildReading(from snapshot: MetricsSnapshot) -> Reading {
    let live = snapshot.live
    let isIdle = live.state == "idle"
    let last = snapshot.requests.first

    // Strata: live.state === "generating" ? live.tok_s : last.decode_tok_s
    var decode: SpeedMetric? = nil
    if live.state == "generating", let v = live.tok_s, v > 0 {
        decode = SpeedMetric(value: v, source: .now)
    } else if let v = last?.decode_tok_s, v > 0 {
        decode = SpeedMetric(value: v, source: .lastRequest)
    }

    // Strata: 忙时取 live.prefill_tok_s_mean；空闲时用最近请求自己算，避免显示上一轮的数
    var prefill: SpeedMetric? = nil
    if !isIdle, let v = live.prefill_tok_s_mean, v > 0 {
        prefill = SpeedMetric(value: v, source: live.state == "reading" ? .now : .thisRequest)
    } else if isIdle,
              let p = last?.prompt_tokens, let ms = last?.prompt_ms, ms > 0 {
        let fresh = Double(max(0, p - (last?.reused ?? 0)))
        let v = fresh / (ms / 1000)
        if v > 0 { prefill = SpeedMetric(value: v, source: .lastRequest) }
    }

    // 菜单栏：空闲不显示速度，忙时优先当前瞬时值
    var tok: Double? = nil
    if !isIdle {
        if let v = live.tok_s, v > 0 { tok = v }
        if tok == nil, let v = last?.decode_tok_s, v > 0 { tok = v }
    }

    return Reading(
        snapshot: snapshot,
        serverState: isIdle ? .idle : .busy,
        decodeTokS: tok,
        lastRequest: last,
        decodeMetric: decode,
        prefillMetric: prefill
    )
}
