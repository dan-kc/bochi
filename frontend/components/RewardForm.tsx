import type { Reward, RewardInput } from "@/lib/reward";
import { useRewardPriceUpdateOptional } from "@/lib/RewardPriceUpdateContext";
import { useTagsForReward, useTagActions, useRewardTagActions } from "@/lib/store/hooks";
import { ChangeForm, type ChangeFormConfig, type ChangeFormEntity } from "./ChangeForm";

interface RewardFormProps {
  reward?: Reward | null;
  userId: string;
  onSave: (input: RewardInput) => Promise<void>;
  onClose: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
  onPurchase?: (reward: Reward) => Promise<void>;
}

const REWARD_CONFIG: ChangeFormConfig = {
  entityType: "reward",
  entityLabel: "Reward",
  frequencyLabel: "Max Frequency",
  frequencyField: "max_daily_frequency",
  frequencyPrefix: "max",
  rankLabel: "Damage",
  actionLabel: "Trade",
};

export function RewardForm({ reward, userId, onSave, onClose, onDelete, onRerank, onPurchase }: RewardFormProps) {
  const rewardTags = useTagsForReward(reward?.id ?? "");
  const { updateTag } = useTagActions();
  const { addTagToReward, removeTagFromReward } = useRewardTagActions();
  const priceContext = useRewardPriceUpdateOptional();
  const tradeAmount = reward ? (priceContext?.prices[reward.id]?.current ?? null) : null;

  return (
    <ChangeForm
      config={REWARD_CONFIG}
      entity={reward}
      userId={userId}
      tags={rewardTags}
      tradeAmount={tradeAmount != null ? -tradeAmount : null}
      onSave={(input) => onSave(input as unknown as RewardInput)}
      onClose={onClose}
      onDelete={onDelete}
      onRerank={onRerank}
      onAction={onPurchase ? (entity) => onPurchase(entity as unknown as Reward) : undefined}
      tagActions={{ addTag: addTagToReward, removeTag: removeTagFromReward }}
      updateTag={updateTag}
    />
  );
}
