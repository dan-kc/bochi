import { useCallback } from "react";
import { Text, Pressable, StyleSheet } from "react-native";
import type { Reward } from "@/lib/reward";
import { useRewardPriceUpdateOptional } from "@/lib/RewardPriceUpdateContext";
import type { DisplayMode } from "@/lib/rewardSorting";
import { formatShortDate } from "@/lib/rewardSorting";
import { useTagsForReward } from "@/lib/store/hooks";
import { ListItemCard } from "./ListItemCard";
import { TagRow } from "./TagRow";
import { SwipeableRow } from "./SwipeableRow";
import { useColors, fontSize, fontWeight } from "@/lib/theme";

interface RewardItemProps {
  reward: Reward;
  onPress: (reward: Reward) => void;
  onPurchase?: (reward: Reward) => void;
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
  const colors = useColors();

  if (displayMode === "price") {
    if (!priceContext) return null;
    const priceData = priceContext.prices[reward.id];
    if (!priceData) return null;

    return (
      <Text style={[styles.priceText, { color: colors.accent }]}>
        {priceData.current} tofu
      </Text>
    );
  }

  if (displayMode === "frequency") {
    if (reward.max_daily_frequency == null) {
      return (
        <Text style={[styles.smallText, { color: colors.muted }]}>no limit</Text>
      );
    }
    return (
      <Text style={[styles.smallText, { color: colors.accentSecondary }]}>
        {reward.max_daily_frequency} max/day
      </Text>
    );
  }

  if (displayMode === "created_at") {
    return (
      <Text style={[styles.smallText, { color: colors.muted }]}>
        {formatShortDate(reward.created_at)}
      </Text>
    );
  }

  if (displayMode === "damage") {
    if (reward.damage_rank == null) {
      return (
        <Text style={[styles.smallText, { color: colors.muted }]}>not set</Text>
      );
    }
    return (
      <Text style={[styles.damageText, { color: colors.accent }]}>
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
  onPurchase,
  displayMode = "price",
  onSetRank,
}: RewardItemProps) {
  const tags = useTagsForReward(reward.id);
  const colors = useColors();

  const handlePurchase = useCallback(() => {
    onPurchase?.(reward);
  }, [onPurchase, reward]);

  const bottomRight = reward.damage_rank == null && displayMode === "price" && onSetRank ? (
    <Pressable onPress={() => onSetRank(reward)}>
      <Text style={[styles.setDamageText, { color: colors.accent }]}>Set Damage</Text>
    </Pressable>
  ) : (
    <InfoDisplay reward={reward} displayMode={displayMode} />
  );

  const content = (
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
      onAction={handlePurchase}
      actionColor={colors.accent}
      actionIcon="cart"
    >
      {content}
    </SwipeableRow>
  );
}

const styles = StyleSheet.create({
  priceText: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.bold,
  },
  smallText: {
    fontSize: fontSize.sm,
  },
  damageText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.bold,
    fontFamily: "monospace",
  },
  setDamageText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
});
