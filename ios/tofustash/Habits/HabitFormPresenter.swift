import Observation

// App-level presenter for the habit form flow.
// Keeping this above the tab content lets the modal sit over the entire app,
// so the tab bar and floating + button stay behind the keyboard instead of
// joining the same layout pass as the focused text input.
@Observable
@MainActor
final class HabitFormPresenter {
    enum Route {
        case new(
            prefill: HabitFormSnapshot?,
            onDiscard: ((HabitFormSnapshot) -> Void)?
        )
        case change(
            habit: Habit,
            focus: HabitFormFocus?,
            onDelete: ((Habit) -> Void)?
        )
    }

    var route: Route? = nil

    func presentNew(
        prefill: HabitFormSnapshot? = nil,
        onDiscard: ((HabitFormSnapshot) -> Void)? = nil
    ) {
        route = .new(prefill: prefill, onDiscard: onDiscard)
    }

    func presentChange(
        habit: Habit,
        focus: HabitFormFocus? = nil,
        onDelete: ((Habit) -> Void)? = nil
    ) {
        route = .change(habit: habit, focus: focus, onDelete: onDelete)
    }

    func dismiss() {
        route = nil
    }
}
