import XCTest
@testable import TokenSpeed

/// 钉住取数的两条硬规则：三态判定（空闲绝不显示 `hardware.tok_s` 的旧值）
/// 和「`live` 段不许容错」。这两条都是实测踩过血的，改取数代码时必须继续成立。
final class SnapshotTests: XCTestCase {

    private func snapshot(_ json: String) -> MetricsSnapshot {
        try! JSONDecoder().decode(MetricsSnapshot.self, from: Data(json.utf8))
    }

    /// 空闲但 `hardware.tok_s` 还挂着上一轮的旧值：菜单栏必须是空闲，不能显示那个旧值。
    func testIdleNeverShowsStaleHardwareSpeed() {
        let s = snapshot("""
        {"live":{"state":"idle","running":0,"queued":0,"slots":[{"slot":0,"state":"idle","held_tokens":134889}]},
         "hardware":{"tok_s":199.4},
         "requests":[{"id":"a","time":1,"decode_tok_s":210.0,"prompt_tokens":1000,"prompt_ms":2000,"reused":0}]}
        """)
        let r = buildReading(from: s)
        XCTAssertEqual(r.serverState, .idle)
        XCTAssertNil(r.decodeTokS, "空闲时把 hardware.tok_s 的旧值当成当前速度，比显示 0 更坏")
    }

    /// 空闲时浮窗可以显示速度，但必须带来源标注（3.4：没有来源的数字不许显示成事实）。
    func testIdleSpeedIsLabelledAsLastRequest() {
        let s = snapshot("""
        {"live":{"state":"idle"},
         "requests":[{"id":"a","time":1,"decode_tok_s":210.0,"prompt_tokens":1000,"prompt_ms":2000,"reused":0}]}
        """)
        let r = buildReading(from: s)
        XCTAssertEqual(r.decodeMetric?.value, 210.0)
        XCTAssertEqual(r.decodeMetric?.source, .lastRequest)
    }

    /// 忙时优先 `live.tok_s` 的瞬时值，来源标「当前」。
    func testBusyPrefersInstantValue() {
        let s = snapshot("""
        {"live":{"state":"generating","tok_s":123.4},
         "requests":[{"id":"a","time":1,"decode_tok_s":210.0}]}
        """)
        let r = buildReading(from: s)
        XCTAssertEqual(r.serverState, .busy)
        XCTAssertEqual(r.decodeTokS, 123.4)
        XCTAssertEqual(r.decodeMetric?.source, .now)
    }

    /// 解析失败必须抛到上层（→ 菜单栏 `!`），不许被兜底成"服务空闲"。
    func testMissingLiveSegmentThrows() {
        let data = Data(#"{"hardware":{"tok_s":199.4}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MetricsSnapshot.self, from: data))
    }

    /// 实测服务端一有槽位在忙就换 `live.slots` 的字段形状，那种"客户端看不懂"同样要抛。
    func testUnparseableLiveSegmentThrows() {
        let data = Data(#"{"live":{"state":"generating","slots":{"0":"decoding"}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MetricsSnapshot.self, from: data))
    }

    /// 反过来：除 `live` 之外的段缺字段要照常出图，别把一次抖动变成整屏 `!`。
    func testOtherSegmentsTolerateMissingFields() throws {
        let data = Data(#"{"live":{"state":"idle"}}"#.utf8)
        let s = try JSONDecoder().decode(MetricsSnapshot.self, from: data)
        XCTAssertEqual(s.live.state, "idle")
        XCTAssertNil(s.hardware.tok_s)
        XCTAssertNil(s.engine.version)
        XCTAssertEqual(s.requests.count, 0)
        XCTAssertEqual(s.time, 0)
    }

    /// 同一个槽位两种形状（3.2）：空闲带 held_tokens，忙带 prompt_tokens，同一段里混着也要能解。
    func testBothSlotShapesDecode() throws {
        let s = snapshot("""
        {"live":{"state":"generating","slots":[
          {"slot":0,"state":"idle","held_tokens":134889},
          {"slot":1,"state":"decoding","prompt_tokens":900,"prompt_read":900,"generated":12,"elapsed_s":0.4,"tok_s":180.0}]}}
        """)
        let slots = try XCTUnwrap(s.live.slots)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].held_tokens, 134889)
        XCTAssertNil(slots[1].held_tokens, "忙时服务端不返回 held_tokens，缺字段不算解析失败")
        XCTAssertEqual(slots[1].tok_s, 180.0)
    }

    // MARK: - Maya 变体（2026-11-07 实测 1.1.56，字段值取自真实 /metrics）

    /// 识别必须正向：engine.maya_version 是 Maya 自己报上的名字，有它才算 Maya。
    func testMayaDetectedByExplicitMarker() {
        let withMarker = snapshot("""
        {"live":{"state":"generating","tok_s":53.6},"engine":{"model":"PowerAI","version":null,"maya_version":"1.1.56"}}
        """)
        XCTAssertEqual(withMarker.flavor, .maya)
        let withoutMarker = snapshot("""
        {"live":{"state":"idle"},"engine":{"version":"0.1.56"}}
        """)
        XCTAssertEqual(withoutMarker.flavor, .strata, "没有 maya_version 一律按 Strata，旧服务端零行为变化")
    }

    /// Maya 的 requests[] 不带 id、gpus[] 不带 name——这两处曾是必填，
    /// 缺了会把 requests 整条丢弃、hardware 整段静默丢掉（GPU/CPU/内存卡全消失）。
    func testMayaBusySnapshotDecodes() throws {
        let s = snapshot("""
        {"live":{"state":"generating","queued":0,"active":1,"writing":1,
                 "prompt_tokens":61717,"generated":7645,"max_tokens":64000,
                 "elapsed_s":220.3,"tok_s":53.6,"tok_s_mean":35.5,
                 "prefill_tok_s_mean":508.5,"tok_s_window_s":5.0,"prompt_reused":59140},
         "hardware":{"tok_s":53.69,"cpu":51.7,"ram_used":89041747968,"ram_total":130460315648,
                     "gpu_util":86.0,"gpu_temp":58,"gpu_power":396.0,
                     "gpus":[{"index":0,"util":96,"mem_used":33629863936,"mem_total":34190917632,"temp":51,"power":192.167},
                              {"index":1,"util":91,"mem_used":33464189184,"mem_total":34190917632,"temp":55,"power":203.85}]},
         "engine":{"model":"PowerAI","version":null,"maya_version":"1.1.56","max_context":262144,"kv":"int8"},
         "history":{"tok_s":[40.2,53.6],"prefill_tok_s_mean":[508.5,508.5]},
         "totals":{"requests":9,"prompt_tokens":91000,"reused":59140,"output_tokens":3000},
         "requests":[{"time":1794050873.0,"duration_s":56.3,"finish":"stop","prefill_tok_s":1672.9,
                      "prompt_tokens":59141,"reused":0,"output_tokens":516,"prompt_ms":35353.4,
                      "decode_ms":20919.7,"decode_tok_s":24.7,"hit_rate":0.775}],
         "time":1794051376.28}
        """)
        XCTAssertEqual(s.flavor, .maya)
        let r = buildReading(from: s)
        XCTAssertEqual(r.serverState, .busy)
        XCTAssertEqual(r.decodeTokS, 53.6)
        XCTAssertEqual(r.decodeMetric?.source, .now)
        XCTAssertEqual(s.hardware.gpus?.count, 2, "gpus[] 缺 name 不能丢掉整段 hardware")
        XCTAssertEqual(s.requests.count, 1, "requests[] 缺 id 不能丢条目")
        XCTAssertNil(s.requests.first?.id)
        XCTAssertNil(s.live.running)
        XCTAssertEqual(s.live.active, 1, "Maya 用 active 报运行数，队列行要用它兜底")
    }

    /// Maya 空闲态（实测）：live.state == "idle"、live 速度字段全 null、slots 键整个不出现、
    /// hardware.tok_s 归零；空闲预填充优先用 Maya 直给的 prefill_tok_s，不再从 prompt_ms 反推。
    func testMayaIdleNeverShowsStaleHardwareSpeed() {
        let s = snapshot("""
        {"live":{"state":"idle","queued":0,"active":0},
         "hardware":{"tok_s":0.0},
         "engine":{"maya_version":"1.1.56"},
         "requests":[{"time":1,"decode_tok_s":24.7,"prefill_tok_s":1672.9,
                      "prompt_tokens":59141,"reused":0,"output_tokens":516,
                      "prompt_ms":35353.4,"decode_ms":20919.7}]}
        """)
        XCTAssertEqual(s.flavor, .maya)
        let r = buildReading(from: s)
        XCTAssertEqual(r.serverState, .idle)
        XCTAssertNil(r.decodeTokS)
        XCTAssertEqual(r.prefillMetric?.value, 1672.9)
        XCTAssertEqual(r.prefillMetric?.source, .lastRequest)
    }
}
