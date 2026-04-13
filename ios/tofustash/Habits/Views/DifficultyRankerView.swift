import SwiftUI

// SwiftUI wrapper around the DifficultyRanker.Session logic.
// The session struct holds all state; this view just renders it.
//
// In React, the DifficultyRanker component mixed state (useState/useEffect)
// and UI into one component. Here the Session struct is pure logic (testable
// without UI), and this view is a thin rendering layer on top.
//
// Like a React component that uses useReducer for complex state —
// the reducer (Session) is tested independently from the component.
struct DifficultyRankerView: View {
    @Binding var difficultyRank: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var habitStore

    // The ranking session — drives the binary search state machine
    @State private var session: DifficultyRanker.Session

    // Whether initializeSession() has run. The session starts with empty
    // rankedHabits (isComplete == true) because @Environment isn't available
    // in init(). We gate the completion view on this flag so it doesn't
    // flash the checkmark and auto-dismiss before the real session loads.
    @State private var isInitialized = false

    // Drives the checkmark pop-in animation. Starts false (scaled to 0),
    // set to true on appear so the checkmark springs into view.
    // Like a CSS class toggle: className={showCheck ? "scale-100" : "scale-0"}
    @State private var showCheckmark = false

    // Exclude this habit from comparisons (for change form editing existing habit)
    let excludeHabitId: String?

    // The difficulty rank when the ranker was opened — used to decide whether
    // to show the "Unset" toolbar button. Captured at init time so it doesn't
    // change mid-session. Like capturing props.initialValue in React.
    let currentDifficultyRank: String?

    init(
        habitName: String,
        difficultyRank: Binding<String?>,
        currentDifficultyRank: String? = nil,
        excludeHabitId: String? = nil
    ) {
        self._difficultyRank = difficultyRank
        self.currentDifficultyRank = currentDifficultyRank
        self.excludeHabitId = excludeHabitId
        // Initialize with empty session — will be replaced in .onAppear
        // when we have access to habitStore via @Environment
        self._session = State(initialValue: DifficultyRanker.makeSession(
            habitName: habitName,
            rankedHabits: []
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isInitialized {
                    // Show nothing until the real session loads from habitStore.
                    // Without this gate, the empty initial session (isComplete == true)
                    // would render the completion view and auto-dismiss immediately.
                    Color.clear
                } else if session.isComplete {
                    completionView
                } else if let comparison = session.currentComparison {
                    comparisonView(comparison)
                }
            }
            .navigationTitle(session.isComplete ? "" : "Set Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            // Toolbar only shows during active comparison — the completion
            // screen auto-dismisses, so no navigation buttons are needed.
            .toolbar(session.isComplete ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                // Cancel button — replaces the old "Skip" at the bottom.
                // Placed top-left (cancellationAction) per iOS convention.
                // Like a "Cancel" button in a React modal header.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                // Unset button — only shown when difficulty is already set.
                // Clears the rank and dismisses, like a "Reset" action.
                if Self.shouldShowUnsetButton(currentDifficultyRank: currentDifficultyRank) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Unset") {
                            difficultyRank = nil
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                initializeSession()
            }
        }
    }

    // Shown when binary search is complete — just the green checkmark,
    // no text or buttons. The checkmark pops in with a spring animation,
    // then the sheet auto-dismisses after 1 second.
    // Task.sleep is like setTimeout in JS but cooperative — it cancels
    // automatically if the view disappears (user swipes sheet away).
    private var completionView: some View {
        VStack {
            // "checkmark.circle.fill" is an SF Symbol — like a Material Icon.
            // Starts at scale 0 and springs to full size on appear —
            // like a CSS keyframe: 0% { transform: scale(0) } 100% { transform: scale(1) }
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .scaleEffect(showCheckmark ? 1.0 : 0.0)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: showCheckmark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Small delay so the view is laid out before animating.
            // Without this, the spring may not be visible because SwiftUI
            // could batch the initial layout and the state change together.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showCheckmark = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }

    // Shown during active comparison — asks user "harder or easier?"
    private func comparisonView(_ comparison: Habit) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with remaining comparisons
                Text("~\(max(1, session.estimatedComparisons - session.comparisonCount)) comparison\(session.estimatedComparisons - session.comparisonCount != 1 ? "s" : "") remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // New habit card
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Habit")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(session.habitName)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Is this habit harder or easier than:")
                    .foregroundStyle(.secondary)

                // Comparison habit card
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comparison.name)
                        .font(.headline)
                    if !comparison.description.isEmpty {
                        Text(comparison.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Action buttons — Harder and Easier only. Cancel/Unset
                // are in the toolbar now (top-left / top-right).
                VStack(spacing: 12) {
                    Button {
                        session.chooseHarder()
                        checkCompletion()
                    } label: {
                        Text("Harder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        session.chooseEasier()
                        checkCompletion()
                    } label: {
                        Text("Easier")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }

    // Whether to show the "Unset" toolbar button. Only shown when difficulty
    // is already set — gives the user a way to clear it without re-ranking.
    // Static so it can be unit tested without instantiating the view.
    static func shouldShowUnsetButton(currentDifficultyRank: String?) -> Bool {
        currentDifficultyRank != nil
    }

    private func initializeSession() {
        // Get ranked habits sorted hardest→easiest, excluding the current habit
        let ranked = habitStore.activeHabits
            .filter { $0.difficultyRank != nil && $0.id != excludeHabitId }
            .sorted { ($0.difficultyRank ?? "") > ($1.difficultyRank ?? "") }

        session = DifficultyRanker.makeSession(
            habitName: session.habitName,
            rankedHabits: ranked
        )

        isInitialized = true

        // If no ranked habits exist, complete immediately
        if session.isComplete {
            difficultyRank = session.generateRank()
        }
    }

    private func checkCompletion() {
        if session.isComplete {
            difficultyRank = session.generateRank()
        }
    }
}
