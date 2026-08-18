import AVFoundation
import Foundation

@MainActor
final class TimerSoundPlayer {
    // Behaviour: clicks are rendered into long PCM tracks on exact
    // quarter-second frame boundaries, avoiding timer callbacks and short loops.
    nonisolated static let sampleRate = 48_000
    nonisolated static let clicksPerSecond = 4
    nonisolated static let clickFrameCount = sampleRate / clicksPerSecond
    nonisolated static let clickTrackChunkDuration: TimeInterval = 16

    private static let schedulingLeadMilliseconds = 100
    private static var schedulingLeadTime: TimeInterval {
        TimeInterval(schedulingLeadMilliseconds) / 1_000
    }

    private let clock = ContinuousClock()
    private let countdownToneData: Data
    private let transitionToneData: Data
    private var scheduledClickPlayers: [AVAudioPlayer] = []
    private var scheduledCuePlayers: [AVAudioPlayer] = []
    private var scheduledIntervalDurations: [TimeInterval] = []
    private var scheduleStartedAt: ContinuousClock.Instant?
    private var sessionActive = false
    private var shouldResumeAfterInterruption = false
    private var interruptionTask: Task<Void, Never>?

    init() {
        countdownToneData = Self.toneData(frequency: 880, duration: 0.11, amplitude: 0.16)
        transitionToneData = Self.toneData(frequency: 1_260, duration: 0.18, amplitude: 0.2)

        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            ) {
                guard let self else { return }
                self.handleInterruption(notification)
            }
        }
    }

    deinit {
        interruptionTask?.cancel()
    }

    // Returns the monotonic instant at which both the timer and its audio should
    // begin, keeping the UI deadline aligned with the audio device timeline.
    func startSession(intervalDurations: [TimeInterval]) -> ContinuousClock.Instant? {
        let durations = intervalDurations.filter { $0 > 0 && $0.isFinite }
        guard !durations.isEmpty else { return nil }

        stopScheduledPlayers()
        guard activateSession() else {
            assertionFailure("Failed to start timer audio")
            return nil
        }

        let wholeDuration = durations.reduce(0, +)
        guard let preparedClickPlayers = Self.makeClickPlayers(duration: wholeDuration) else {
            assertionFailure("Failed to create timer click audio")
            stopSession()
            return nil
        }
        let cues = TimerAudioTimeline.cues(intervalDurations: durations)
        let preparedCues = cues.compactMap { cue -> (TimerAudioCue, AVAudioPlayer)? in
            let data = cue.kind == .countdown ? countdownToneData : transitionToneData
            guard let player = Self.makePlayer(data: data) else { return nil }
            player.prepareToPlay()
            return (cue, player)
        }
        guard preparedCues.count == cues.count else {
            assertionFailure("Failed to create timer cue audio")
            stopSession()
            return nil
        }

        let monotonicStartTime = clock.now.advanced(by: .milliseconds(Self.schedulingLeadMilliseconds))
        let deviceStartTime = preparedClickPlayers[0].player.deviceCurrentTime + Self.schedulingLeadTime
        scheduledClickPlayers = preparedClickPlayers.map(\.player)
        scheduledCuePlayers = preparedCues.map(\.1)
        for (cue, player) in preparedCues {
            guard player.play(atTime: deviceStartTime + cue.offset) else {
                assertionFailure("Failed to schedule timer cue audio")
                stopSession()
                return nil
            }
        }
        for clickPlayer in preparedClickPlayers {
            guard clickPlayer.player.play(atTime: deviceStartTime + clickPlayer.offset) else {
                assertionFailure("Failed to schedule timer click audio")
                stopSession()
                return nil
            }
        }

        scheduledIntervalDurations = durations
        scheduleStartedAt = monotonicStartTime
        return monotonicStartTime
    }

    func stopSession() {
        shouldResumeAfterInterruption = false
        stopScheduledPlayers()
        scheduledIntervalDurations = []
        scheduleStartedAt = nil
        guard sessionActive else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            assertionFailure("Failed to deactivate timer audio session: \(error)")
        }
        sessionActive = false
    }

    private func activateSession() -> Bool {
        if sessionActive { return true }

        do {
            let session = AVAudioSession.sharedInstance()
            // Behaviour: timer sounds should continue in the background and mix
            // over the user's existing music instead of interrupting it.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActive = true
            return true
        } catch {
            sessionActive = false
            return false
        }
    }

    private func stopScheduledPlayers() {
        scheduledClickPlayers.forEach { $0.stop() }
        scheduledCuePlayers.forEach { $0.stop() }
        scheduledClickPlayers = []
        scheduledCuePlayers = []
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterInterruption = sessionActive
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard shouldResumeAfterInterruption, options.contains(.shouldResume),
                  let scheduleStartedAt
            else {
                shouldResumeAfterInterruption = false
                return
            }

            shouldResumeAfterInterruption = false
            let elapsed = TimerAudioTimeline.elapsedDuration(
                from: scheduleStartedAt,
                to: clock.now
            )
            let remainingIntervals = TimerAudioTimeline.remainingIntervals(
                intervalDurations: scheduledIntervalDurations,
                after: elapsed
            )
            sessionActive = false
            if remainingIntervals.isEmpty {
                stopSession()
            } else {
                _ = startSession(intervalDurations: remainingIntervals)
            }
        @unknown default:
            return
        }
    }

    private static func makePlayer(data: Data) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        player.volume = 1
        return player
    }

    private static func makeClickPlayers(
        duration: TimeInterval
    ) -> [(offset: TimeInterval, player: AVAudioPlayer)]? {
        let completeChunkCount = Int(duration / clickTrackChunkDuration)
        let completeChunksDuration = TimeInterval(completeChunkCount) * clickTrackChunkDuration
        let tailDuration = duration - completeChunksDuration
        var players: [(offset: TimeInterval, player: AVAudioPlayer)] = []

        if completeChunkCount > 0 {
            guard let player = makePlayer(data: clickTrackData(duration: clickTrackChunkDuration)) else {
                return nil
            }
            player.numberOfLoops = completeChunkCount - 1
            player.prepareToPlay()
            players.append((offset: 0, player: player))
        }

        if tailDuration > 0,
           completeChunkCount == 0 || tailDuration * TimeInterval(sampleRate) >= 1
        {
            guard let player = makePlayer(data: clickTrackData(duration: tailDuration)) else {
                return nil
            }
            player.prepareToPlay()
            players.append((offset: completeChunksDuration, player: player))
        }

        return players.isEmpty ? nil : players
    }

    private static func toneData(frequency: Double, duration: Double, amplitude: Double) -> Data {
        let sampleCount = max(Int(Double(sampleRate) * duration), 1)
        return waveData(sampleCount: sampleCount) { sampleIndex in
            let progress = Double(sampleIndex) / Double(sampleCount)
            let fadeIn = min(progress / 0.18, 1)
            let fadeOut = min((1 - progress) / 0.25, 1)
            let envelope = min(fadeIn, fadeOut)
            let wave = sin((2 * .pi * frequency * Double(sampleIndex)) / Double(sampleRate))
            return Int16((wave * amplitude * envelope * Double(Int16.max)).rounded())
        }
    }

    nonisolated static func clickTrackData(duration: TimeInterval) -> Data {
        let sampleCount = max(Int((duration * TimeInterval(sampleRate)).rounded(.up)), 1)
        return waveData(sampleCount: sampleCount) { sampleIndex in
            clickSample(frameInClick: sampleIndex % clickFrameCount)
        }
    }

    nonisolated private static func clickSample(frameInClick: Int) -> Int16 {
        let pulseFrameCount = sampleRate / 125
        guard frameInClick < pulseFrameCount else { return 0 }

        let time = Double(frameInClick) / Double(sampleRate)
        let pulseDuration = Double(pulseFrameCount) / Double(sampleRate)
        let attack = min(time / 0.0004, 1)
        let decay = exp(-time / 0.0024)
        let finalFade = min((pulseDuration - time) / 0.001, 1)
        let envelope = attack * decay * max(finalFade, 0)
        let wave = sin(2 * .pi * 2_400 * time)
        let sample = wave * envelope * 0.03
        return Int16((sample * Double(Int16.max)).rounded())
    }

    nonisolated private static func waveData(sampleCount: Int, sampleAt: (Int) -> Int16) -> Data {
        let channelCount = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let dataByteCount = sampleCount * channelCount * bytesPerSample
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataByteCount), to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(channelCount), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(byteRate), to: &data)
        append(UInt16(blockAlign), to: &data)
        append(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(dataByteCount), to: &data)

        for sampleIndex in 0..<sampleCount {
            append(sampleAt(sampleIndex), to: &data)
        }

        return data
    }

    nonisolated private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
