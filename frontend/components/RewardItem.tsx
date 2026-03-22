import { Text, Pressable } from "react-native";
import type { Reward } from "@/lib/reward";
import { useRewardPriceUpdateOptional } from "@/lib/RewardPriceUpdateContext";
import type { DisplayMode } from "@/lib/rewardSorting";
import { formatShortDate } from "@/lib/rewardSorting";
import { useTagsForReward } from "@/lib/store/hooks";
import { ListItemCard } from "./ListItemCard";
import { TagRow } from "./TagRow";

interface RewardItemProps {
  reward: Reward;
  onPress: (reward: Reward) => void;
  displayMode?: DisplayMode;
  onSetRank?: (reward: Reward) => void;
}

function InfoDisplay({
  reward,
  displayMode,
}: {
  reward: Reward;
  displayMode: DisplayMode;
}) {
  const priceContext = useRewardPriceUpdateOptional();

  if (displayMode === "price") {
    if (!priceContext) return null;
    const priceData = priceContext.prices[reward.id];
    if (!priceData) return null;

    return (
      <Text className="text-base font-bold text-accent">
        {priceData.current} tofu
      </Text>
    );
  }

  if (displayMode === "frequency") {
    if (reward.max_daily_frequency == null) {
      return (
        <Text className="text-sm text-muted">no limit</Text>
      );
    }
    return (
      <Text className="text-sm text-accent-secondary">
        {reward.max_daily_frequency} max/day
      </Text>
    );
  }

  if (displayMode === "created_at") {
    return (
      <Text className="text-sm text-muted">
        {formatShortDate(reward.created_at)}
      </Text>
    );
  }

  if (displayMode === "damage") {
    if (reward.damage_rank == null) {
      return (
        <Text className="text-sm text-muted">not set</Text>
      );
    }
    return (
      <Text className="text-sm font-bold text-accent font-mono">
        {reward.damage_rank}
      </Text>
    );
  }

  return null;
}

function formatFrequency(frequency: number | null): string | null {
  if (frequency == null) return null;
  return `${frequency}x max/day`;
}

export function RewardItem({
  reward,
  onPress,
  displayMode = "price",
  onSetRank,
}: RewardItemProps) {
  const tags = useTagsForReward(reward.id);

  const bottomRight = reward.damage_rank == null && displayMode === "price" && onSetRank ? (
    <Pressable onPress={() => onSetRank(reward)}>
      <Text className="text-sm font-medium text-accent">Set Damage</Text>
    </Pressable>
  ) : (
    <InfoDisplay reward={reward} displayMode={displayMode} />
  );

  return (
    <ListItemCard
      name={reward.name}
      description={reward.description}
      subtitle={formatFrequency(reward.max_daily_frequency)}
      tags={<TagRow tags={tags} />}
      bottomRight={bottomRight}
      onPress={() => onPress(reward)}
    />
  );

  if (!onPurchase) return content;

  return (
    <SwipeableRow
      onAction={handleAction}
      actionColor="#f54900"
      actionIcon="cart"
    >
      {content}
    </SwipeableRow>
  );
}
