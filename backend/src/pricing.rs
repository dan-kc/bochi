use crate::database::HabitDifficultyTier;

const TASK_BASE_REWARD: f64 = 200.0;
const MAX_DURATION_SECONDS: f64 = 43_200.0;
const DURATION_INFLUENCE: f64 = 0.35;

pub fn calculate_task_reward(
    difficulty_tier: Option<HabitDifficultyTier>,
    duration_seconds: Option<i32>,
    commitment: Option<i16>,
) -> i32 {
    let reward = TASK_BASE_REWARD
        * difficulty_multiplier(difficulty_tier)
        * duration_multiplier(duration_seconds)
        * commitment_multiplier(commitment);

    reward.round() as i32
}

fn difficulty_multiplier(difficulty_tier: Option<HabitDifficultyTier>) -> f64 {
    match difficulty_tier.unwrap_or(HabitDifficultyTier::Trivial) {
        HabitDifficultyTier::Trivial => 0.2,
        HabitDifficultyTier::Light => 0.6,
        HabitDifficultyTier::Medium => 1.0,
        HabitDifficultyTier::Hard => 1.4,
        HabitDifficultyTier::Extreme => 2.0,
    }
}

fn duration_multiplier(duration_seconds: Option<i32>) -> f64 {
    let Some(duration_seconds) = duration_seconds else {
        return 1.0;
    };
    if duration_seconds <= 0 {
        return 1.0;
    }

    let normalized = (f64::from(duration_seconds)).ln_1p() / MAX_DURATION_SECONDS.ln_1p();
    1.0 + (normalized * DURATION_INFLUENCE)
}

fn commitment_multiplier(commitment: Option<i16>) -> f64 {
    match commitment.unwrap_or(1) {
        1 => 1.0,
        2 => 1.3,
        3 => 1.6,
        4 => 2.0,
        5 => 2.5,
        _ => 1.0,
    }
}
