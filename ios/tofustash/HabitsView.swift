import SwiftUI

struct HabitsView: View {
    // Inject the HabitStore from the environment — like useContext(HabitStoreContext).
    // The store is provided by `.environment(habitStore)` in tofustashApp.swift.
    @Environment(HabitStore.self) private var habitStore

    // @State drives the sheet presentation. When `showingForm` becomes true,
    // the .sheet modifier presents HabitFormView modally. Like controlling a
    // modal with `const [showModal, setShowModal] = useState(false)` in React.
    @State private var showingForm = false

    var body: some View {
        NavigationStack {
            // ZStack layers views on top of each other (z-axis).
            // Like position: relative on a container with position: absolute children.
            // We use it to overlay the FAB on top of the list/empty state.
            ZStack {
                if habitStore.activeHabits.isEmpty {
                    // ContentUnavailableView is a built-in SwiftUI component for empty states.
                    // It shows a centered icon, title, and description — standard iOS pattern.
                    // No React equivalent — you'd build this yourself with styled divs.
                    ContentUnavailableView(
                        "No Habits Yet",
                        systemImage: "checkmark.circle",
                        description: Text("Tap + to create your first habit.")
                    )
                } else {
                    // List is like a FlatList in React Native — a scrollable,
                    // recycling list that efficiently renders many items.
                    // Because Habit conforms to Identifiable, List automatically
                    // uses `habit.id` as the key (no need for `id:` parameter).
                    List(habitStore.activeHabits) { habit in
                        // VStack stacks views vertically — like flexDirection: "column".
                        // `alignment: .leading` is like alignItems: "flex-start".
                        VStack(alignment: .leading, spacing: 4) {
                            Text(habit.name)
                                // .font(.body) is the default, but explicit here for clarity.
                                // System fonts in SwiftUI are like using rem-based font sizes.
                                .font(.body)

                            if !habit.description.isEmpty {
                                Text(habit.description)
                                    // .font(.subheadline) is a smaller system font.
                                    .font(.subheadline)
                                    // .foregroundStyle(.secondary) makes text gray —
                                    // like `color: "gray"` but adapts to dark mode automatically.
                                    .foregroundStyle(.secondary)
                                    // .lineLimit(1) truncates with "..." after 1 line,
                                    // like numberOfLines={1} in React Native.
                                    .lineLimit(1)
                            }

                            if let frequency = habit.frequency {
                                Text("\(frequency, specifier: "%.1f")x per day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Habits")
            // .overlay positions a view on top of the current view.
            // `alignment: .bottomTrailing` places it at the bottom-right corner —
            // like position: absolute; bottom: 0; right: 0 in CSS.
            .overlay(alignment: .bottomTrailing) {
                // The floating action button (FAB). SwiftUI doesn't have a built-in
                // FAB component, so we build one with a styled Button.
                Button {
                    showingForm = true
                } label: {
                    // Image(systemName:) loads an SF Symbol — Apple's built-in icon set.
                    // Like using a Material Icon in React: <Icon name="add" />.
                    // "plus" is the SF Symbol name for a + icon.
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        // .frame sets explicit width/height — like setting width/height in CSS.
                        .frame(width: 56, height: 56)
                        // .background(.blue, in: .circle) draws a blue circle behind the icon.
                        // Like backgroundColor: "blue", borderRadius: "50%" in CSS.
                        .background(.blue, in: .circle)
                        .shadow(radius: 4)
                }
                // Padding pushes the button inward from the edges.
                .padding()
            }
            // .sheet presents a modal view that slides up from the bottom.
            // `isPresented: $showingForm` binds to our @State — when showingForm
            // becomes true, the sheet appears; when dismissed, it's set back to false.
            // Like {showModal && <Modal onClose={() => setShowModal(false)}><Form/></Modal>}
            .sheet(isPresented: $showingForm) {
                HabitFormView()
            }
        }
    }
}

#Preview {
    HabitsView()
        .environment(HabitStore())
}
