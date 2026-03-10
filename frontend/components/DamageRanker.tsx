import { useState, useEffect, useCallback, useRef } from "react";
import { View, Text, Pressable, ScrollView } from "react-native";
import type { Reward } from "@/lib/reward";
import { generateKeyBetween } from "@/lib/fractionalIndex";

interface DamageRankerProps {
  reward: Reward;
  existingRewards: Reward[]; // Already-ranked rewards, sorted by damage (highest first)
  onComplete: (rank: string) => void;
  onSkip: () => void;
}

type RankingState = "comparing" | "complete";

export function DamageRanker({
  reward,
  existingRewards,
  onComplete,
  onSkip,
}: DamageRankerProps) {
  const [low, setLow] = useState(0);
  const [high, setHigh] = useState(existingRewards.length);
  const [state, setState] = useState<RankingState>("comparing");
  const [comparisonCount, setComparisonCount] = useState(0);
  const hasCompletedRef = useRef(false);

  // Calculate the midpoint for binary search
  const mid = Math.floor((low + high) / 2);
  const comparisonReward = existingRewards[mid];

  // Check if we've found the insertion point
  useEffect(() => {
    if (low >= high && existingRewards.length > 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      setState("complete");
      const moreDamagingReward = existingRewards[low - 1];
      const lessDamagingReward = existingRewards[low];
      const moreDamagingRank = moreDamagingReward?.damage_rank ?? null;
      const lessDamagingRank = lessDamagingReward?.damage_rank ?? null;
      const newRank = generateKeyBetween(lessDamagingRank, moreDamagingRank);
      onComplete(newRank);
    }
  }, [low, high, existingRewards, onComplete]);

  // Handle case where there are no existing ranked rewards
  useEffect(() => {
    if (existingRewards.length === 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      const newRank = generateKeyBetween(null, null);
      onComplete(newRank);
    }
  }, [existingRewards.length, onComplete]);

  const handleMoreDamaging = useCallback(() => {
    setHigh(mid);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  const handleLessDamaging = useCallback(() => {
    setLow(mid + 1);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  // If no rewards to compare against, show loading
  if (existingRewards.length === 0) {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-muted">Setting up damage ranking...</Text>
      </View>
    );
  }

  // If comparison reward is undefined (brief window before effect transitions to complete)
  if (!comparisonReward) {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-muted">Finalizing ranking...</Text>
      </View>
    );
  }

  // If complete, show confirmation
  if (state === "complete") {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-2xl font-bold text-accent-secondary mb-2">Done!</Text>
        <Text className="text-muted text-center">
          Damage ranking has been set after {comparisonCount} comparison{comparisonCount !== 1 ? "s" : ""}.
        </Text>
      </View>
    );
  }

  const remainingComparisons = Math.ceil(Math.log2(existingRewards.length + 1)) - comparisonCount;

  return (
    <ScrollView className="flex-1 bg-background">
      <View className="p-6">
        <View className="mb-8">
          <Text className="text-2xl font-bold text-foreground mb-2 text-center">
            Set Damage Level
          </Text>
          <Text className="text-muted text-center">
            Compare with existing rewards to find where this fits
          </Text>
          <Text className="text-muted text-sm text-center mt-1">
            ~{remainingComparisons} comparison{remainingComparisons !== 1 ? "s" : ""} remaining
          </Text>
        </View>

        <View className="bg-surface rounded-xl p-4 mb-6">
          <Text className="text-sm text-accent font-medium mb-1">New Reward</Text>
          <Text className="text-lg font-semibold text-foreground">{reward.name}</Text>
          {reward.description ? (
            <Text className="text-muted text-sm mt-1" numberOfLines={2}>
              {reward.description}
            </Text>
          ) : null}
        </View>

        <Text className="text-center text-foreground text-lg mb-4">
          Is this reward more or less damaging than:
        </Text>

        <View className="bg-surface rounded-xl p-4 mb-8">
          <Text className="text-sm text-muted font-medium mb-1">Compare with</Text>
          <Text className="text-lg font-semibold text-foreground">{comparisonReward.name}</Text>
          {comparisonReward.description ? (
            <Text className="text-muted text-sm mt-1" numberOfLines={2}>
              {comparisonReward.description}
            </Text>
          ) : null}
        </View>

        <View className="gap-3">
          <Pressable
            onPress={handleMoreDamaging}
            className="bg-accent py-4 px-6 rounded-xl items-center"
          >
            <Text className="text-white font-bold text-lg">More Damaging</Text>
            <Text className="text-white/70 text-sm mt-1">Worse for my goals</Text>
          </Pressable>

          <Pressable
            onPress={handleLessDamaging}
            className="bg-accent-secondary py-4 px-6 rounded-xl items-center"
          >
            <Text className="text-white font-bold text-lg">Less Damaging</Text>
            <Text className="text-white/70 text-sm mt-1">Not as bad</Text>
          </Pressable>

          <Pressable
            onPress={onSkip}
            className="border border-border py-3 px-6 rounded-xl items-center mt-4"
          >
            <Text className="text-muted font-medium">Skip for now</Text>
          </Pressable>
        </View>

        <View className="mt-8 pt-4 border-t border-border">
          <Text className="text-muted text-center text-sm">
            Comparison {comparisonCount + 1} of ~{Math.ceil(Math.log2(existingRewards.length + 1))}
          </Text>
        </View>
      </View>
    </ScrollView>
  );
}
