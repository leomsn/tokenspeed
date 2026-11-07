import SwiftUI

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let n = nextValue()
        if n.width > 0 && n.height > 0 { value = n }
    }
}

struct PanelRootView: View {
    @ObservedObject var vm: PanelViewModel
    @ObservedObject private var lang = LanguageCenter.shared
    let onPin: () -> Void
    let onClose: () -> Void
    let idealWidth: CGFloat
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .padding(.top, 10)
        }
        .frame(width: idealWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PanelSizeKey.self, value: geo.size)
        })
        .onPreferenceChange(PanelSizeKey.self, perform: onSizeChange)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.pinned ? "line.3.horizontal" : "circle")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(vm.pinned ? .primary.opacity(0.7) : .secondary.opacity(0.6))
                .frame(width: 12)
            Text("TokenSpeed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
            Button(action: onPin) {
                Image(systemName: vm.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(vm.pinned ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(vm.pinned ? L("取消驻留") : L("驻留浮窗（驻留后可拖动）"))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("关闭"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(PanelDragHandle(enabled: vm.pinned))
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBanner
            // 横幅之外整块挂一个"这一屏显示的全部值"的指纹：服务端一个字段都没变时
            // （空闲时几乎每轮都这样）连 ForEach 都不重建，只有横幅跟着取数时间重画。
            PanelContentView(vm: vm).equatable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusBanner: some View {
        let tone = StateTone(link: vm.link, busy: vm.reading?.serverState == .busy)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle().fill(tone.color).frame(width: 7, height: 7)
                Text(tone.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.88))
                Spacer()
                if let t = vm.lastUpdated, vm.link != .never {
                    Text(Self.timeFmt.string(from: t))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if case .failed(let msg) = vm.link {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tone.color.opacity(0.22), lineWidth: 0.5)
        )
    }

    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

}

/// 横幅以下的全部行。整块挂一个指纹（EquatableView）：服务端这些字段几乎每轮都不变，
/// 指纹没变就连 ForEach 都不重建，整棵子树不参与重排——上一轮只做行级门不够，
/// 根视图观察 vm 就使每轮都付一次全树 sizeThatFits（sample 里 LayoutEngineBox 占大头）。
/// 代价是指纹必须覆盖每一行显示的值：漏一个字段，那一行就再也不刷新。
struct PanelContentView: View, Equatable {
    let vm: PanelViewModel
    let stamp: Int
    @ObservedObject private var lang = LanguageCenter.shared   // 切语言要重算指纹，见 baseStamp

    init(vm: PanelViewModel) {
        self.vm = vm
        self.stamp = PanelContentView.contentStamp(vm: vm, lang: LanguageCenter.shared.current)
    }

    // == 只比 stamp 是有意的——vm 是引用，永远"相等"，比它等于没比。
    static func == (lhs: PanelContentView, rhs: PanelContentView) -> Bool { lhs.stamp == rhs.stamp }

    var body: some View {
        rowsView(base: Self.baseStamp(lang: lang.current, fields: vm.enabledFields))
    }

    private func rowsView(base: Hasher) -> some View {
        let r = vm.reading
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.self) { row in
                switch row {
                case .speed:
                    SpeedCard(vm: vm, stamp: Self.speedStamp(r, base: base)).equatable()
                case .field(let field):
                    PanelFieldRow(field: field, vm: vm,
                                  stamp: Self.fieldStamp(field, r, base: base)).equatable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 每行显示哪些值，只有这里知道：整块门和行级门都从这几个函数算，
    // 两处各写一遍迟早会漏字段。指纹里必须带界面语言和栏位开关：
    // 切语言、改栏位时服务端一个字段都没变，不带进去就留着旧文案、或按旧栏位排版。
    static func baseStamp(lang: UILanguage, fields: Set<PanelField>) -> Hasher {
        var h = Hasher()
        h.combine(lang)
        h.combine(fields)
        return h
    }

    static func speedStamp(_ r: Reading?, base: Hasher) -> Int {
        var h = base
        // SpeedMetric 本身没 conform Hashable，按它显示出来的两项算就够了
        h.combine(r?.decodeMetric?.value); h.combine(r?.decodeMetric?.source.label)
        h.combine(r?.prefillMetric?.value); h.combine(r?.prefillMetric?.source.label)
        h.combine(r?.snapshot.history.tok_s)
        h.combine(r?.snapshot.history.prefill_tok_s_mean)
        return h.finalize()
    }

    static func fieldStamp(_ field: PanelField, _ r: Reading?, base: Hasher) -> Int {
        var h = base
        switch field {
        case .modelVersion:
            if let e = r?.snapshot.engine {
                h.combine(e.model); h.combine(e.version); h.combine(e.maya_version); h.combine(e.max_context)
            }
        case .liveState:
            let l = r?.snapshot.live
            h.combine(l?.state); h.combine(l?.prompt_read); h.combine(l?.prompt_total)
            h.combine(l?.generated); h.combine(l?.max_tokens); h.combine(l?.tok_s)
            h.combine(r?.lastRequest?.id)
            h.combine(r?.lastRequest?.output_tokens)
            h.combine(r?.lastRequest?.decode_tok_s)
        case .decodeSpeed, .prefillSpeed:
            h.combine(speedStamp(r, base: base))   // 渲染在 SpeedCard 里，这里只为占位
        case .queueDepth:
            let l = r?.snapshot.live
            h.combine(l?.running); h.combine(l?.active); h.combine(l?.queued); h.combine(l?.waiting); h.combine(l?.parallel)
        case .slots:
            for s in r?.snapshot.live.slots ?? [] {
                h.combine(s.slot); h.combine(s.state); h.combine(s.held_tokens)
                h.combine(s.prompt_read); h.combine(s.prompt_tokens)
                h.combine(s.generated); h.combine(s.tok_s)
            }
        case .lastRequest:
            let q = r?.lastRequest
            h.combine(q?.id); h.combine(q?.decode_tok_s); h.combine(q?.prompt_tokens); h.combine(q?.hit_rate)
        case .gpuUtil:
            for g in r?.snapshot.hardware.gpus ?? [] { h.combine(g.index); h.combine(g.util) }
        case .gpuTemp:  h.combine(r?.snapshot.hardware.gpu_temp)
        case .gpuPower: h.combine(r?.snapshot.hardware.gpu_power)
        case .vram:
            h.combine(r?.snapshot.hardware.gpu_mem_used)
            h.combine(r?.snapshot.hardware.gpu_mem_total)
        case .cpu: h.combine(r?.snapshot.hardware.cpu)
        case .ram:
            h.combine(r?.snapshot.hardware.ram_used)
            h.combine(r?.snapshot.hardware.ram_total)
        case .totals:
            let t = r?.snapshot.totals
            h.combine(t?.requests); h.combine(t?.output_tokens)
            h.combine(t?.drafts_accepted); h.combine(t?.drafts_offered)
        }
        return h.finalize()
    }

    static func contentStamp(vm: PanelViewModel, lang: UILanguage) -> Int {
        let base = baseStamp(lang: lang, fields: vm.enabledFields)
        var h = base
        let r = vm.reading
        h.combine(speedStamp(r, base: base))
        for f in PanelField.allCases where vm.enabledFields.contains(f) {
            h.combine(fieldStamp(f, r, base: base))
        }
        return h.finalize()
    }

    // 解码/预填充合并成一张速度卡（官方 Speed 卡的样子），渲染在它俩中靠前的位置
    private enum Row: Hashable {
        case field(PanelField)
        case speed
    }

    private var rows: [Row] {
        var out: [Row] = []
        var speedPlaced = false
        for f in PanelField.allCases where vm.enabledFields.contains(f) {
            if f == .decodeSpeed || f == .prefillSpeed {
                if !speedPlaced { out.append(.speed); speedPlaced = true }
            } else {
                out.append(.field(f))
            }
        }
        return out
    }
}

/// 服务端对空闲槽位和忙槽位给的是两套字段（见 LiveSlot 注释），所以这里按 state 选列；
/// 读不到就显示破折号，不猜 0——把缺字段显示成 0 tok 就是凭空造数。
func slotValue(_ s: LiveSlot) -> String {
    switch s.state {
    case "idle":    return "\(Num.grouped(s.held_tokens ?? 0)) tok"
    case "reading": return "\(Num.grouped(s.prompt_read ?? 0))/\(Num.grouped(s.prompt_tokens ?? 0))"
    default:        return s.tok_s.map { "\(Num.grouped($0)) t/s" } ?? "—"
    }
}

private struct StateTone {
    let color: Color
    let label: String
    init(link: LinkState, busy: Bool) {
        switch link {
        case .never:
            color = .secondary; label = L("等待首次取数…")
        case .ok:
            color = busy ? .green : .secondary
            label = busy ? L("服务忙") : L("服务空闲")
        case .failed:
            color = .red; label = L("取数失败")
        }
    }
}

// MARK: - Speed card（对齐 Strata web Monitor 的 Speed 卡）

enum Num {
    /// 全站数字一律逗号千分位，小数位由调用方定。区域固定 en_US_POSIX 并显式写死分隔符：
    /// 跟系统区域走的话，德语机器会把 1,234 显示成 1.234，跟界面语言走又会出现三种分隔符。
    private static let fmt: NumberFormatter = {
        let x = NumberFormatter()
        x.numberStyle = .decimal
        x.locale = Locale(identifier: "en_US_POSIX")
        x.usesGroupingSeparator = true
        x.groupingSeparator = ","
        return x
    }()

    private static func str(_ v: Double, _ digits: Int) -> String {
        fmt.minimumFractionDigits = digits
        fmt.maximumFractionDigits = digits
        return fmt.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v)
    }

    static func grouped(_ v: Int) -> String { str(Double(v), 0) }
    static func grouped(_ v: Double, _ digits: Int = 1) -> String { str(v, digits) }
}

// MARK: - Sparkline（对齐 Strata web Monitor 的 st-metric__spark）

/// 最近采样的形状。归一化与 Strata 的 spark() 一致：顶格取序列最大值（至少 1），
/// 线在 32 高的坐标系里占 4…30，面积填到底。null 采样按 0 画。
struct Sparkline: View {
    let values: [Double?]
    var color: Color = .green
    var height: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let v = values.map { $0 ?? 0 }
            let top = max(1.0, v.max() ?? 1.0)
            let pts = v.indices.map { i in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(v.count - 1),
                        y: geo.size.height * (30 - CGFloat(v[i] / top) * 26) / 32)
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for pt in pts { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.12))
                Path { $0.addLines(pts) }
                    .stroke(color,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}

struct SpeedCard: View, Equatable {
    // vm 不再是 @ObservedObject：观察只留在 PanelRootView 一处，行能不能更新由 stamp 决定。
    // == 只比 stamp 是有意的——vm 是引用，永远"相等"，比它等于没比。
    let vm: PanelViewModel
    let stamp: Int
    @ObservedObject private var lang = LanguageCenter.shared

    static func == (lhs: SpeedCard, rhs: SpeedCard) -> Bool { lhs.stamp == rhs.stamp }

    var body: some View {
        let r = vm.reading
        let showDecode = vm.enabledFields.contains(.decodeSpeed)
        let showPrefill = vm.enabledFields.contains(.prefillSpeed)
        if r != nil, showDecode || showPrefill {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(L("速度"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    if showDecode {
                        column(r?.decodeMetric, name: L("解码"), trailing: false,
                               series: r?.snapshot.history.tok_s ?? [],
                               spark: Color.green.opacity(0.9))
                    }
                    if showPrefill {
                        column(r?.prefillMetric, name: L("预填充"), trailing: true,
                               series: r?.snapshot.history.prefill_tok_s_mean ?? [],
                               spark: Color.green.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
        }
    }

    private func column(_ m: SpeedMetric?, name: String, trailing: Bool,
                        series: [Double?], spark: Color) -> some View {
        let caption = m.map { "\(name) · \($0.source.label)" } ?? name
        // 只有"最近请求"是历史值，标灰；当前/本次请求才是活的
        let stale = m?.source == .lastRequest
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(m.map { Num.grouped($0.value) } ?? "—")
                    .font(.system(size: 27, weight: .heavy))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("t/s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(stale ? Color.secondary : Color.green.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if series.count >= 2 {
                Sparkline(values: series, color: spark)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

// MARK: - State row

/// 官方状态卡的样子：一行 label + detail，下面一条会随轮询生长的进度条
/// （reading 走 prompt_read/prompt_total，generating 走 generated/max_tokens）。
struct StateRow: View {
    @ObservedObject private var lang = LanguageCenter.shared
    let live: LiveState
    let last: RequestEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L("状态"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.9))
                if let d = detail {
                    Text(d)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(value: pct, color: barColor)
                .animation(.easeOut(duration: 0.16), value: pct)
        }
    }

    private var label: String {
        switch live.state {
        case "idle": return L("空闲")
        case "reading": return L("读取提示词")
        case "generating": return L("生成中")
        case "admitting": return L("排队准入")
        case "unloaded": return L("模型未加载")
        default: return live.state
        }
    }

    private var pct: Double {
        switch live.state {
        case "reading":
            guard let t = live.prompt_total, t > 0, let r = live.prompt_read else { return 0 }
            return min(100, 100 * Double(r) / Double(t))
        case "generating":
            guard let m = live.max_tokens, m > 0, let g = live.generated else { return 0 }
            return min(100, 100 * Double(g) / Double(m))
        default:
            return 0
        }
    }

    // 官方把 reading 的进度条切成 info 蓝，其余忙态用主色
    private var barColor: Color {
        live.state == "reading" ? Color(red: 0.23, green: 0.66, blue: 1.0) : Color.green
    }

    private var detail: String? {
        switch live.state {
        case "reading":
            if let t = live.prompt_total, t > 0 {
                let r = live.prompt_read ?? 0
                return "\(Num.grouped(r)) / \(Num.grouped(t)) tok · \(Int(pct))%"
            }
            return live.prompt_tokens.map { "\(Num.grouped($0)) tok" }
        case "generating":
            var parts: [String] = []
            if let g = live.generated {
                parts.append(live.max_tokens.map { "\(Num.grouped(g)) / \(Num.grouped($0)) tok" }
                                           ?? "\(Num.grouped(g)) tok")
            }
            if let t = live.tok_s, t > 0 { parts.append("\(Num.grouped(t)) t/s") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case "unloaded", "admitting":
            return nil
        default:   // 空闲：官方在这里显示上一次请求的结果，这一行不至于空着
            guard let last = last, let o = last.output_tokens, o > 0 else { return nil }
            var s = LF("上次 %1$@ tok", Num.grouped(o))
            if let d = last.decode_tok_s, d > 0 { s += " · \(Num.grouped(d)) t/s" }
            return s
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .menu
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 面板 header 的透明拖拽层：仅驻留时激活，mouseDown 时让窗口跟着鼠标移动。
struct PanelDragHandle: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.enabled = enabled
    }
    final class DragView: NSView {
        var enabled: Bool = false {
            didSet { window?.invalidateCursorRects(for: self) }
        }
        override func resetCursorRects() {
            guard enabled else { return }
            addCursorRect(bounds, cursor: .openHand)
        }
        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            window?.performDrag(with: event)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

struct KVLine: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var singleLine: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(valueColor.opacity(0.9))
                .textSelection(.enabled)
                .lineLimit(singleLine ? 1 : nil)
                .minimumScaleFactor(singleLine ? 0.8 : 1)
            Spacer(minLength: 0)
        }
    }
}

struct MonoNumber: View {
    let text: String
    var color: Color = .primary
    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced).weight(.medium))
            .foregroundColor(color.opacity(0.9))
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = .accentColor
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, value / 100)) * geo.size.width)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Field rows

struct PanelFieldRow: View, Equatable {
    let field: PanelField
    let vm: PanelViewModel
    let stamp: Int
    @ObservedObject private var lang = LanguageCenter.shared

    static func == (lhs: PanelFieldRow, rhs: PanelFieldRow) -> Bool {
        lhs.field == rhs.field && lhs.stamp == rhs.stamp
    }

    var body: some View {
        switch field {
        case .modelVersion:
            if let e = vm.reading?.snapshot.engine {
                // Maya 的版本在 maya_version（version 为 null）；Strata 用 version
                let eng = e.maya_version.map { "Maya \($0)" } ?? (e.version ?? "?")
                KVLine(label: L("模型"),
                       value: LF("%1$@  ·  引擎 %2$@  ·  ctx %3$@",
                                 e.model ?? "?", eng, Num.grouped(e.max_context ?? 0)))
            }
        case .liveState:
            if let r = vm.reading {
                StateRow(live: r.snapshot.live, last: r.lastRequest)
            }
        case .decodeSpeed, .prefillSpeed:
            EmptyView()   // 渲染在 SpeedCard 里
        case .queueDepth:
            if let l = vm.reading?.snapshot.live {
                let run = l.running ?? l.active ?? 0
                // Maya 不报 parallel（并行容量），那一段不能画成 0，整段省掉
                let value = l.parallel.map {
                    LF("%1$d 运行 · %2$d 排队 · %3$d 等待 / %4$d",
                       run, l.queued ?? 0, l.waiting ?? 0, $0)
                } ?? LF("%1$d 运行 · %2$d 排队 · %3$d 等待",
                        run, l.queued ?? 0, l.waiting ?? 0)
                KVLine(label: L("队列"), value: value, singleLine: true)
            }
        case .slots:
            if let slots = vm.reading?.snapshot.live.slots, !slots.isEmpty {
                SectionCard(title: "Slots") {
                    ForEach(slots, id: \.slot) { s in
                        HStack(spacing: 8) {
                            Text("slot \(s.slot)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Circle()
                                .fill(s.state == "idle" ? Color.secondary : Color.green)
                                .frame(width: 5, height: 5)
                            Text(s.state).font(.system(size: 10))
                            Spacer()
                            Text(slotValue(s))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        case .lastRequest:
            if let r = vm.reading?.lastRequest {
                SectionCard(title: L("最近请求")) {
                    HStack(spacing: 10) {
                        miniStat("dec", "\(Num.grouped(r.decode_tok_s ?? 0)) t/s", color: .green)
                        miniStat("prompt", Num.grouped(r.prompt_tokens ?? 0))
                        miniStat("reuse", String(format: "%.0f%%", (r.hit_rate ?? 0) * 100))
                    }
                }
            }
        case .gpuUtil:
            if let gpus = vm.reading?.snapshot.hardware.gpus, !gpus.isEmpty {
                SectionCard(title: L("GPU 利用率")) {
                    ForEach(gpus) { g in
                        HStack(spacing: 8) {
                            Text("GPU\(g.index)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            // 只让条长插值；右边的百分数保持每个采样原值，不跟着动画（3.4）
                            ProgressBar(value: g.util ?? 0)
                                .animation(.easeOut(duration: 0.4), value: g.util ?? 0)
                            Text(String(format: "%.0f%%", g.util ?? 0))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        case .gpuTemp:
            if let h = vm.reading?.snapshot.hardware {
                KVLine(label: L("温度"), value: String(format: "%.0f °C", h.gpu_temp ?? 0))
            }
        case .gpuPower:
            if let h = vm.reading?.snapshot.hardware {
                KVLine(label: L("功率"), value: "\(Num.grouped(h.gpu_power ?? 0, 0)) W")
            }
        case .vram:
            if let h = vm.reading?.snapshot.hardware, let used = h.gpu_mem_used, let total = h.gpu_mem_total {
                KVLine(label: L("显存"), value: "\(Num.grouped(used / 1e9)) / \(Num.grouped(total / 1e9)) GiB")
            }
        case .cpu:
            if let h = vm.reading?.snapshot.hardware, let c = h.cpu {
                KVLine(label: "CPU", value: String(format: "%.0f %%", c))
            }
        case .ram:
            if let h = vm.reading?.snapshot.hardware, let used = h.ram_used, let total = h.ram_total {
                KVLine(label: L("内存"), value: "\(Num.grouped(used / 1e9)) / \(Num.grouped(total / 1e9)) GiB")
            }
        case .totals:
            if let t = vm.reading?.snapshot.totals {
                let offered = t.drafts_offered ?? 0
                let accepted = t.drafts_accepted ?? 0
                // 光给"接受数/提议数"看不出好坏，接受率放前面，原数留在括号里当出处。
                // 分母为 0（服务刚起、或引擎没开投机解码）不能算百分比，画成 —。
                let draft = offered > 0
                    ? "draft \(String(format: "%.1f%%", Double(accepted) / Double(offered) * 100)) (\(Num.grouped(accepted))/\(Num.grouped(offered)))"
                    : "draft — (\(Num.grouped(accepted))/\(Num.grouped(offered)))"
                KVLine(label: L("累计"),
                       value: "req \(Num.grouped(t.requests ?? 0)) · out \(Num.grouped(t.output_tokens ?? 0))")
                // 括号里那对原数塞在同一行会被折到下一行、正好把数字劈开，所以单独一行。
                KVLine(label: "", value: draft)
            }
        }
    }

    private func miniStat(_ k: String, _ v: String, color: Color = .primary) -> some View {
        HStack(spacing: 3) {
            Text(k).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(color.opacity(0.9))
        }
    }
}
