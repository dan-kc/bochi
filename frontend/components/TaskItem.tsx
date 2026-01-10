import { View, Text, Pressable } from "react-native";
import type { Task } from "@/lib/task";

interface TaskItemProps {
  task: Task;
  onPress: (task: Task) => void;
  onSetDifficulty?: (task: Task) => void;
  showDifficultyRank?: boolean;
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

export function TaskItem({
  task,
  onPress,
  onSetDifficulty,
  showDifficultyRank,
}: TaskItemProps) {
  const hasDueBy = task.due_by !== null;
  const hasHiddenUntil = task.hidden_until !== null;
  const hasDifficultyRank = task.difficulty_rank !== null;

  return (
    <Pressable
      onPress={() => onPress(task)}
      className="bg-white border border-gray-200 rounded-lg p-4 mb-3"
    >
      {({ hovered }) => (
        <View className={hovered ? "opacity-80" : ""}>
          <View className="flex-row justify-between items-start">
            <Text className="text-lg font-semibold text-gray-900 mb-1 flex-1">
              {task.name}
            </Text>
            {showDifficultyRank && hasDifficultyRank && (
              <View className="bg-orange-100 px-2 py-1 rounded ml-2">
                <Text className="text-orange-700 text-xs font-medium">
                  Ranked
                </Text>
              </View>
            )}
          </View>
          {task.description ? (
            <Text
              className="text-gray-600 text-sm mb-2"
              numberOfLines={2}
              ellipsizeMode="tail"
            >
              {task.description}
            </Text>
          ) : null}
          <View className="flex-row flex-wrap gap-2">
            {hasDueBy && (
              <View className="bg-blue-100 px-2 py-1 rounded">
                <Text className="text-blue-700 text-xs">
                  Due: {formatDate(task.due_by)}
                </Text>
              </View>
            )}
            {hasHiddenUntil && (
              <View className="bg-gray-100 px-2 py-1 rounded">
                <Text className="text-gray-600 text-xs">
                  Hidden until: {formatDate(task.hidden_until)}
                </Text>
              </View>
            )}
            {task.min_daily_frequency !== null && (
              <View className="bg-green-100 px-2 py-1 rounded">
                <Text className="text-green-700 text-xs">
                  {task.min_daily_frequency}x/day
                </Text>
              </View>
            )}
            {!hasDifficultyRank && onSetDifficulty && (
              <Pressable
                onPress={(e) => {
                  e.stopPropagation();
                  onSetDifficulty(task);
                }}
                className="bg-orange-50 border border-orange-200 px-2 py-1 rounded"
              >
                <Text className="text-orange-600 text-xs">Set Difficulty</Text>
              </Pressable>
            )}
          </View>
        </View>
      )}
    </Pressable>
  );
}
