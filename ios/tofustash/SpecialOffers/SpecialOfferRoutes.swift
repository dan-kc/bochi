import Foundation

struct HabitTradeRoute: Identifiable {
    let habit: Habit
    let resolvedSpecialOffer: SpecialOffer?

    var id: RecordID { habit.id }
}

struct RewardPurchaseRoute: Identifiable {
    let reward: Reward
    let resolvedSpecialOffer: SpecialOffer?

    var id: RecordID { reward.id }
}
