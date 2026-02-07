import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import { calculatePrice } from "./rewardPriceCalculation";
import type { Reward } from "./reward";
import { tradeStore } from "./store/tradeStore";
import { useAuth } from "./AuthContext";
import { LOCAL_USER_ID } from "./store";

/** Time bucket size in milliseconds (30 minutes) */
const TIME_BUCKET_MS = 30 * 60 * 1000;

/** Period for frequency calculation (60 days = ~2 months) */
const FREQUENCY_PERIOD_DAYS = 60;

interface PriceData {
  current: number;
  previous: number;
}

interface RewardPriceUpdateContextType {
  /** Map of reward ID to price data */
  prices: Record<string, PriceData>;
  /** Current time bucket */
  timeBucket: number;
  /** Seconds until next price update */
  secondsUntilUpdate: number;
  /** Update prices for given rewards */
  updatePrices: (rewards: Reward[]) => void;
}

const RewardPriceUpdateContext = createContext<RewardPriceUpdateContextType | null>(null);

/**
 * Get milliseconds until the next half-hour mark (00 or 30 minutes).
 */
function getMsUntilNextHalfHour(now: Date = new Date()): number {
  const minutes = now.getMinutes();
  const seconds = now.getSeconds();
  const ms = now.getMilliseconds();

  // Calculate minutes until next 00 or 30
  const minutesUntil = minutes < 30 ? 30 - minutes : 60 - minutes;

  // Convert to ms and subtract current seconds/ms
  return (minutesUntil * 60 - seconds) * 1000 - ms;
}

/**
 * Get the time bucket aligned to half-hour marks.
 * This ensures all clients update at exactly :00 and :30.
 */
function getAlignedTimeBucket(now: Date = new Date()): number {
  // Floor to the nearest half hour
  const ms = now.getTime();
  return Math.floor(ms / TIME_BUCKET_MS);
}

export function RewardPriceUpdateProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const userId = user?.id ?? LOCAL_USER_ID;

  const [prices, setPrices] = useState<Record<string, PriceData>>({});
  const [timeBucket, setTimeBucket] = useState(() => getAlignedTimeBucket());
  const [secondsUntilUpdate, setSecondsUntilUpdate] = useState(() =>
    Math.ceil(getMsUntilNextHalfHour() / 1000)
  );
  const [allRewards, setAllRewards] = useState<Reward[]>([]);

  // Calculate prices for rewards, comparing current bucket against previous bucket
  const calculatePrices = useCallback(
    (rewards: Reward[], bucket: number) => {
      const newPrices: Record<string, PriceData> = {};
      const previousBucket = bucket - 1;

      for (const reward of rewards) {
        // Get real purchase count from trade store (last 60 days for rewards)
        const purchasesInPeriod = tradeStore.getRewardPurchasesInPeriod(
          userId,
          reward.id,
          FREQUENCY_PERIOD_DAYS
        );

        // Calculate current price
        const current = calculatePrice(
          reward,
          rewards,
          purchasesInPeriod,
          bucket,
        );

        // Calculate what the price was in the previous time bucket
        const previous = calculatePrice(
          reward,
          rewards,
          purchasesInPeriod,
          previousBucket,
        );

        newPrices[reward.id] = {
          current,
          previous,
        };
      }

      return newPrices;
    },
    [userId]
  );

  // Update prices when rewards change or time bucket changes
  const updatePrices = useCallback(
    (rewards: Reward[]) => {
      setAllRewards(rewards);
      setPrices(calculatePrices(rewards, timeBucket));
    },
    [timeBucket, calculatePrices]
  );

  // Set up countdown timer (updates every second)
  useEffect(() => {
    const interval = setInterval(() => {
      const msUntil = getMsUntilNextHalfHour();
      const secondsUntil = Math.ceil(msUntil / 1000);
      setSecondsUntilUpdate(secondsUntil);

      // Check if we've crossed into a new time bucket
      const newBucket = getAlignedTimeBucket();
      if (newBucket !== timeBucket) {
        setTimeBucket(newBucket);
        // Recalculate prices with new bucket
        setPrices(calculatePrices(allRewards, newBucket));
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [timeBucket, allRewards, calculatePrices]);

  return (
    <RewardPriceUpdateContext.Provider
      value={{
        prices,
        timeBucket,
        secondsUntilUpdate,
        updatePrices,
      }}
    >
      {children}
    </RewardPriceUpdateContext.Provider>
  );
}

export function useRewardPriceUpdate(): RewardPriceUpdateContextType {
  const context = useContext(RewardPriceUpdateContext);
  if (!context) {
    throw new Error("useRewardPriceUpdate must be used within a RewardPriceUpdateProvider");
  }
  return context;
}

export function useRewardPriceUpdateOptional(): RewardPriceUpdateContextType | null {
  return useContext(RewardPriceUpdateContext);
}
