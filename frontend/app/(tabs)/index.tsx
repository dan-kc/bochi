import { useState, useCallback, useEffect, useMemo } from "react";
import { View, Text, Pressable, Modal, Alert } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useHabitsContext } from "@/lib/HabitContext";
import { usePriceUpdate } from "@/lib/PriceUpdateContext";
import { HabitItem } from "@/components/HabitItem";
import { HabitForm } from "@/components/HabitForm";
import { DifficultyRanker } from "@/components/DifficultyRanker";
import { SyncStatusIcon } from "@/components/SyncStatusIcon";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import type { Habit, HabitInput } from "@/lib/habit";
import { SORT_OPTIONS } from "@/lib/sortOptions";
import { sortHabits } from "@/lib/habitSorting";
import { useSortPreference } from "@/lib/store/sortPreferencesStore";

export default function Habits() {
  const {
    habits,
    rankedHabits,
    selectedHabit,
    userId,
    createHabit,
    updateHabit,
    deleteHabit,
    completeHabit,
    selectHabit,
    setIsEditing,
  } = useHabitsContext();

  const [isHabitFormVisible, setIsHabitFormVisible] = useState(false);
  const [isRankingVisible, setIsRankingVisible] = useState(false);
  const [habitToRank, setHabitToRank] = useState<Habit | null>(null);
  const [sortKey, setSortKey] = useSortPreference();

  // Price update context
  const { updatePrices, prices } = usePriceUpdate();

  // Sort habits
  const displayHabits = useMemo(() => {
    return sortHabits(habits, sortKey, prices);
  }, [habits, sortKey, prices]);

  // Update prices when habits change
  useEffect(() => {
    updatePrices(habits);
  }, [habits, updatePrices]);

  const handleAddHabit = useCallback(() => {
    selectHabit(null);
    setIsEditing(false);
    setIsHabitFormVisible(true);
  }, [selectHabit, setIsEditing]);

  const handleHabitPress = useCallback(
    (habit: Habit) => {
      selectHabit(habit);
      setIsEditing(true);
      setIsHabitFormVisible(true);
    },
    [selectHabit, setIsEditing],
  );

  const handleSave = useCallback(
    async (input: HabitInput) => {
      if (selectedHabit) {
        await updateHabit(selectedHabit.id, input);
        setIsHabitFormVisible(false);
        selectHabit(null);
      } else {
        const newHabit = await createHabit(input);
        setIsHabitFormVisible(false);
        selectHabit(null);
        // After creating a new habit, offer to set difficulty
        setHabitToRank(newHabit);
        setIsRankingVisible(true);
      }
    },
    [selectedHabit, updateHabit, createHabit, selectHabit],
  );

  const handleCancel = useCallback(() => {
    setIsHabitFormVisible(false);
    selectHabit(null);
  }, [selectHabit]);

  const handleDelete = useCallback(async () => {
    if (selectedHabit) {
      await deleteHabit(selectedHabit.id);
      setIsHabitFormVisible(false);
      selectHabit(null);
    }
  }, [selectedHabit, deleteHabit, selectHabit]);

  const handleRankComplete = useCallback(
    async (rank: string) => {
      if (habitToRank) {
        await updateHabit(habitToRank.id, { difficulty_rank: rank });
      }
      setIsRankingVisible(false);
      setHabitToRank(null);
    },
    [habitToRank, updateHabit],
  );

  const handleRankSkip = useCallback(() => {
    setIsRankingVisible(false);
    setHabitToRank(null);
  }, []);

  const handleComplete = useCallback(
    async (habit: Habit) => {
      try {
        const amount = await completeHabit(habit);
        updatePrices(habits);
        Alert.alert("Completed!", `Earned ${amount} tofu for "${habit.name}"`);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Failed to complete habit";
        Alert.alert("Cannot Complete", message);
      }
    },
    [completeHabit, updatePrices, habits],
  );

  const handleRerank = useCallback(() => {
    if (selectedHabit) {
      setIsHabitFormVisible(false);
      setHabitToRank(selectedHabit);
      setIsRankingVisible(true);
    }
  }, [selectedHabit]);

  const renderItem = useCallback(
    ({ item }: { item: Habit }) => (
      <HabitItem habit={item} onPress={handleHabitPress} />
    ),
    [handleHabitPress],
  );

  const keyExtractor = useCallback((item: Habit) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-border">
          <View className="flex-row justify-between items-center mb-3">
            <Text className="text-2xl font-bold text-foreground">Habits</Text>
            <View className="flex-row items-center gap-2">
              <BalanceDisplay />
              <SyncStatusIcon />
            </View>
          </View>
          <View className="flex-row justify-end items-center">
            <SortDropdown
              options={SORT_OPTIONS}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayHabits.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-muted text-center mb-4">
              No habits yet. Add your first habit to get started.
            </Text>
          </View>
        ) : (
          <LegendList
            data={displayHabits}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            extraData={{ sortKey }}
            contentContainerStyle={{ padding: 16 }}
            estimatedItemSize={100}
          />
        )}

        <View className="p-4 border-t border-border">
          <Pressable
            onPress={handleAddHabit}
            className="bg-accent py-3 px-6 rounded-lg items-center"
          >
            <Text className="text-white font-semibold text-base">Add Habit</Text>
          </Pressable>
        </View>

        <Modal
          visible={isHabitFormVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleCancel}
        >
          <SafeAreaView className="flex-1 bg-background">
            <HabitForm
              habit={selectedHabit}
              userId={userId}
              onSave={handleSave}
              onCancel={handleCancel}
              onDelete={selectedHabit ? handleDelete : undefined}
              onRerank={selectedHabit && habits.length > 1 ? handleRerank : undefined}
              onComplete={selectedHabit ? handleComplete : undefined}
            />
          </SafeAreaView>
        </Modal>

        <Modal
          visible={isRankingVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleRankSkip}
        >
          <SafeAreaView className="flex-1 bg-background">
            {habitToRank && (
              <DifficultyRanker
                habit={habitToRank}
                existingHabits={rankedHabits.filter(h => h.id !== habitToRank.id && h.difficulty_rank !== null)}
                onComplete={handleRankComplete}
                onSkip={handleRankSkip}
              />
            )}
          </SafeAreaView>
        </Modal>
      </View>
    </SafeAreaView>
  );
}
