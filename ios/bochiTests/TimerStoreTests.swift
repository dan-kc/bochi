import Foundation
import Testing
@testable import bochi

@MainActor
struct TimerStoreTests {
    // Behaviour: saved named timers should survive an app restart with their
    // interval order and durations intact.
    @Test func savedTimerPersistsAcrossStoreReload() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("timers")
        let sut = TimerStore(storageURL: storageURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let timer = try #require(sut.addTimer(
            id: RecordID("timer-1"),
            name: "Tabata",
            intervals: [
                TimerInterval(name: "Work", durationSeconds: 20),
                TimerInterval(name: "Rest", durationSeconds: 10)
            ],
            now: now
        ))

        #expect(timer.name == "Tabata")
        let reloaded = TimerStore(storageURL: storageURL)
        let persisted = try #require(reloaded.timer(id: RecordID("timer-1")))
        #expect(persisted.intervals.map(\.name) == ["Work", "Rest"])
        #expect(persisted.intervals.map(\.durationSeconds) == [20, 10])
    }

    // Behaviour: editing a signed-in user's timer should queue that timer for
    // sync so other devices receive the updated definition.
    @Test func signedInTimerEditsMarkTimerDirtyForSync() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("timer-dirty")
        let syncStateStore = SyncStateStore(storageURL: storageURL)
        let sut = TimerStore(storageURL: storageURL, syncStateStore: syncStateStore)
        sut.setCurrentOwner("user-1")

        let timer = try #require(sut.addTimer(
            id: RecordID("timer-1"),
            name: "Focus",
            intervals: [TimerInterval(name: "Focus", durationSeconds: 1500)]
        ))

        let dirty = syncStateStore.state(for: "user-1").dirty.timers
        #expect(dirty.map(\.id) == [timer.id])
    }

    // Behaviour: invalid timer drafts should not create saved timers because
    // the timer modal needs a real name and at least one interval to run.
    @Test func invalidTimerDraftsAreRejected() {
        let sut = TimerStore(storageURL: TestHelpers.makeTemporaryFileURL("invalid-timers"))

        #expect(sut.addTimer(name: "", intervals: [TimerInterval(name: "Work", durationSeconds: 20)]) == nil)
        #expect(sut.addTimer(name: "Focus", intervals: []) == nil)
        #expect(sut.addTimer(name: "Focus", intervals: [TimerInterval(name: "", durationSeconds: 20)]) == nil)
        #expect(sut.activeTimers.isEmpty)
    }
}
