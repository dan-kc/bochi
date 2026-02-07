import { View, Text, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import type { Reward } from "@/lib/reward";
import { useRewardPriceUpdateOptional } from "@/lib/RewardPriceUpdateContext";
import type { DisplayMode } from "@/lib/rewardSorting";
import { formatShortDate } from "@/lib/rewardSorting";
import { RewardTagChips } from "./RewardTagChips";

interface RewardItemProps {
  reward: Reward;
  onPress: (reward: Reward) => void;
  onPurchase?: (reward: Reward) => void;
  onSetDamage?: (reward: Reward) => void;
  isDamageView?: boolean;
  displayMode?: DisplayMode;
}

function formatDate(dateString: string | null): string {
  if (!dateString) return "";
  const date = new Date(dateString);
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
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

    const { current, previous } = priceData;
    const isUp = current > previous;
    const isDown = current < previous;

    return (
      <View className="flex-row items-center bg-red-50 border border-red-200 px-2 py-1 rounded">
        {isUp && <Ionicons name="arrow-up" size={12} color="#ef4444" />}
        {isDown && <Ionicons name="arrow-down" size={12} color="#22c55e" />}
        <Text
          className={`text-xs font-medium ml-0.5 ${
            isUp ? "text-red-600" : isDown ? "text-green-600" : "text-red-700"
          }`}
        >
          {current} tofu (was {previous})
        </Text>
      </View>
    );
  }

  if (displayMode === "frequency") {
    if (reward.max_daily_frequency == null) {
      return (
        <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
          <Text className="text-xs font-medium text-gray-500">no limit</Text>
        </View>
      );
    }
    return (
      <View className="flex-row items-center bg-orange-50 border border-orange-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-orange-700">
          {reward.max_daily_frequency} max/day
        </Text>
      </View>
    );
  }

  if (displayMode === "created_at") {
    return (
      <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-gray-700">
          {formatShortDate(reward.created_at)}
        </Text>
      </View>
    );
  }

  if (displayMode === "damage") {
    if (reward.damage_rank == null) {
      return (
        <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
          <Text className="text-xs font-medium text-gray-500">not set</Text>
        </View>
      );
    }
    return (
      <View className="flex-row items-center bg-red-50 border border-red-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-red-700 font-mono">
          {reward.damage_rank}
        </Text>
      </View>
    );
  }

  return null;
}

export function RewardItem({
  reward,
  onPress,
  onPurchase,
  onSetDamage,
  isDamageView,
  displayMode = "price",
}: RewardItemProps) {
  const hasHiddenUntil = reward.hidden_until !== null;
  const hasDamageRank = reward.damage_rank != null;
  const isUnrankedInDamageView = isDamageView && !hasDamageRank;
  const priceContext = useRewardPriceUpdateOptional();
  const currentPrice = priceContext?.prices[reward.id]?.current;

  return (
    <Pressable
      onPress={() => onPress(reward)}
      className={`border rounded-lg p-4 mb-3 ${
        isUnrankedInDamageView
          ? "bg-gray-50 border-gray-300"
          : "bg-white border-gray-200"
      }`}
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <View className="flex-row justify-between items-start">
            <Text className="text-lg font-semibold text-gray-900 mb-1 flex-1">
              {reward.name}
            </Text>
            <View className="flex-row items-center gap-2 ml-2">
              <InfoDisplay reward={reward} displayMode={displayMode} />
              {isUnrankedInDamageView && (
                <View className="bg-gray-200 px-2 py-1 rounded">
                  <Text className="text-gray-600 text-xs font-medium">
                    Unranked
                  </Text>
                </View>
              )}
            </View>
          </View>
          {reward.description ? (
            <Text
              className="text-gray-600 text-sm mb-1"
              numberOfLines={2}
              ellipsizeMode="tail"
            >
              {reward.description}
            </Text>
          ) : null}
          <RewardTagChips rewardId={reward.id} />
          <View className="flex-row flex-wrap gap-2 mt-2">
            {hasHiddenUntil && (
              <View className="bg-gray-100 px-2 py-1 rounded">
                <Text className="text-gray-600 text-xs">
                  Hidden until: {formatDate(reward.hidden_until)}
                </Text>
              </View>
            )}
            {reward.max_daily_frequency !== null && (
              <View className="bg-orange-100 px-2 py-1 rounded">
                <Text className="text-orange-700 text-xs">
                  {reward.max_daily_frequency}x max/day
                </Text>
              </View>
            )}
            {hasDamageRank && isDamageView && (
              <View className="bg-red-100 px-2 py-1 rounded">
                <Text className="text-red-700 text-xs font-mono">
                  {reward.damage_rank}
                </Text>
              </View>
            )}
            {!hasDamageRank && onSetDamage && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onSetDamage(reward);
                }}
                className="bg-red-50 border border-red-200 px-2 py-1 rounded"
              >
                <Text className="text-red-600 text-xs">Set Damage</Text>
              </Pressable>
            )}
            {onPurchase && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onPurchase(reward);
                }}
                className="bg-red-500 px-3 py-1 rounded ml-auto"
              >
                <Text className="text-white text-xs font-semibold">
                  -{currentPrice ?? "..."} tofu
                </Text>
              </Pressable>
            )}
          </View>
        </View>
      )}
    </Pressable>
  );
}
