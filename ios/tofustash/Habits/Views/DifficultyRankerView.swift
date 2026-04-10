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

    // Exclude this habit from comparisons (for change form editing existing habit)
    let excludeHabitId: String?

    init(habitName: String, difficultyRank: Binding<String?>, excludeHabitId: String? = nil) {
        self._difficultyRank = difficultyRank
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
                if session.isComplete {
                    completionView
                } else if let comparison = session.currentComparison {
                    comparisonView(comparison)
                }
            }
            .navigationTitle("Set Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                initializeSession()
            }
        }
    }

    // Shown when binary search is complete
    private var completionView: some View {
        VStack(spacing: 16) {
            // "checkmark.circle.fill" is an SF Symbol — like a Material Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("Done!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Difficulty set after \(session.comparisonCount) comparison\(session.comparisonCount != 1 ? "s" : "").")
                .foregroundStyle(.secondary)
        }
        .padding()
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

                // Action buttons
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

                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
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
