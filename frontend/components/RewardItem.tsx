import { View, Text, Pressable } from "react-native";
import type { Reward } from "@/lib/reward";
import { useRewardPriceUpdateOptional } from "@/lib/RewardPriceUpdateContext";
import type { DisplayMode } from "@/lib/rewardSorting";
import { formatShortDate } from "@/lib/rewardSorting";
import { RewardTagChips } from "./RewardTagChips";

interface RewardItemProps {
  reward: Reward;
  onPress: (reward: Reward) => void;
  onSetDamage?: (reward: Reward) => void;
  isDamageView?: boolean;
  displayMode?: DisplayMode;
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
      <Text className="text-sm font-bold text-accent">
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

export function RewardItem({
  reward,
  onPress,
  onSetDamage,
  isDamageView,
  displayMode = "price",
}: RewardItemProps) {
  const hasDamageRank = reward.damage_rank != null;
  const isUnrankedInDamageView = isDamageView && !hasDamageRank;

  return (
    <Pressable
      onPress={() => onPress(reward)}
      className="border-b border-border py-4 px-2"
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <View className="flex-row justify-between items-start">
            <Text className="text-lg font-semibold text-foreground mb-1 flex-1">
              {reward.name}
            </Text>
            <View className="flex-row items-center gap-2 ml-2">
              <InfoDisplay reward={reward} displayMode={displayMode} />
              {isUnrankedInDamageView && (
                <Text className="text-muted text-xs font-medium">
                  Unranked
                </Text>
              )}
            </View>
          </View>
          {reward.description ? (
            <Text
              className="text-muted text-sm mb-1"
              numberOfLines={2}
              ellipsizeMode="tail"
            >
              {reward.description}
            </Text>
          ) : null}
          <RewardTagChips rewardId={reward.id} />
          <View className="flex-row flex-wrap gap-2 mt-2">
            {reward.max_daily_frequency !== null && (
              <Text className="text-accent-secondary text-xs">
                {reward.max_daily_frequency}x max/day
              </Text>
            )}
            {hasDamageRank && isDamageView && (
              <Text className="text-accent text-xs font-mono">
                {reward.damage_rank}
              </Text>
            )}
            {!hasDamageRank && onSetDamage && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onSetDamage(reward);
                }}
              >
                <Text className="text-accent text-xs">Set Damage</Text>
              </Pressable>
            )}
          </View>
        </View>
      )}
    </Pressable>
  );
}
