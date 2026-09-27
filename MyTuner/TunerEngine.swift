//
//  TunerEngine.swift
//  MyTuner
//
//  调音器核心：用 AVAudioEngine 采集麦克风输入，用 YIN 时域自相关算法检测音高。
//
//  为什么用「时域自相关（YIN）」而不是 FFT？
//  - 调音器要测的是基频，尤其贝斯最低弦 E1 只有约 41 Hz；
//  - FFT 在低频的分辨率取决于窗口大小，要精确到「音分」级别需要超大 FFT，成本高；
//  - 时域自相关按「采样点」直接找周期，低频分辨率天然够用，还附带抛物线插值
//    把周期精确到亚采样级别，音分误差很小。
//
//  线程模型（与 MyTempo 节拍器一致）：
//  - 音频回调只做「拷贝采样」，把重活丢到串行队列 processingQueue；
//  - 主线程用一个 30Hz 的 Timer 只负责把最新检测结果刷到 UI。
//

import Foundation
import AVFoundation
import Combine

final class TunerEngine: ObservableObject {

    // MARK: - 可调参数（UI 直接绑定）
    @Published var instrument: Instrument = .guitar {
        didSet {
            if instrument != oldValue {
                targetMidi = nil   // 换乐器后需重新选弦
            }
        }
    }
    /// 当前选中要调的目标弦（midi 编号）；nil 表示尚未选弦。
    @Published var targetMidi: Int?

    // MARK: - 检测结果（只读，UI 观察）
    /// 平滑后的检测频率（Hz）；nil 表示当前无有效声音。
    @Published private(set) var frequency: Double?
    /// 是否正在采集。
    @Published private(set) var isRunning = false
    /// 麦克风授权状态 / 错误信息。
    @Published private(set) var micError: String?

    // MARK: - 音频
    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "tuner.processing")
    private let lock = NSLock()

    // 以下变量只在 processingQueue 访问（串行，无需额外加锁）
    private var smoothFrequency: Double?
    private var recent: [Double] = []

    // 处理结果与 UI 之间的桥：processingQueue 写入，主线程 Timer 读取
    private var latestFrequency: Double?
    private var lastDetection = Date.distantPast
    private var uiTimer: Timer?

    private let minFrequency = 30.0    // 低于此视为噪声（低于贝斯 E1）
    private let maxFrequency = 1000.0  // 高于此视为噪声

    // MARK: - 控制
    func start() {
        guard !isRunning else { return }
        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                granted ? self.configureAndStart() : (self.micError = "未授权麦克风")
            }
        }
        #else
        configureAndStart()
        #endif
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        frequency = nil
        smoothFrequency = nil
        recent.removeAll()
        uiTimer?.invalidate()
        uiTimer = nil
    }

    // MARK: - 采集
    private func configureAndStart() {
        #if os(iOS)
        // .measurement：关闭系统自动增益/降噪，尽量拿到「原汁原味」的波形，利于音高检测
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [])
        try? session.setActive(true)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let samples = self.copyMonoSamples(buffer)
            self.processingQueue.async {
                self.process(samples: samples, sampleRate: sampleRate)
            }
        }

        try? engine.start()
        isRunning = true
        startTimer()
    }

    /// 把输入缓冲拷贝成单声道 Float 数组（取第一个声道）。
    private func copyMonoSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let data = channelData[0]
        var samples = [Float](repeating: 0, count: frames)
        for i in 0..<frames { samples[i] = data[i] }
        return samples
    }

    private func process(samples: [Float], sampleRate: Double) {
        guard let raw = Self.detectPitch(samples, sampleRate: sampleRate),
              raw > minFrequency, raw < maxFrequency else {
            return
        }

        // 中值滤波：最近 3 次取中值，抑制偶发的八度跳变
        recent.append(raw)
        if recent.count > 3 { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]

        // 指数平滑
        smoothFrequency = (smoothFrequency.map { $0 * 0.6 + median * 0.4 }) ?? median

        lock.lock()
        latestFrequency = smoothFrequency
        lastDetection = Date()
        lock.unlock()
    }

    // MARK: - 视觉同步（主线程，30Hz）
    private func startTimer() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.displayTick()
        }
        RunLoop.main.add(t, forMode: .common)
        uiTimer = t
    }

    private func displayTick() {
        lock.lock()
        let f = latestFrequency
        let last = lastDetection
        lock.unlock()

        // 超过 0.6 秒没有有效检测 → 回到静默态
        if let f = f, Date().timeIntervalSince(last) < 0.6 {
            frequency = f
        } else {
            frequency = nil
        }
    }

    // MARK: - 音高检测（YIN）
    /// 输入一段单声道采样，返回检测到的基频（Hz）；无法判断则返回 nil。
    static func detectPitch(_ samples: [Float], sampleRate: Double) -> Double? {
        let n = samples.count
        let w = n / 2
        guard w >= 2 else { return nil }

        var sumSq = 0.0
        for v in samples { sumSq += Double(v) * Double(v) }
        let rms = sqrt(sumSq / Double(n))
        guard rms > 0.01 else { return nil }

        var d = [Double](repeating: 0, count: w + 1)
        for tau in 0...w {
            var s = 0.0
            for j in 0..<w {
                let diff = Double(samples[j]) - Double(samples[j + tau])
                s += diff * diff
            }
            d[tau] = s
        }

        var dNorm = [Double](repeating: 0, count: w + 1)
        dNorm[0] = 1
        var running = 0.0
        for tau in 1...w {
            running += d[tau]
            dNorm[tau] = running > 0 ? (d[tau] * Double(tau)) / running : 1
        }

        let threshold = 0.15
        var tau = 2
        while tau < w && dNorm[tau] >= threshold { tau += 1 }
        guard tau < w else { return nil }

        while tau + 1 <= w && dNorm[tau + 1] < dNorm[tau] { tau += 1 }
        if tau > 1 && tau < w {
            let s0 = dNorm[tau - 1], s1 = dNorm[tau], s2 = dNorm[tau + 1]
            let denom = s0 - 2 * s1 + s2
            if denom != 0 {
                let delta = (s0 - s2) / (2 * denom)
                if delta > -1 && delta < 1 {
                    return sampleRate / (Double(tau) + delta)
                }
            }
        }
        return sampleRate / Double(tau)
    }

    deinit {
        stop()
    }
}
