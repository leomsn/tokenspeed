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
}
