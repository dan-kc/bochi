import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import { calculateReward } from "./rewardCalculation";
import type { Habit } from "./habit";
import { tradeStore } from "./store/tradeStore";
import { useAuth } from "./AuthContext";
import { LOCAL_USER_ID } from "./store";

/** Time bucket size in milliseconds (30 minutes) */
const TIME_BUCKET_MS = 30 * 60 * 1000;

interface PriceData {
  current: number;
  previous: number;
}

interface PriceUpdateContextType {
  /** Map of habit ID to price data */
  prices: Record<string, PriceData>;
  /** Current time bucket */
  timeBucket: number;
  /** Seconds until next price update */
  secondsUntilUpdate: number;
  /** Update prices for given habits */
  updatePrices: (habits: Habit[]) => void;
}

const PriceUpdateContext = createContext<PriceUpdateContextType | null>(null);

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

export function PriceUpdateProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const userId = user?.id ?? LOCAL_USER_ID;

  const [prices, setPrices] = useState<Record<string, PriceData>>({});
  const [timeBucket, setTimeBucket] = useState(() => getAlignedTimeBucket());
  const [secondsUntilUpdate, setSecondsUntilUpdate] = useState(() =>
    Math.ceil(getMsUntilNextHalfHour() / 1000)
  );
  const [allHabits, setAllHabits] = useState<Habit[]>([]);

  // Calculate prices for habits, comparing current bucket against previous bucket
  const calculatePrices = useCallback(
    (habits: Habit[], bucket: number) => {
      const newPrices: Record<string, PriceData> = {};
      const previousBucket = bucket - 1;

      for (const habit of habits) {
        // Get real completion count from trade store (last 7 days)
        const completionsInPeriod = tradeStore.getTradesInPeriod(userId, habit.id, 7);

        // Calculate current price
        const current = calculateReward(
          habit,
          habits,
          completionsInPeriod,
          bucket,
        );

        // Calculate what the price was in the previous time bucket
        const previous = calculateReward(
          habit,
          habits,
          completionsInPeriod,
          previousBucket,
        );

        newPrices[habit.id] = {
          current,
          previous,
        };
      }

      return newPrices;
    },
    [userId]
  );

  // Update prices when habits change or time bucket changes
  const updatePrices = useCallback(
    (habits: Habit[]) => {
      setAllHabits(habits);
      setPrices(calculatePrices(habits, timeBucket));
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
        setPrices(calculatePrices(allHabits, newBucket));
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [timeBucket, allHabits, calculatePrices]);

  return (
    <PriceUpdateContext.Provider
      value={{
        prices,
        timeBucket,
        secondsUntilUpdate,
        updatePrices,
      }}
    >
      {children}
    </PriceUpdateContext.Provider>
  );
}

export function usePriceUpdate(): PriceUpdateContextType {
  const context = useContext(PriceUpdateContext);
  if (!context) {
    throw new Error("usePriceUpdate must be used within a PriceUpdateProvider");
  }
  return context;
}

export function usePriceUpdateOptional(): PriceUpdateContextType | null {
  return useContext(PriceUpdateContext);
}

/**
 * Format seconds as MM:SS countdown string.
 */
export function formatCountdown(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}
