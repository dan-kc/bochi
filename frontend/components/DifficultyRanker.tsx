import { useState, useEffect, useCallback, useRef } from "react";
import { View, Text, Pressable, ScrollView } from "react-native";
import type { Task } from "@/lib/task";
import { generateKeyBetween } from "@/lib/fractionalIndex";

interface DifficultyRankerProps {
  task: Task;
  existingTasks: Task[]; // Already-ranked tasks, sorted by difficulty (hardest first)
  onComplete: (rank: string) => void;
  onSkip: () => void;
}

type RankingState = "comparing" | "complete";

export function DifficultyRanker({
  task,
  existingTasks,
  onComplete,
  onSkip,
}: DifficultyRankerProps) {
  const [low, setLow] = useState(0);
  const [high, setHigh] = useState(existingTasks.length);
  const [state, setState] = useState<RankingState>("comparing");
  const [comparisonCount, setComparisonCount] = useState(0);
  const hasCompletedRef = useRef(false);

  // Calculate the midpoint for binary search
  const mid = Math.floor((low + high) / 2);
  const comparisonTask = existingTasks[mid];

  // Check if we've found the insertion point
  useEffect(() => {
    if (low >= high && existingTasks.length > 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      setState("complete");
      // Generate rank between adjacent tasks
      // List is sorted hardest-first (descending by rank), so:
      // - existingTasks[low - 1] has higher rank (harder)
      // - existingTasks[low] has lower rank (easier)
      // generateKeyBetween expects (smaller, larger) so we swap the order
      const harderTask = existingTasks[low - 1];
      const easierTask = existingTasks[low];
      const harderRank = harderTask?.difficulty_rank ?? null;
      const easierRank = easierTask?.difficulty_rank ?? null;
      const newRank = generateKeyBetween(easierRank, harderRank);
      onComplete(newRank);
    }
  }, [low, high, existingTasks, onComplete]);

  // Handle case where there are no existing ranked tasks
  useEffect(() => {
    if (existingTasks.length === 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      const newRank = generateKeyBetween(null, null);
      onComplete(newRank);
    }
  }, [existingTasks.length, onComplete]);

  const handleHarder = useCallback(() => {
    // Task is harder than comparison, so it goes in the lower indices (higher rank)
    setHigh(mid);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  const handleEasier = useCallback(() => {
    // Task is easier than comparison, so it goes in the higher indices (lower rank)
    setLow(mid + 1);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  // If no tasks to compare against, show loading
  if (existingTasks.length === 0) {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-gray-500">Setting up difficulty ranking...</Text>
      </View>
    );
  }

  // If comparison task is undefined (brief window before effect transitions to complete)
  if (!comparisonTask) {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-gray-500">Finalizing ranking...</Text>
      </View>
    );
  }

  // If complete, show confirmation
  if (state === "complete") {
    return (
      <View className="flex-1 items-center justify-center p-6">
        <Text className="text-2xl font-bold text-green-600 mb-2">Done!</Text>
        <Text className="text-gray-600 text-center">
          Difficulty ranking has been set after {comparisonCount} comparison{comparisonCount !== 1 ? "s" : ""}.
        </Text>
      </View>
    );
  }

  const remainingComparisons = Math.ceil(Math.log2(existingTasks.length + 1)) - comparisonCount;

  return (
    <ScrollView className="flex-1 bg-white">
      <View className="p-6">
        <View className="mb-8">
          <Text className="text-2xl font-bold text-gray-900 mb-2 text-center">
            Set Difficulty
          </Text>
          <Text className="text-gray-600 text-center">
            Compare with existing tasks to find where this fits
          </Text>
          <Text className="text-gray-400 text-sm text-center mt-1">
            ~{remainingComparisons} comparison{remainingComparisons !== 1 ? "s" : ""} remaining
          </Text>
        </View>

        <View className="bg-blue-50 rounded-xl p-4 mb-6">
          <Text className="text-sm text-blue-600 font-medium mb-1">New Task</Text>
          <Text className="text-lg font-semibold text-gray-900">{task.name}</Text>
          {task.description ? (
            <Text className="text-gray-600 text-sm mt-1" numberOfLines={2}>
              {task.description}
            </Text>
          ) : null}
        </View>

        <Text className="text-center text-gray-700 text-lg mb-4">
          Is this task harder or easier than:
        </Text>

        <View className="bg-gray-50 rounded-xl p-4 mb-8">
          <Text className="text-sm text-gray-500 font-medium mb-1">Compare with</Text>
          <Text className="text-lg font-semibold text-gray-900">{comparisonTask.name}</Text>
          {comparisonTask.description ? (
            <Text className="text-gray-600 text-sm mt-1" numberOfLines={2}>
              {comparisonTask.description}
            </Text>
          ) : null}
        </View>

        <View className="gap-3">
          <Pressable
            onPress={handleHarder}
            className="bg-red-500 py-4 px-6 rounded-xl items-center"
          >
            <Text className="text-white font-bold text-lg">Harder</Text>
            <Text className="text-red-100 text-sm mt-1">More difficult to complete</Text>
          </Pressable>

          <Pressable
            onPress={handleEasier}
            className="bg-green-500 py-4 px-6 rounded-xl items-center"
          >
            <Text className="text-white font-bold text-lg">Easier</Text>
            <Text className="text-green-100 text-sm mt-1">Less difficult to complete</Text>
          </Pressable>

          <Pressable
            onPress={onSkip}
            className="border border-gray-300 py-3 px-6 rounded-xl items-center mt-4"
          >
            <Text className="text-gray-600 font-medium">Skip for now</Text>
          </Pressable>
        </View>

        <View className="mt-8 pt-4 border-t border-gray-200">
          <Text className="text-gray-400 text-center text-sm">
            Comparison {comparisonCount + 1} of ~{Math.ceil(Math.log2(existingTasks.length + 1))}
          </Text>
        </View>
      </View>
    </ScrollView>
  );
}
