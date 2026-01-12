import { Task, isHabit } from "./task";
import { taskStore } from "./store/taskStore";
import { tradeStore } from "./store/tradeStore";
import { balanceStore } from "./store/balanceStore";
import { calculateReward, getCurrentTimeBucket } from "./rewardCalculation";

/**
 * Complete a task and award the calculated soy reward.
 *
 * This function:
 * 1. Calculates the reward based on difficulty, due date, habit frequency, etc.
 * 2. Creates a trade record (locally stored, synced to server)
 * 3. Updates the local balance
 * 4. For non-habits: sets completed_at to mark the task as done
 * 5. For habits: leaves the task in the list for future completions
 *
 * @param task - The task to complete
 * @param allTasks - All user's tasks (for difficulty ranking)
 * @param userId - The current user's ID
 * @param onComplete - Optional callback after completion (e.g., to trigger sync)
 * @returns The amount of soy awarded
 */
export async function completeTask(
  task: Task,
  allTasks: Task[],
  userId: string,
  onComplete?: () => void,
): Promise<number> {
  // Get habit completion count for the last 7 days (for habit multiplier)
  const completionsInPeriod = isHabit(task)
    ? tradeStore.getTradesInPeriod(userId, task.id, 7)
    : 0;

  // Calculate the reward amount
  const timeBucket = getCurrentTimeBucket();
  const amount = calculateReward(
    task,
    allTasks,
    completionsInPeriod,
    timeBucket,
  );

  // Create the trade record
  await tradeStore.createTrade(userId, {
    task_id: task.id,
    amount,
  });

  // Update local balance
  await balanceStore.addSoy(amount);

  // For non-habits, mark the task as completed
  if (!isHabit(task)) {
    const now = new Date().toISOString();
    await taskStore.updateTask(task.id, { completed_at: now });
  }

  // Notify caller to trigger sync
  if (onComplete) {
    onComplete();
  }

  return amount;
}
