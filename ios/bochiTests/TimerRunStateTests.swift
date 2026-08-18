import Foundation
import Testing
@testable import bochi

struct TimerRunStateTests {
    // Behaviour: delayed UI refreshes should subtract the real elapsed duration,
    // so backgrounding cannot slow the timer down or accumulate callback drift.
    @Test func delayedRefreshUsesRealElapsedDuration() {
        var sut = TimerRunState(intervals: [
            TimerInterval(name: "Focus", durationSeconds: 10)
        ])

        sut.start()
        _ = sut.advance(by: 0.31)
        _ = sut.advance(by: 0.19)

        #expect(sut.remainingDuration == 9.5)
        #expect(sut.isRunning)
    }

    // Behaviour: returning after a background gap should land in the correct
    // interval rather than resuming the interval that was visible before it.
    @Test func backgroundGapAdvancesAcrossIntervals() {
        var sut = TimerRunState(intervals: [
            TimerInterval(name: "Work", durationSeconds: 1),
            TimerInterval(name: "Rest", durationSeconds: 2)
        ])

        sut.start()
        let events = sut.advance(by: 1.75)

        #expect(events == [.intervalTransition])
        #expect(sut.currentIntervalIndex == 1)
        #expect(sut.remainingDuration == 1.25)
        #expect(sut.isRunning)
    }

    // Behaviour: a gap longer than the complete routine should finish the timer
    // immediately instead of replaying overdue intervals when the app wakes.
    @Test func backgroundGapCanCompleteWholeTimer() {
        var sut = TimerRunState(intervals: [
            TimerInterval(name: "Work", durationSeconds: 1),
            TimerInterval(name: "Rest", durationSeconds: 2)
        ])

        sut.start()
        let events = sut.advance(by: 5)

        #expect(events == [.intervalTransition, .completed])
        #expect(sut.remainingDuration == 0)
        #expect(!sut.isRunning)
    }

    // Behaviour: time spent paused should not be charged to the timer, while a
    // resumed run should continue from the exact fractional duration remaining.
    @Test func pauseAndResumePreserveElapsedProgress() {
        var sut = TimerRunState(intervals: [
            TimerInterval(name: "Focus", durationSeconds: 10)
        ])

        sut.start()
        _ = sut.advance(by: 1.25)
        sut.pause()
        _ = sut.advance(by: 30)
        sut.start()
        _ = sut.advance(by: 0.75)

        #expect(sut.remainingDuration == 8)
        #expect(sut.isRunning)
    }

    // Behaviour: the rendered track should contain four byte-identical clicks
    // per second, so neither sound nor spacing can vary between beats.
    @Test func clickTrackContainsFourIdenticalClicksPerSecond() {
        let mono16BitWAVHeaderByteCount = 44
        let bytesPerFrame = 2
        let duration: TimeInterval = 2
        let data = TimerSoundPlayer.clickTrackData(duration: duration)
        let pcmData = data.dropFirst(mono16BitWAVHeaderByteCount)
        let clickByteCount = TimerSoundPlayer.clickFrameCount * bytesPerFrame
        let firstClick = Data(pcmData.prefix(clickByteCount))
        let expectedClickCount = Int(duration) * TimerSoundPlayer.clicksPerSecond

        #expect(TimerSoundPlayer.clickFrameCount * TimerSoundPlayer.clicksPerSecond == TimerSoundPlayer.sampleRate)
        #expect(
            data.count
                == mono16BitWAVHeaderByteCount
                    + (Int(duration) * TimerSoundPlayer.sampleRate * bytesPerFrame)
        )
        #expect(firstClick.contains { $0 != 0 })
        for clickIndex in 1..<expectedClickCount {
            let start = clickIndex * clickByteCount
            let click = Data(pcmData.dropFirst(start).prefix(clickByteCount))
            #expect(click == firstClick)
        }
    }

    // Behaviour: while visible and running, the timer should refresh within one
    // display frame so a countdown beep cannot lead its number by 250 ms.
    @Test func activeTimerRefreshesAtDisplayCadence() {
        #expect(TimerDisplayTimeline.refreshInterval <= .milliseconds(17))
        #expect(TimerDisplayTimeline.shouldRefresh(isRunning: true, sceneIsActive: true))
    }

    // Behaviour: display refresh work should stop when the timer is paused or
    // backgrounded; foregrounding will reconcile the full elapsed gap at once.
    @Test func inactiveTimerDoesNotRunDisplayRefreshWork() {
        #expect(!TimerDisplayTimeline.shouldRefresh(isRunning: false, sceneIsActive: true))
        #expect(!TimerDisplayTimeline.shouldRefresh(isRunning: true, sceneIsActive: false))
    }

    // Behaviour: the final three countdown beeps should be scheduled exactly one
    // second apart on the audio clock instead of following UI refresh callbacks.
    @Test func countdownCuesAreExactlyOneSecondApart() {
        let cues = TimerAudioTimeline.cues(intervalDurations: [10])

        #expect(cues == [
            TimerAudioCue(kind: .countdown, offset: 7),
            TimerAudioCue(kind: .countdown, offset: 8),
            TimerAudioCue(kind: .countdown, offset: 9)
        ])
    }

    // Behaviour: every interval should have audio-clock countdown cues, including
    // short later intervals whose first beep occurs exactly at their transition.
    @Test func multiIntervalCuesAreScheduledBeforePlaybackStarts() {
        let cues = TimerAudioTimeline.cues(intervalDurations: [4, 2])

        #expect(cues == [
            TimerAudioCue(kind: .countdown, offset: 1),
            TimerAudioCue(kind: .countdown, offset: 2),
            TimerAudioCue(kind: .countdown, offset: 3),
            TimerAudioCue(kind: .transition, offset: 4),
            TimerAudioCue(kind: .countdown, offset: 4),
            TimerAudioCue(kind: .countdown, offset: 5)
        ])
    }

    // Behaviour: resuming partway through the final countdown should only play
    // future cues, preserving their exact positions relative to completion.
    @Test func resumedCountdownSkipsCuesThatAlreadyPassed() {
        let cues = TimerAudioTimeline.cues(intervalDurations: [2.5])

        #expect(cues == [
            TimerAudioCue(kind: .countdown, offset: 0.5),
            TimerAudioCue(kind: .countdown, offset: 1.5)
        ])
    }

    // Behaviour: resuming after an interruption should discard completed
    // intervals and rebuild cues from the exact remaining fractional duration.
    @Test func interruptionResumeKeepsOnlyRemainingIntervals() {
        #expect(TimerAudioTimeline.remainingIntervals(
            intervalDurations: [4, 5],
            after: 4.5
        ) == [4.5])
        #expect(TimerAudioTimeline.remainingIntervals(
            intervalDurations: [4, 5],
            after: 10
        ).isEmpty)
    }

    // Behaviour: interruption recovery should measure from the scheduled audio
    // start and must not add the scheduling lead time a second time.
    @Test func interruptionElapsedTimeStartsAtScheduledAudioStart() {
        let clock = ContinuousClock()
        let audioStartedAt = clock.now.advanced(by: .milliseconds(100))
        let interruptionEndedAt = audioStartedAt.advanced(by: .seconds(2))

        #expect(
            TimerAudioTimeline.elapsedDuration(
                from: audioStartedAt,
                to: interruptionEndedAt
            ) == 2
        )
    }
}
