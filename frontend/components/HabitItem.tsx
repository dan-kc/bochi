import { View, Text, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import type { Habit } from "@/lib/habit";
import { usePriceUpdateOptional } from "@/lib/PriceUpdateContext";
import type { DisplayMode } from "@/lib/habitSorting";
import { formatShortDate } from "@/lib/habitSorting";

interface HabitItemProps {
  habit: Habit;
  onPress: (habit: Habit) => void;
  onComplete?: (habit: Habit) => void;
  onSetDifficulty?: (habit: Habit) => void;
  isDifficultyView?: boolean;
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
  habit,
  displayMode,
}: {
  habit: Habit;
  displayMode: DisplayMode;
}) {
  const priceContext = usePriceUpdateOptional();

  if (displayMode === "price") {
    if (!priceContext) return null;
    const priceData = priceContext.prices[habit.id];
    if (!priceData) return null;

    const { current, previous } = priceData;
    const isUp = current > previous;
    const isDown = current < previous;

    return (
      <View className="flex-row items-center bg-amber-50 border border-amber-200 px-2 py-1 rounded">
        {isUp && <Ionicons name="arrow-up" size={12} color="#22c55e" />}
        {isDown && <Ionicons name="arrow-down" size={12} color="#ef4444" />}
        <Text
          className={`text-xs font-medium ml-0.5 ${
            isUp ? "text-green-600" : isDown ? "text-red-600" : "text-amber-700"
          }`}
        >
          {current} soy (was {previous})
        </Text>
      </View>
    );
  }

  if (displayMode === "frequency") {
    if (habit.min_daily_frequency == null) {
      return (
        <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
          <Text className="text-xs font-medium text-gray-500">no frequency</Text>
        </View>
      );
    }
    return (
      <View className="flex-row items-center bg-green-50 border border-green-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-green-700">
          {habit.min_daily_frequency} /day
        </Text>
      </View>
    );
  }

  if (displayMode === "created_at") {
    return (
      <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-gray-700">
          {formatShortDate(habit.created_at)}
        </Text>
      </View>
    );
  }

  if (displayMode === "difficulty") {
    if (habit.difficulty_rank == null) {
      return (
        <View className="flex-row items-center bg-gray-50 border border-gray-200 px-2 py-1 rounded">
          <Text className="text-xs font-medium text-gray-500">not set</Text>
        </View>
      );
    }
    return (
      <View className="flex-row items-center bg-purple-50 border border-purple-200 px-2 py-1 rounded">
        <Text className="text-xs font-medium text-purple-700 font-mono">
          {habit.difficulty_rank}
        </Text>
      </View>
    );
  }

  return null;
}

export function HabitItem({
  habit,
  onPress,
  onComplete,
  onSetDifficulty,
  isDifficultyView,
  displayMode = "price",
}: HabitItemProps) {
  const hasHiddenUntil = habit.hidden_until !== null;
  // Use != null to catch both null and undefined
  const hasDifficultyRank = habit.difficulty_rank != null;
  const isUnrankedInDifficultyView = isDifficultyView && !hasDifficultyRank;
  const priceContext = usePriceUpdateOptional();
  const currentPrice = priceContext?.prices[habit.id]?.current;

  return (
    <Pressable
      onPress={() => onPress(habit)}
      className={`border rounded-lg p-4 mb-3 ${
        isUnrankedInDifficultyView
          ? "bg-gray-50 border-gray-300"
          : "bg-white border-gray-200"
      }`}
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <View className="flex-row justify-between items-start">
            <Text className="text-lg font-semibold text-gray-900 mb-1 flex-1">
              {habit.name}
            </Text>
            <View className="flex-row items-center gap-2 ml-2">
              <InfoDisplay habit={habit} displayMode={displayMode} />
              {isUnrankedInDifficultyView && (
                <View className="bg-gray-200 px-2 py-1 rounded">
                  <Text className="text-gray-600 text-xs font-medium">
                    Unranked
                  </Text>
                </View>
              )}
            </View>
          </View>
          {habit.description ? (
            <Text
              className="text-gray-600 text-sm mb-2"
              numberOfLines={2}
              ellipsizeMode="tail"
            >
              {habit.description}
            </Text>
          ) : null}
          <View className="flex-row flex-wrap gap-2">
            {hasHiddenUntil && (
              <View className="bg-gray-100 px-2 py-1 rounded">
                <Text className="text-gray-600 text-xs">
                  Hidden until: {formatDate(habit.hidden_until)}
                </Text>
              </View>
            )}
            {habit.min_daily_frequency !== null && (
              <View className="bg-green-100 px-2 py-1 rounded">
                <Text className="text-green-700 text-xs">
                  {habit.min_daily_frequency}x/day
                </Text>
              </View>
            )}
            {hasDifficultyRank && isDifficultyView && (
              <View className="bg-purple-100 px-2 py-1 rounded">
                <Text className="text-purple-700 text-xs font-mono">
                  {habit.difficulty_rank}
                </Text>
              </View>
            )}
            {!hasDifficultyRank && onSetDifficulty && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onSetDifficulty(habit);
                }}
                className="bg-orange-50 border border-orange-200 px-2 py-1 rounded"
              >
                <Text className="text-orange-600 text-xs">Set Difficulty</Text>
              </Pressable>
            )}
            {onComplete && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onComplete(habit);
                }}
                className="bg-green-500 px-3 py-1 rounded ml-auto"
              >
                <Text className="text-white text-xs font-semibold">
                  +{currentPrice ?? "..."} soy
                </Text>
              </Pressable>
            )}
          </View>
        </View>
      )}
    </Pressable>
  );
}
