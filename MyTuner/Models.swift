//
//  Models.swift
//  MyTuner
//
//  调音器的数据模型：乐器、调弦、音高换算。
//

import Foundation

/// 一根弦的调音目标。
/// - `stringNumber`：弦号（1 = 最高音弦，越大越低音）；
/// - `midi`：目标音高的 MIDI 编号（A4 = 69），据此精确算出频率与音名。
struct TuningString: Identifiable, Hashable {
    let stringNumber: Int
    let midi: Int

    var id: Int { midi }
    var noteName: String { NoteUtil.name(of: midi) }
    var octave: Int { NoteUtil.octave(of: midi) }
    var frequency: Double { NoteUtil.frequency(of: midi) }
    var label: String { "\(stringNumber)弦 \(noteName)\(octave)" }
}

/// 乐器。每种乐器定义一组标准调弦（低音弦在前）。
enum Instrument: String, CaseIterable, Identifiable {
    case guitar = "吉他"
    case bass   = "贝斯"

    var id: String { rawValue }

    var strings: [TuningString] {
        switch self {
        case .guitar:
            return [
                TuningString(stringNumber: 6, midi: 40), // E2
                TuningString(stringNumber: 5, midi: 45), // A2
                TuningString(stringNumber: 4, midi: 50), // D3
                TuningString(stringNumber: 3, midi: 55), // G3
                TuningString(stringNumber: 2, midi: 59), // B3
                TuningString(stringNumber: 1, midi: 64), // E4
            ]
        case .bass:
            return [
                TuningString(stringNumber: 4, midi: 28), // E1
                TuningString(stringNumber: 3, midi: 33), // A1
                TuningString(stringNumber: 2, midi: 38), // D2
                TuningString(stringNumber: 1, midi: 43), // G2
            ]
        }
    }
}

/// 音高换算工具：频率 ↔ MIDI ↔ 音名/八度。
enum NoteUtil {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// MIDI → 频率（Hz）。A4 = 440Hz 对应 midi 69。
    static func frequency(of midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// 频率 → MIDI（浮点，可含小数用于计算音分）。
    static func midi(from frequency: Double) -> Double {
        69 + 12 * log2(frequency / 440)
    }

    /// MIDI → 音名（如 45 → "A"）。
    static func name(of midi: Int) -> String {
        names[((midi % 12) + 12) % 12]
    }

    /// MIDI → 八度（如 45 → 2，即 A2）。
    static func octave(of midi: Int) -> Int {
        midi / 12 - 1
    }
}
