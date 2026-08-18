import Foundation

@Observable
@MainActor
final class PremiumWelcomeStore {
    var isPresented = false
    private(set) var presentationRequestID = 0

    func requestPresentation() {
        presentationRequestID += 1
    }

    func present(requestID: Int) {
        guard requestID == presentationRequestID else { return }
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
