//
//  ContentView.swift
//  MyTuner
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tuner = TunerEngine()
    /// 已标记「调音完成」的弦（midi 集合，跨乐器全局唯一）
    @State private var doneStrings: Set<Int> = []

    private let tuneCents = 5.0   // |音分| ≤ 5 视为已调准
    private let gaugeRange = 50.0 // 表盘满偏：±50 音分

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                instrumentPicker
                stringPicker
                gauge
                noteDisplay
                doneButton
                Spacer(minLength: 0)
                startButton
            }
            .padding()
            .navigationTitle("调音器")
        }
        .tint(.orange)
    }

    // MARK: - 乐器切换
    private var instrumentPicker: some View {
        Picker("乐器", selection: $tuner.instrument) {
            ForEach(Instrument.allCases) { inst in
                Text(inst.rawValue).tag(inst)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 目标琴弦（点选）
    private var stringPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择要调的弦")
                .font(.subheadline)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tuner.instrument.strings) { s in
                        stringChip(s)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func stringChip(_ s: TuningString) -> some View {
        let isSelected = tuner.targetMidi == s.midi
        let isDone = doneStrings.contains(s.midi)
        return Button {
            tuner.targetMidi = s.midi
        } label: {
            VStack(spacing: 2) {
                Text(s.noteName + (isDone ? " ✓" : ""))
                    .font(.title3.weight(.semibold))
                Text("\(s.stringNumber)弦")
                    .font(.caption2)
                    .foregroundColor(isDone ? Color.green : .secondary)
            }
            .foregroundColor(isDone ? .green : .primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(isDone ? Color.green.opacity(0.35)
                               : isSelected ? Color.gray.opacity(0.3)
                               : Color.gray.opacity(0.15))
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.orange : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 指针表盘
    private var gauge: some View {
        TunerGauge(cents: gaugeCents, inTune: inTune, gaugeRange: gaugeRange)
            .frame(height: 170)
    }

    // MARK: - 音符显示
    private var noteDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(noteName)
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(octaveText)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(inTune ? .green : .secondary)
            }
            .foregroundColor(inTune ? .green : .primary)

            Text(statusText)
                .font(.headline)
                .foregroundColor(statusColor)

            Text(frequencyText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .frame(height: 150)
    }

    // MARK: - 调音完成按钮
    private var doneButton: some View {
        Button {
            guard let t = tuner.targetMidi else { return }
            if doneStrings.contains(t) { doneStrings.remove(t) } else { doneStrings.insert(t) }
        } label: {
            Text(doneButtonLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(doneButtonBackground)
                .foregroundColor(doneButtonForeground)
                .cornerRadius(14)
        }
        .disabled(doneButtonDisabled)
    }

    // MARK: - 开始 / 停止
    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                tuner.isRunning ? tuner.stop() : tuner.start()
            } label: {
                Image(systemName: tuner.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.orange))
            }
            Text("1. 选乐器 → 2. 选要调的弦 → 3. 点「开始」允许麦克风，拨该弦")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 派生数据（宽松检测：任何音高都显示，音分相对「最近音名」计算）
    private var nearestMidi: Int? {
        guard let f = tuner.frequency else { return nil }
        return Int(round(NoteUtil.midi(from: f)))
    }

    private var gaugeCents: Double? {
        guard let f = tuner.frequency else { return nil }
        let midi = NoteUtil.midi(from: f)
        return 1200 * (midi - midi.rounded())
    }

    private var inTune: Bool {
        guard let c = gaugeCents else { return false }
        return abs(c) <= tuneCents
    }

    private var noteName: String {
        guard tuner.isRunning, let m = nearestMidi else { return "——" }
        return NoteUtil.name(of: m)
    }

    private var octaveText: String {
        guard tuner.isRunning, let m = nearestMidi else { return "" }
        return String(NoteUtil.octave(of: m))
    }

    private var statusText: String {
        if !tuner.isRunning {
            return tuner.targetMidi != nil ? "点「开始」启动调音" : "请选择要调的弦"
        }
        guard tuner.targetMidi != nil else { return "请选择要调的弦" }
        guard let c = gaugeCents else { return "等待声音…（拨目标弦）" }
        if inTune { return "已调准 ✓" }
        return c > 0 ? "偏高 \(formatCents(c)) 音分" : "偏低 \(formatCents(c)) 音分"
    }

    private var statusColor: Color {
        guard tuner.isRunning, tuner.targetMidi != nil, gaugeCents != nil else { return .secondary }
        return inTune ? .green : .orange
    }

    private var frequencyText: String {
        guard let f = tuner.frequency else { return "" }
        var text = String(format: "%.1f Hz", f)
        if matched { text += " · \(tuningStringLabel(tuner.targetMidi!))" }
        return text
    }

    /// 检测到的音名正好等于选中的目标弦。
    private var matched: Bool {
        guard let t = tuner.targetMidi, let m = nearestMidi else { return false }
        return m == t
    }

    private func tuningStringLabel(_ midi: Int) -> String {
        if let s = tuner.instrument.strings.first(where: { $0.midi == midi }) {
            return "\(s.stringNumber)弦"
        }
        return ""
    }

    // MARK: - 调音完成按钮样式
    private var doneButtonLabel: String {
        guard let t = tuner.targetMidi else { return "标记调音完成" }
        if doneStrings.contains(t) { return "已调完 ✓（点击取消）" }
        return (matched && inTune) ? "标记调音完成" : "调准后点击标记"
    }

    private var doneButtonDisabled: Bool {
        guard let t = tuner.targetMidi else { return true }
        if doneStrings.contains(t) { return false }
        return !(matched && inTune)
    }

    private var doneButtonBackground: Color {
        guard let t = tuner.targetMidi else { return Color.gray.opacity(0.15) }
        if doneStrings.contains(t) { return Color.green.opacity(0.25) }
        return (matched && inTune) ? .green : Color.gray.opacity(0.15)
    }

    private var doneButtonForeground: Color {
        guard let t = tuner.targetMidi else { return .secondary }
        if doneStrings.contains(t) { return .green }
        return (matched && inTune) ? Color(.systemBackground) : .secondary
    }

    private func formatCents(_ c: Double) -> String {
        let v = Int(c.rounded())
        return v > 0 ? "+\(v)" : "\(v)"
    }
}

// MARK: - 表盘（Canvas 绘制：弧、绿色调准区、刻度、指针）
struct TunerGauge: View {
    let cents: Double?
    let inTune: Bool
    let gaugeRange: Double

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height * 0.96
            let r = min(size.width, size.height * 2) * 0.86

            func pt(_ c: Double, _ radius: Double) -> CGPoint {
                let deg = (c / gaugeRange) * 90 * .pi / 180
                return CGPoint(x: cx + radius * sin(deg), y: cy - radius * cos(deg))
            }

            // 背景弧
            var bg = Path()
            for i in 0...120 {
                let c = -gaugeRange + Double(i) / 120 * (gaugeRange * 2)
                let p = pt(c, r)
                i == 0 ? bg.move(to: p) : bg.addLine(to: p)
            }
            context.stroke(bg, with: .color(Color.gray.opacity(0.25)), lineWidth: 7)

            // 绿色调准区（±5 音分）
            var good = Path()
            for i in 0...20 {
                let c = -5 + Double(i) / 20 * 10
                let p = pt(c, r)
                i == 0 ? good.move(to: p) : good.addLine(to: p)
            }
            context.stroke(good, with: .color(.green), lineWidth: 7)

            // 刻度
            for c in stride(from: -gaugeRange, through: gaugeRange, by: 10) {
                let major = Int(c) % 20 == 0
                var t = Path()
                t.move(to: pt(c, r - 10))
                t.addLine(to: pt(c, r - (major ? 22 : 16)))
                context.stroke(t, with: .color(Color.gray.opacity(0.45)), lineWidth: major ? 2.5 : 1.5)
            }

            // 指针（静默时停在中间）
            let c = min(max(cents ?? 0, -gaugeRange), gaugeRange)
            var needle = Path()
            needle.move(to: pt(c, 6))
            needle.addLine(to: pt(c, r - 16))
            context.stroke(needle, with: .color(inTune ? .green : .primary), lineWidth: 4)

            // 圆心
            let pivot = Path(ellipseIn: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14))
            context.fill(pivot, with: .color(inTune ? .green : .primary))
        }
    }
}
