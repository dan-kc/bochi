import Testing
@testable import tofustash

// Tests for UserSettingsStore — stores user preferences like general difficulty.
@MainActor
struct UserSettingsStoreTests {

    private func makeSUT() -> UserSettingsStore {
        UserSettingsStore()
    }

    @Test("Default general difficulty is 5.0")
    func defaultValue() {
        let sut = makeSUT()
        #expect(sut.generalDifficulty == 5.0)
    }

    @Test("setGeneralDifficulty updates the value")
    func setsValue() {
        let sut = makeSUT()
        sut.setGeneralDifficulty(10.0)
        #expect(sut.generalDifficulty == 10.0)
    }

    @Test("setGeneralDifficulty rejects values <= 0")
    func rejectsZeroOrNegative() {
        let sut = makeSUT()
        sut.setGeneralDifficulty(0)
        #expect(sut.generalDifficulty == 5.0) // unchanged
        sut.setGeneralDifficulty(-1)
        #expect(sut.generalDifficulty == 5.0) // unchanged
    }

    @Test("setGeneralDifficulty rejects values >= 1000")
    func rejectsThousandOrMore() {
        let sut = makeSUT()
        sut.setGeneralDifficulty(1000)
        #expect(sut.generalDifficulty == 5.0) // unchanged
        sut.setGeneralDifficulty(1500)
        #expect(sut.generalDifficulty == 5.0) // unchanged
    }

    @Test("setGeneralDifficulty accepts decimal values")
    func acceptsDecimals() {
        let sut = makeSUT()
        sut.setGeneralDifficulty(2.5)
        #expect(sut.generalDifficulty == 2.5)
    }
}
