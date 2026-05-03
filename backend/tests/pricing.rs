use tofustash_backend::database::HabitDifficultyTier;
use tofustash_backend::pricing::calculate_task_reward;

#[test]
fn task_reward_uses_doubled_commitment_curve() {
    let low = calculate_task_reward(Some(HabitDifficultyTier::Medium), None, Some(1));
    let mid = calculate_task_reward(Some(HabitDifficultyTier::Medium), None, Some(3));
    let high = calculate_task_reward(Some(HabitDifficultyTier::Medium), None, Some(5));

    assert_eq!(low, 200);
    assert_eq!(mid, 320);
    assert_eq!(high, 500);
}

#[test]
fn task_reward_defaults_to_lowest_commitment_when_missing() {
    assert_eq!(
        calculate_task_reward(Some(HabitDifficultyTier::Medium), None, None),
        200
    );
}
