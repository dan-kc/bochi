import Combine
import SwiftUI
import UIKit

// HabitFormMode is like a discriminated union in TypeScript:
//   { type: "new" } | { type: "change", habit: Habit }
//
// Swift enums can carry data for each case, so `.change` can include the habit
// being edited without needing a separate wrapper object.
enum HabitFormMode: Equatable {
    case new
    case change(Habit)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

// Which part of the habit flow should open first.
// The user can land directly in name/description, frequency, difficulty, or tags
// depending on which control they tapped before opening the modal.
enum HabitFormFocus: Equatable {
    case name
    case description
    case frequency
    case difficulty
    case tags

    var isNameDescription: Bool {
        self == .name || self == .description
    }
}

// The habit flow has two visual surfaces inside one modal:
// 1. a small name/description editor
// 2. the full habit form
//
// Keeping this as explicit state makes the "morph" animation predictable.
enum HabitFormSurface: Equatable {
    case nameDescription
    case form
}

// Captures a discarded new-habit draft so the parent can offer recovery.
// Like serializing controlled-input state before unmounting a React modal.
struct HabitFormSnapshot {
    let name: String
    let description: String
    let frequency: Double?
    let difficultyRank: String?
    let habitId: String
}

// Custom modal wrapper for the habit flow.
// We intentionally avoid SwiftUI's sheet detents here because the user wants:
// - content-sized height
// - an editor that morphs into the full form
// - the keyboard to animate with the opening modal
//
// A custom overlay gives us direct control over height, keyboard avoidance,
// and enter/exit transitions.
struct HabitFormModal: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    let prefill: HabitFormSnapshot?
    let onDiscard: ((HabitFormSnapshot) -> Void)?
    let onDelete: ((Habit) -> Void)?
    let onClose: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var keyboardOverlap: CGFloat = 0
    @State private var keyboardAnimation = Animation.easeOut(duration: 0.25)

    var body: some View {
        GeometryReader { proxy in
            let sideInset: CGFloat = 12
            let cardWidth = min(560, proxy.size.width - (sideInset * 2))
            let bottomInset = keyboardOverlap > 0 ? keyboardOverlap : proxy.safeAreaInsets.bottom
            let maxCardHeight = max(0, proxy.size.height - proxy.safeAreaInsets.top - bottomInset)
            let needsScroll = contentHeight > maxCardHeight

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onClose()
                    }

                if needsScroll {
                    ScrollView(showsIndicators: false) {
                        measuredContent
                    }
                    .frame(width: cardWidth, height: maxCardHeight, alignment: .top)
                    .modifier(HabitFormCardChrome())
                    .padding(.horizontal, sideInset)
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    measuredContent
                        .frame(width: cardWidth, alignment: .top)
                        .modifier(HabitFormCardChrome())
                        .padding(.horizontal, sideInset)
                        .padding(.bottom, bottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onPreferenceChange(ContentHeightPreferenceKey.self) { newHeight in
                contentHeight = newHeight
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                updateKeyboard(with: note, in: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                updateKeyboard(with: note, in: proxy)
            }
            .animation(.easeInOut(duration: 0.24), value: needsScroll)
        }
    }

    private var measuredContent: some View {
        HabitFormView(
            mode: mode,
            initialFocus: initialFocus,
            prefill: prefill,
            onClose: onClose,
            onDiscard: onDiscard,
            onDelete: onDelete
        )
        // Measure the card from its intrinsic content height, not from a scroll
        // container or full-screen presentation host.
        .fixedSize(horizontal: false, vertical: true)
        .background(HeightReader())
    }

    private func updateKeyboard(with note: Notification, in proxy: GeometryProxy) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        keyboardAnimation = .easeOut(duration: duration)

        let screenEndFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let overlap = max(0, proxy.frame(in: .global).maxY - screenEndFrame.minY)

        withAnimation(keyboardAnimation) {
            keyboardOverlap = overlap
        }
    }
}

private struct HabitFormCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
}

struct HabitFormView: View {
    let mode: HabitFormMode
    let initialFocus: HabitFormFocus?
    let prefill: HabitFormSnapshot?
    let onClose: () -> Void
    let onDiscard: ((HabitFormSnapshot) -> Void)?
    let onDelete: ((Habit) -> Void)?

    @Environment(HabitStore.self) private var habitStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var surface: HabitFormSurface
    @State private var hasShownMainForm: Bool
    @State private var name = ""
    @State private var description = ""
    @State private var frequency: Double? = nil
    @State private var difficultyRank: String? = nil
    @State private var habitId: String = UUID().uuidString

    @State private var showingFrequency = false
    @State private var showingDifficulty = false
    @State private var showingTags = false
    @State private var showingTradeModal = false
    @State private var shouldCloseAfterTrade = false
    @State private var showingFirstHabitAlert = false
    @State private var difficultyPillAnimating = false

    @State private var activeEntryField: EntryField
    @State private var focusedEntryField: EntryField? = nil
    @State private var descriptionHeight = Self.minimumDescriptionHeight

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false

    enum EntryField: Hashable {
        case name
        case description
    }

    private var habitTags: [Tag] {
        tagStore.tagsForHabit(habitId: habitId)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 100
    }

    private var isFirstHabit: Bool {
        Self.isFirstHabit(mode: mode, activeHabitsCount: habitStore.activeHabits.count)
    }

    private var hasComparableHabits: Bool {
        let rankedCount = habitStore.activeHabits
            .filter { $0.difficultyRank != nil && $0.id != habitId }
            .count
        return Self.hasComparableHabits(rankedHabitCount: rankedCount, excludeHabitId: mode.isNew ? nil : habitId)
    }

    private var currentPrice: Int {
        guard case .change(let habit) = mode else { return 0 }
        let completions = tradeStore.tradesInPeriod(habitId: habit.id, days: 7)
        return RewardCalculation.calculateReward(
            habit: habit,
            allHabits: habitStore.activeHabits,
            completionsInPeriod: completions,
            generalDifficulty: userSettingsStore.generalDifficulty
        )
    }

    private var canTrade: Bool {
        frequency != nil && difficultyRank != nil
    }

    private var missingPropertiesText: String {
        RewardCalculation.missingTradeProperties(frequency: frequency, difficultyRank: difficultyRank) ?? ""
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: description,
            frequency: frequency,
            difficultyRank: difficultyRank,
            tagCount: habitTags.count,
            isFirstHabit: isFirstHabit
        )
    }

    private var toolbarTitle: String {
        switch surface {
        case .nameDescription:
            "Name & Description"
        case .form:
            mode.isNew ? "New Habit" : "Edit Habit"
        }
    }

    init(
        mode: HabitFormMode = .new,
        initialFocus: HabitFormFocus? = nil,
        prefill: HabitFormSnapshot? = nil,
        onClose: @escaping () -> Void = {},
        onDiscard: ((HabitFormSnapshot) -> Void)? = nil,
        onDelete: ((Habit) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onClose = onClose
        self.onDiscard = onDiscard
        self.onDelete = onDelete

        let initialSurface = Self.initialSurface(mode: mode, initialFocus: initialFocus, hasPrefill: prefill != nil)
        self._surface = State(initialValue: initialSurface)
        self._hasShownMainForm = State(initialValue: initialSurface == .form)
        self._activeEntryField = State(initialValue: Self.entryField(for: Self.initialEntryFocus(initialFocus: initialFocus)))

        if let prefill {
            self._habitId = State(initialValue: prefill.habitId)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                if surface == .form {
                    mainFormContent
                        .transition(.opacity)
                }

                if surface == .nameDescription {
                    nameDescriptionContent
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .animation(.easeInOut(duration: 0.24), value: surface)
        }
        .sheet(isPresented: $showingFrequency) {
            FrequencyModal(frequency: $frequency)
        }
        .sheet(isPresented: $showingDifficulty, onDismiss: {
            if difficultyRank != nil {
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                    difficultyPillAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                        difficultyPillAnimating = false
                    }
                }
            }
        }) {
            DifficultyRankerView(
                habitName: trimmedName.isEmpty ? "New Habit" : trimmedName,
                difficultyRank: $difficultyRank,
                currentDifficultyRank: difficultyRank,
                excludeHabitId: mode.isNew ? nil : habitId
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(habitId: habitId)
        }
        .sheet(isPresented: $showingTradeModal, onDismiss: {
            if shouldCloseAfterTrade {
                shouldCloseAfterTrade = false
                onClose()
            }
        }) {
            if case .change(let habit) = mode {
                TradeModalView(habit: habit) {
                    shouldCloseAfterTrade = true
                }
            }
        }
        .alert("Difficulty Set", isPresented: $showingFirstHabitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There are no other habits to compare against. Add more habits to adjust difficulty ranking.")
        }
        .onAppear {
            initializeIfNeeded()
        }
        .onChange(of: name) { _, _ in autoSave() }
        .onChange(of: description) { _, _ in autoSave() }
        .onChange(of: frequency) { _, _ in autoSave() }
        .onChange(of: difficultyRank) { _, _ in autoSave() }
    }

    private var toolbar: some View {
        HStack {
            leadingToolbarButton

            Spacer()

            Text(toolbarTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            trailingToolbarButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var leadingToolbarButton: some View {
        switch surface {
        case .nameDescription where hasShownMainForm:
            Button {
                closeNameDescriptionEditor()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
        default:
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch surface {
        case .nameDescription:
            Button {
                closeNameDescriptionEditor()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        case .form where mode.isNew:
            Button("Add") {
                persistHabit()
                didPersist = true
                onClose()
            }
            .disabled(!isValid)
            .buttonStyle(.borderedProminent)
        default:
            Color.clear
                .frame(width: 36, height: 36)
        }
    }

    private var mainFormContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainFieldCard

            PillRow(pills: buildPills())

            if !habitTags.isEmpty {
                sectionCard {
                    TagPillsRow(tags: habitTags)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingTags = true
                        }
                }
            }

            if case .change(let habitForDelete) = mode {
                if canTrade {
                    sectionCard {
                        Button {
                            showingTradeModal = true
                        } label: {
                            HStack {
                                Text("Claim Reward")
                                Spacer()
                                HStack(spacing: 2) {
                                    Text("\(currentPrice)")
                                        .contentTransition(.numericText())
                                    Image(systemName: "cube.fill")
                                        .font(.caption2)
                                }
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Label {
                        Text("Set \(missingPropertiesText) to enable rewards")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                sectionCard {
                    Button("Delete Habit", role: .destructive) {
                        onClose()
                        onDelete?(habitForDelete)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var mainFieldCard: some View {
        VStack(spacing: 0) {
            fieldSummaryButton(
                title: "Name",
                value: trimmedName.isEmpty ? nil : name,
                lineLimit: 1,
                field: .name
            )

            Divider()
                .padding(.leading, 16)

            fieldSummaryButton(
                title: "Description",
                value: trimmedDescription.isEmpty ? nil : description,
                lineLimit: 3,
                field: .description
            )
        }
        .background(cardBackground)
    }

    private var nameDescriptionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Give the habit a clear name, then add as much description as the user needs.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            fieldCard(title: "Name") {
                AutoFocusingTextField(
                    text: $name,
                    placeholder: "Name",
                    isFirstResponder: focusBinding(for: .name)
                )
                .frame(height: 24)
            }

            fieldCard(title: "Description") {
                GrowingTextView(
                    text: $description,
                    placeholder: "Description",
                    measuredHeight: $descriptionHeight,
                    minHeight: Self.minimumDescriptionHeight,
                    isFirstResponder: focusBinding(for: .description)
                )
                .frame(height: max(Self.minimumDescriptionHeight, descriptionHeight))
            }
        }
    }

    private func fieldSummaryButton(title: String, value: String?, lineLimit: Int, field: EntryField) -> some View {
        Button {
            openNameDescriptionEditor(field)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let value, !value.isEmpty {
                    Text(value)
                        .foregroundStyle(.primary)
                        .lineLimit(lineLimit)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .lineLimit(lineLimit)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fieldCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(14)
        .background(cardBackground)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
    }

    private func openNameDescriptionEditor(_ field: EntryField) {
        activeEntryField = field
        focusedEntryField = field
        withAnimation(.easeInOut(duration: 0.24)) {
            surface = .nameDescription
        }
    }

    private func closeNameDescriptionEditor() {
        focusedEntryField = nil
        hasShownMainForm = true
        withAnimation(.easeInOut(duration: 0.24)) {
            surface = .form
        }
    }

    private func focusBinding(for field: EntryField) -> Binding<Bool> {
        Binding(
            get: { focusedEntryField == field },
            set: { isFocused in
                if isFocused {
                    focusedEntryField = field
                } else if focusedEntryField == field {
                    focusedEntryField = nil
                }
            }
        )
    }

    private func requestClose() {
        focusedEntryField = nil

        if mode.isNew && !didPersist && hasContent {
            onDiscard?(HabitFormSnapshot(
                name: name,
                description: description,
                frequency: frequency,
                difficultyRank: difficultyRank,
                habitId: habitId
            ))
        }

        onClose()
    }

    static func initialSurface(mode: HabitFormMode, initialFocus: HabitFormFocus?, hasPrefill: Bool) -> HabitFormSurface {
        if hasPrefill {
            return .form
        }

        if mode.isNew {
            return .nameDescription
        }

        if initialFocus?.isNameDescription == true {
            return .nameDescription
        }

        return .form
    }

    static func initialEntryFocus(initialFocus: HabitFormFocus?) -> HabitFormFocus {
        initialFocus == .description ? .description : .name
    }

    private static func entryField(for focus: HabitFormFocus) -> EntryField {
        focus == .description ? .description : .name
    }

    static func hasContent(
        name: String,
        description: String,
        frequency: Double?,
        difficultyRank: String?,
        tagCount: Int,
        isFirstHabit: Bool = false
    ) -> Bool {
        let hasDifficulty = isFirstHabit ? false : difficultyRank != nil

        return !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || frequency != nil
            || hasDifficulty
            || tagCount > 0
    }

    static func nameForAutoSave(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }

    static func isFirstHabit(mode: HabitFormMode, activeHabitsCount: Int) -> Bool {
        mode.isNew && activeHabitsCount == 0
    }

    static func defaultDifficultyRankForFirstHabit() -> String {
        DifficultyRanker.makeSession(habitName: "", rankedHabits: []).generateRank()
    }

    static func hasComparableHabits(rankedHabitCount: Int, excludeHabitId: String?) -> Bool {
        rankedHabitCount > 0
    }

    static func shouldOpenDifficultyRanker(isFirstHabit: Bool, hasComparableHabits: Bool) -> Bool {
        !isFirstHabit && hasComparableHabits
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        difficultyRank: String?,
        frequency: Double?
    ) -> [PillItem] {
        let freqLabel = FrequencyConversion.formatSummary(frequency) ?? "Frequency"
        return [
            PillItem(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            PillItem(id: "difficulty", label: "Difficulty", icon: "chart.bar", isSet: difficultyRank != nil),
            PillItem(id: "frequency", label: freqLabel, icon: "clock", isSet: frequency != nil),
        ]
    }

    private func buildPills() -> [PillItem] {
        var pills = Self.buildPillData(
            hasTagsApplied: !habitTags.isEmpty,
            difficultyRank: difficultyRank,
            frequency: frequency
        )

        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "difficulty": {
                if Self.shouldOpenDifficultyRanker(isFirstHabit: isFirstHabit, hasComparableHabits: hasComparableHabits) {
                    showingDifficulty = true
                } else {
                    showingFirstHabitAlert = true
                }
            },
            "frequency": { showingFrequency = true },
        ]

        for index in pills.indices {
            pills[index].action = actions[pills[index].id]
            if pills[index].id == "difficulty" {
                pills[index].animating = difficultyPillAnimating
            }
        }

        return pills
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            name = prefill.name
            description = prefill.description
            frequency = prefill.frequency
            difficultyRank = prefill.difficultyRank
        } else if case .change(let habit) = mode {
            name = habit.name
            description = habit.description
            frequency = habit.frequency
            difficultyRank = habit.difficultyRank
            habitId = habit.id
        }

        if isFirstHabit && difficultyRank == nil {
            difficultyRank = Self.defaultDifficultyRankForFirstHabit()
        }

        hasAppliedInitialLoad = true

        if surface == .nameDescription {
            focusedEntryField = activeEntryField
        }

        let focus = initialFocus
        guard let focus, !focus.isNameDescription else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            switch focus {
            case .name, .description:
                break
            case .frequency:
                showingFrequency = true
            case .difficulty:
                showingDifficulty = true
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSave() {
        guard !mode.isNew, hasAppliedInitialLoad else { return }
        persistHabit()
    }

    private func persistHabit() {
        if case .new = mode {
            habitStore.addHabit(
                id: habitId,
                name: name,
                description: description,
                frequency: frequency,
                difficultyRank: difficultyRank
            )
        } else {
            habitStore.updateHabit(
                id: habitId,
                name: Self.nameForAutoSave(name),
                description: description,
                frequency: .some(frequency),
                difficultyRank: .some(difficultyRank)
            )
        }
    }

    private static var minimumDescriptionHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        return (lineHeight * 3) + 20
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ContentHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}

// UIKit-backed single-line field so the keyboard can become first responder as
// soon as the modal enters the hierarchy. That is the closest SwiftUI/iOS
// equivalent to mounting an <input autoFocus /> inside an animating React modal.
private struct AutoFocusingTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.autocorrectionType = .default
        textField.returnKeyType = .done
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutoFocusingTextField

        init(_ parent: AutoFocusingTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFirstResponder = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFirstResponder = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// UIKit-backed multiline field with dynamic height.
// User behaviour:
// - starts at roughly 3 lines tall
// - grows as the user types more description
// - stops growing once the outer modal hits its max height, after which the
//   modal scrolls instead of the text view going full screen.
private struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    @Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if context.coordinator.placeholderLabel.superview == nil {
            uiView.addSubview(context.coordinator.placeholderLabel)
        }

        context.coordinator.placeholderLabel.text = placeholder
        context.coordinator.placeholderLabel.font = uiView.font
        context.coordinator.placeholderLabel.textColor = .placeholderText
        context.coordinator.placeholderLabel.isHidden = !text.isEmpty
        context.coordinator.placeholderLabel.frame = CGRect(
            x: 0,
            y: 8,
            width: uiView.bounds.width,
            height: 20
        )

        let fittingSize = CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)
        let targetHeight = max(minHeight, uiView.sizeThatFits(fittingSize).height)

        if abs(measuredHeight - targetHeight) > 0.5 {
            DispatchQueue.main.async {
                measuredHeight = targetHeight
            }
        }

        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView
        let placeholderLabel = UILabel()

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel.isHidden = !textView.text.isEmpty

            let fittingSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            parent.measuredHeight = max(parent.minHeight, textView.sizeThatFits(fittingSize).height)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFirstResponder = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFirstResponder = false
        }
    }
}

#Preview("Habit Form Modal") {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()

        HabitFormModal(
            mode: .new,
            initialFocus: .name,
            prefill: nil,
            onDiscard: { _ in },
            onDelete: nil,
            onClose: {}
        )
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
    }
}
