import type { Reward } from "./reward";
import { tradeStore } from "./store/tradeStore";
import { balanceStore } from "./store/balanceStore";
import { calculatePrice, getCurrentTimeBucket } from "./rewardPriceCalculation";

/**
 * Purchase a reward and deduct the calculated tofu price.
 *
 * This function:
 * 1. Calculates the price based on damage, purchase frequency, etc.
 * 2. Checks if user has enough balance
 * 3. Creates a trade record (locally stored, synced to server)
 * 4. Updates the local balance
 *
 * @param reward - The reward to purchase
 * @param allRewards - All user's rewards (for damage ranking)
 * @param userId - The current user's ID
 * @param onComplete - Optional callback after completion (e.g., to trigger sync)
 * @returns The amount of tofu spent (negative), or throws if insufficient balance
 */
export async function purchaseReward(
  reward: Reward,
  allRewards: Reward[],
  userId: string,
  onComplete?: () => void,
): Promise<number> {
  // Get reward purchase count for the last 60 days (for frequency multiplier)
  const purchasesInPeriod = tradeStore.getRewardPurchasesInPeriod(userId, reward.id, 60);

  // Calculate the price (positive value)
  const timeBucket = getCurrentTimeBucket();
  const price = calculatePrice(
    reward,
    allRewards,
    purchasesInPeriod,
    timeBucket,
  );

  // Check if user has enough balance
  const currentBalance = balanceStore.getBalance();
  if (currentBalance < price) {
    throw new Error(`Insufficient balance. Need ${price} tofu but only have ${currentBalance}.`);
  }

  // Create the trade record with negative amount (spending tofu)
  await tradeStore.createTrade(userId, {
    reward_id: reward.id,
    amount: -price, // Negative because we're spending
  });

  // Update local balance (subtract the price)
  await balanceStore.subtractTofu(price);

  // Notify caller to trigger sync
  if (onComplete) {
    onComplete();
  }

  return price;
}
