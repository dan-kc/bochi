import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import type { Reward, RewardInput } from "./reward";
import { useAuth } from "./AuthContext";
import { useSyncOptional } from "./sync";
import { useRewards as useRewardsFromStore, useRewardActions, useRewardsSortedByDamage, LOCAL_USER_ID } from "./store";
import { purchaseReward as purchaseRewardAction } from "./purchaseReward";

interface RewardContextType {
  rewards: Reward[];
  rankedRewards: Reward[];
  selectedReward: Reward | null;
  isEditing: boolean;
  userId: string;
  createReward: (input: RewardInput) => Promise<Reward>;
  updateReward: (id: string, input: Partial<RewardInput>) => Promise<Reward | null>;
  deleteReward: (id: string) => Promise<boolean>;
  purchaseReward: (reward: Reward) => Promise<number>;
  selectReward: (reward: Reward | null) => void;
  setIsEditing: (editing: boolean) => void;
}

const RewardContext = createContext<RewardContextType | null>(null);

export function RewardProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const sync = useSyncOptional();
  const actions = useRewardActions();

  // Use user ID from auth, fallback to local-user for offline mode
  const userId = user?.id ?? LOCAL_USER_ID;

  // Get rewards from reactive store (fine-grained subscription)
  const rewards = useRewardsFromStore(userId);
  const rankedRewards = useRewardsSortedByDamage(userId);

  // UI state (not persisted)
  const [selectedReward, setSelectedReward] = useState<Reward | null>(null);
  const [isEditing, setIsEditing] = useState(false);

  const createReward = useCallback(
    async (input: RewardInput): Promise<Reward> => {
      const reward = await actions.createReward(userId, input);
      // Notify sync service of change
      sync?.notifyChange();
      return reward;
    },
    [userId, sync, actions],
  );

  const updateReward = useCallback(
    async (id: string, input: Partial<RewardInput>): Promise<Reward | null> => {
      const updated = await actions.updateReward(id, input);
      if (updated) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return updated;
    },
    [sync, actions],
  );

  const deleteReward = useCallback(
    async (id: string): Promise<boolean> => {
      const success = await actions.deleteReward(id);
      if (success) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return success;
    },
    [sync, actions],
  );

  const purchaseReward = useCallback(
    async (reward: Reward): Promise<number> => {
      const price = await purchaseRewardAction(reward, rewards, userId, () => {
        sync?.notifyChange();
      });
      return price;
    },
    [rewards, userId, sync],
  );

  const selectReward = useCallback((reward: Reward | null) => {
    setSelectedReward(reward);
  }, []);

  return (
    <RewardContext.Provider
      value={{
        rewards,
        rankedRewards,
        selectedReward,
        isEditing,
        userId,
        createReward,
        updateReward,
        deleteReward,
        purchaseReward,
        selectReward,
        setIsEditing,
      }}
    >
      {children}
    </RewardContext.Provider>
  );
}

export function useRewardsContext(): RewardContextType {
  const context = useContext(RewardContext);
  if (!context) {
    throw new Error("useRewardsContext must be used within a RewardProvider");
  }
  return context;
}
