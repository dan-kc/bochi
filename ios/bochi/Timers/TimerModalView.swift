import SwiftUI

struct TimerModalView: View {
    @Environment(\.bochiTheme) private var theme
    @Binding var selection: EntityTimerSelection
    let durationSeconds: Int?
    let allowsDurationTimer: Bool

    @Environment(TimerStore.self) private var timerStore
    @State private var showingSelectTimer = false
    @State private var showingAddTimer = false
    @State private var runState = TimerRunState(intervals: [])
    @State private var lastReconciledAt: ContinuousClock.Instant?
    @State private var soundPlayer = TimerSoundPlayer()

    private let clock = ContinuousClock()

    private var resolvedSelection: EntityTimerSelection {
        selection.resolvedForDuration(durationSeconds)
    }

    private var selectedTimer: BochiTimer? {
        guard case .named(let timerID) = resolvedSelection else { return nil }
        return timerStore.timer(id: timerID)
    }

    private var activeIntervals: [TimerInterval] {
        switch resolvedSelection {
        case .none:
            return []
        case .duration:
            guard let durationSeconds else { return [] }
            return [TimerInterval(name: "Duration", durationSeconds: durationSeconds)]
        case .named:
            return selectedTimer?.intervals ?? []
        }
    }

    private var timerTitle: String {
        switch resolvedSelection {
        case .none:
            return "No Timer"
        case .duration:
            return "Duration Timer"
        case .named:
            return selectedTimer?.name ?? "Timer"
        }
    }

    private var currentInterval: TimerInterval? {
        runState.currentInterval
    }

    private var nextInterval: TimerInterval? {
        runState.nextInterval
    }

    private var intervalRemainingSeconds: Int {
        displaySeconds(runState.remainingDuration)
    }

    private var wholeTimerRemainingSeconds: Int {
        displaySeconds(runState.wholeRemainingDuration)
    }

    private var intervalProgress: Double {
        runState.intervalProgress
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TimerHeroCard(
                        timerTitle: timerTitle,
                        intervalTime: TimerClockText.format(seconds: intervalRemainingSeconds),
                        wholeTime: TimerClockText.format(seconds: wholeTimerRemainingSeconds),
                        currentIntervalName: currentInterval?.name ?? "",
                        nextIntervalName: nextInterval?.name ?? "None",
                        intervalCount: activeIntervals.count,
                        currentIntervalIndex: runState.currentIntervalIndex,
                        progress: intervalProgress,
                        isRunning: runState.isRunning,
                        canRun: !activeIntervals.isEmpty && runState.remainingDuration > 0,
                        onStartPause: startOrPauseTimer,
                        onReset: resetTimer
                    )

                    TimerSelectionButton {
                        showingSelectTimer = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground().ignoresSafeArea())
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .onAppear(perform: resetTimer)
            .onDisappear {
                runState.pause()
                soundPlayer.stopSession()
            }
            .onChange(of: selection) { _, _ in resetTimer() }
            .onChange(of: durationSeconds) { _, _ in resetTimer() }
            .sheet(isPresented: $showingSelectTimer) {
                TimerSelectionSheet(
                    selection: $selection,
                    durationSeconds: durationSeconds,
                    allowsDurationTimer: allowsDurationTimer,
                    onAddTimer: { showingAddTimer = true },
                    onTimerEdited: resetTimer
                )
            }
            .sheet(isPresented: $showingAddTimer) {
                TimerDefinitionEditor(timer: nil) { timer in
                    selection = .named(timer.id)
                }
            }
            .timerDisplayLifecycle(
                isRunning: runState.isRunning,
                notBefore: lastReconciledAt,
                onRefresh: reconcileTimer
            )
        }
    }

    private func startOrPauseTimer() {
        runState.isRunning ? pauseTimer() : startTimer()
    }

    private func startTimer() {
        guard !activeIntervals.isEmpty, runState.remainingDuration > 0 else { return }
        runState.start()
        lastReconciledAt = soundPlayer.startSession(
            intervalDurations: runState.remainingIntervalDurations
        ) ?? clock.now
    }

    private func pauseTimer() {
        reconcileTimer(at: clock.now)
        runState.pause()
        lastReconciledAt = nil
        soundPlayer.stopSession()
    }

    private func resetTimer() {
        soundPlayer.stopSession()
        lastReconciledAt = nil
        runState.reset(intervals: activeIntervals)
    }

    private func reconcileTimer(at now: ContinuousClock.Instant) {
        guard runState.isRunning, let lastReconciledAt else { return }
        let elapsedDuration = seconds(from: lastReconciledAt.duration(to: now))
        guard elapsedDuration > 0 else { return }

        self.lastReconciledAt = now
        let events = runState.advance(by: elapsedDuration)

        if events.contains(.completed) {
            self.lastReconciledAt = nil
            soundPlayer.stopSession()
        }
    }

    private func displaySeconds(_ duration: TimeInterval) -> Int {
        max(Int(ceil(duration)), 0)
    }

    private func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}

private struct TimerHeroCard: View {
    @Environment(\.bochiTheme) private var theme
    let timerTitle: String
    let intervalTime: String
    let wholeTime: String
    let currentIntervalName: String
    let nextIntervalName: String
    let intervalCount: Int
    let currentIntervalIndex: Int
    let progress: Double
    let isRunning: Bool
    let canRun: Bool
    let onStartPause: () -> Void
    let onReset: () -> Void

    private var cardFill: Color {
        theme.solidFill(for: .settings)
    }

    private var cardForeground: Color {
        .white
    }

    var body: some View {
        Group {
            if intervalCount == 0 {
                Text("Select a timer to get started.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                timerContent
            }
        }
        .foregroundStyle(cardForeground)
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            cardFill,
                            theme.solidFillHover(for: .settings)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: cardFill.opacity(0.32), radius: 18, x: 0, y: 12)
    }

    private var timerContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 5) {
                Text(timerTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(currentIntervalName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(0.9)
            }

            ZStack {
                Circle()
                    .stroke(cardForeground.opacity(0.34), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        cardForeground,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 6) {
                    Text(intervalTime)
                        .font(.system(size: 58, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Text("interval left")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .opacity(0.76)
                }
                .padding(24)
            }
            .frame(maxWidth: 242)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .combine)

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                TimerDisplayMetric(title: "Whole timer", value: wholeTime)
                Divider()
                    .frame(height: 34)
                    .overlay(cardForeground.opacity(0.36))
                TimerDisplayMetric(title: "Next", value: nextIntervalName)
            }

            TimerIntervalDots(count: intervalCount, currentIndex: currentIntervalIndex)

            HStack(spacing: 14) {
                Button(action: onStartPause) {
                    Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TimerCardButtonStyle(foreground: cardFill, background: cardForeground))
                .disabled(!canRun)

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .accessibilityLabel("Reset timer")
                }
                .buttonStyle(TimerCardButtonStyle(foreground: cardForeground, background: cardForeground.opacity(0.18)))
                .disabled(intervalCount == 0)
            }
        }
    }
}

private struct TimerDisplayMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.72)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TimerIntervalDots: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<min(count, 12), id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.2))
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.88), lineWidth: index == currentIndex ? 0 : 1.5)
                    }
                    .frame(width: 10, height: 10)
            }

            if count > 12 {
                Text("+\(count - 12)")
                    .font(.caption.weight(.semibold))
                    .opacity(0.8)
            }
        }
        .frame(height: 18)
        .accessibilityLabel("\(count) intervals")
    }
}

private struct TimerSelectionButton: View {
    @Environment(\.bochiTheme) private var theme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Label("Select Timer", systemImage: "list.bullet")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(theme.solidFill(for: .settings))
    }
}

private struct TimerCardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .foregroundStyle(foreground)
            .background(Capsule(style: .continuous).fill(background))
            .opacity(!isEnabled ? 0.42 : configuration.isPressed ? 0.72 : 1)
    }
}

private struct TimerSelectionSheet: View {
    @Binding var selection: EntityTimerSelection
    let durationSeconds: Int?
    let allowsDurationTimer: Bool
    let onAddTimer: () -> Void
    let onTimerEdited: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.bochiTheme) private var theme
    @Environment(TimerStore.self) private var timerStore
    @State private var editingTimer: BochiTimer?

    var body: some View {
        NavigationStack {
            List {
                Button("No Timer", systemImage: "xmark.circle") {
                    selection = .none
                    dismiss()
                }

                if allowsDurationTimer, durationSeconds != nil {
                    Button("Duration", systemImage: "timer") {
                        selection = .duration
                        dismiss()
                    }
                }

                Section("Named Timers") {
                    ForEach(timerStore.activeTimers) { timer in
                        HStack(spacing: 0) {
                            Button {
                                selection = .named(timer.id)
                                dismiss()
                            } label: {
                                Label(timer.name, systemImage: "stopwatch")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingTimer = timer
                            } label: {
                                Image(systemName: "pencil")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(timer.name)")
                        }
                    }
                    Button("Add New", systemImage: "plus") {
                        dismiss()
                        DispatchQueue.main.async {
                            onAddTimer()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Select Timer")
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(theme.appBackground())
        }
        .sheet(item: $editingTimer) { timer in
            TimerDefinitionEditor(timer: timer) { _ in
                onTimerEdited()
            }
        }
    }
}

private struct TimerDefinitionEditor: View {
    @Environment(\.bochiTheme) private var theme

    private struct DraftInterval: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var durationText: String
    }

    private enum FieldFocus: Hashable {
        case intervalName(UUID)
    }

    let timer: BochiTimer?
    let onSaved: (BochiTimer) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TimerStore.self) private var timerStore

    @State private var name = ""
    @State private var intervals: [DraftInterval] = [
        DraftInterval(name: "", durationText: "")
    ]
    @State private var attemptedSave = false
    @FocusState private var focusedField: FieldFocus?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimerRequiredField(requiresAttention: attemptedSave && trimmedName.isEmpty) {
                        ImmediateFocusTextField(
                            placeholder: "Name",
                            text: $name,
                            autocapitalizationType: .words,
                            autofocus: timer == nil
                        )
                        .frame(minHeight: 24)
                    }
                } footer: {
                    if attemptedSave && trimmedName.isEmpty {
                        Text("Timer name is required.")
                            .foregroundStyle(BochiTheme.solidFill(palette: .red))
                    }
                }

                Section {
                    ForEach($intervals) { $interval in
                        VStack(alignment: .leading, spacing: 10) {
                            TimerRequiredField(requiresAttention: attemptedSave && intervalNameRequiresAttention(interval)) {
                                TextField("Interval name", text: $interval.name)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .intervalName(interval.id))
                            }

                            TimerRequiredField(requiresAttention: attemptedSave && intervalDurationRequiresAttention(interval)) {
                                TextField("Seconds", text: $interval.durationText)
                                    .keyboardType(.numberPad)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { intervals.remove(atOffsets: $0) }

                    Button("Add Interval", systemImage: "plus") {
                        let newInterval = DraftInterval(name: "", durationText: "")
                        intervals.append(newInterval)
                        DispatchQueue.main.async {
                            focusedField = .intervalName(newInterval.id)
                        }
                    }
                } header: {
                    Text("Intervals")
                } footer: {
                    if attemptedSave && validIntervals == nil {
                        Text("Each interval needs a name and a duration from 1 through 43200 seconds.")
                            .foregroundStyle(BochiTheme.solidFill(palette: .red))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle(timer == nil ? "New Timer" : "Edit Timer")
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(theme.appBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: initialize)
        }
    }

    private var validIntervals: [TimerInterval]? {
        let parsed = intervals.compactMap { draft -> TimerInterval? in
            let trimmedIntervalName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIntervalName.isEmpty else { return nil }
            guard let seconds = Int(draft.durationText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...43_200).contains(seconds)
            else {
                return nil
            }
            return TimerInterval(
                name: String(trimmedIntervalName.prefix(50)),
                durationSeconds: seconds
            )
        }
        guard parsed.count == intervals.count, !parsed.isEmpty else { return nil }
        return parsed
    }

    private func intervalNameRequiresAttention(_ interval: DraftInterval) -> Bool {
        interval.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func intervalDurationRequiresAttention(_ interval: DraftInterval) -> Bool {
        guard let seconds = Int(interval.durationText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return true
        }
        return !(1...43_200).contains(seconds)
    }

    private func initialize() {
        guard let timer else { return }
        name = timer.name
        intervals = timer.intervals.map {
            DraftInterval(name: $0.name, durationText: String($0.durationSeconds))
        }
        if intervals.isEmpty {
            intervals = [DraftInterval(name: "", durationText: "")]
        }
    }

    private func save() {
        attemptedSave = true
        guard !trimmedName.isEmpty, let validIntervals else { return }
        let trimmedTimerName = String(trimmedName.prefix(50))

        if let timer {
            timerStore.updateTimer(id: timer.id, name: trimmedTimerName, intervals: validIntervals)
            if let updatedTimer = timerStore.timer(id: timer.id) {
                onSaved(updatedTimer)
            }
            dismiss()
            return
        }

        if let createdTimer = timerStore.addTimer(name: trimmedTimerName, intervals: validIntervals) {
            onSaved(createdTimer)
            dismiss()
        }
    }
}

private struct TimerRequiredField<Content: View>: View {
    @Environment(\.bochiTheme) private var theme
    let requiresAttention: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, requiresAttention ? 10 : 0)
            .padding(.vertical, requiresAttention ? 7 : 0)
            .background {
                if requiresAttention {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.componentBackground(for: .neutral))
                }
            }
            .overlay {
                if requiresAttention {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BochiTheme.solidFill(palette: .red), lineWidth: 1)
                }
            }
    }
}

private enum TimerClockText {
    static func format(seconds: Int) -> String {
        let clampedSeconds = max(seconds, 0)
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let seconds = clampedSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
