import type { Habit } from "./habit";
import { tradeStore } from "./store/tradeStore";
import { balanceStore } from "./store/balanceStore";
import { calculateReward, getCurrentTimeBucket } from "./rewardCalculation";

/**
 * Complete a habit and award the calculated soy reward.
 *
 * This function:
 * 1. Calculates the reward based on difficulty, habit frequency, etc.
 * 2. Creates a trade record (locally stored, synced to server)
 * 3. Updates the local balance
 *
 * @param habit - The habit to complete
 * @param allHabits - All user's habits (for difficulty ranking)
 * @param userId - The current user's ID
 * @param onComplete - Optional callback after completion (e.g., to trigger sync)
 * @returns The amount of soy awarded
 */
export async function completeHabit(
  habit: Habit,
  allHabits: Habit[],
  userId: string,
  onComplete?: () => void,
): Promise<number> {
  // Get habit completion count for the last 7 days (for habit multiplier)
  const completionsInPeriod = tradeStore.getTradesInPeriod(userId, habit.id, 7);

  // Calculate the reward amount
  const timeBucket = getCurrentTimeBucket();
  const amount = calculateReward(
    habit,
    allHabits,
    completionsInPeriod,
    timeBucket,
  );

  // Create the trade record
  await tradeStore.createTrade(userId, {
    habit_id: habit.id,
    amount,
  });

  // Update local balance
  await balanceStore.addSoy(amount);

  // Notify caller to trigger sync
  if (onComplete) {
    onComplete();
  }

  return amount;
}
