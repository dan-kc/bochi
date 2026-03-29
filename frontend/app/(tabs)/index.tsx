import { useState, useCallback, useEffect, useMemo, useRef } from "react";
import { View, Text, Pressable, Modal, Alert, StyleSheet } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useHabitsContext } from "@/lib/HabitContext";
import { usePriceUpdate } from "@/lib/PriceUpdateContext";
import { HabitItem } from "@/components/HabitItem";
import { HabitForm } from "@/components/HabitForm";
import { DifficultyRanker } from "@/components/DifficultyRanker";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import type { Habit, HabitInput } from "@/lib/habit";
import { SORT_OPTIONS } from "@/lib/sortOptions";
import { sortHabits } from "@/lib/habitSorting";
import { useSortPreference } from "@/lib/store/sortPreferencesStore";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

export default function Habits() {
  const colors = useColors();
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
  const [formKey, setFormKey] = useState(0);
  const rankerFromForm = useRef(false);

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
    setFormKey(k => k + 1);
    setIsHabitFormVisible(true);
  }, [selectHabit, setIsEditing]);

  const handleHabitPress = useCallback(
    (habit: Habit) => {
      selectHabit(habit);
      setIsEditing(true);
      setFormKey(k => k + 1);
      setIsHabitFormVisible(true);
    },
    [selectHabit, setIsEditing],
  );

  const handleSave = useCallback(
    async (input: HabitInput) => {
      if (selectedHabit) {
        await updateHabit(selectedHabit.id, input);
      } else {
        const newHabit = await createHabit(input);
        selectHabit(newHabit);
        setIsEditing(true);
      }
    },
    [selectedHabit, updateHabit, createHabit, selectHabit, setIsEditing],
  );

  const handleFormClose = useCallback(() => {
    setIsHabitFormVisible(false);
  }, []);

  const handleDelete = useCallback(async () => {
    if (selectedHabit) {
      await deleteHabit(selectedHabit.id);
      setIsHabitFormVisible(false);
    }
  }, [selectedHabit, deleteHabit]);

  const handleRankComplete = useCallback(
    async (rank: string) => {
      if (habitToRank) {
        await updateHabit(habitToRank.id, { difficulty_rank: rank });
      }
      setIsRankingVisible(false);
      setHabitToRank(null);
      rankerFromForm.current = false;
    },
    [habitToRank, updateHabit],
  );

  const handleRankSkip = useCallback(() => {
    setIsRankingVisible(false);
    setHabitToRank(null);
    rankerFromForm.current = false;
  }, []);

  const handleComplete = useCallback(
    async (habit: Habit) => {
      setIsHabitFormVisible(false);
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
      rankerFromForm.current = true;
      setHabitToRank(selectedHabit);
      setIsRankingVisible(true);
    }
  }, [selectedHabit]);

  const handleSetRank = useCallback(
    (habit: Habit) => {
      setHabitToRank(habit);
      setIsRankingVisible(true);
    },
    [],
  );

  const renderItem = useCallback(
    ({ item }: { item: Habit }) => (
      <HabitItem habit={item} onPress={handleHabitPress} onComplete={handleComplete} onSetRank={handleSetRank} />
    ),
    [handleHabitPress, handleComplete, handleSetRank],
  );

  const keyExtractor = useCallback((item: Habit) => item.id, []);

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]} edges={["top"]}>
      <View style={styles.container}>
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <View style={styles.headerRow}>
            <Text style={[styles.title, { color: colors.foreground }]}>Habits</Text>
            <BalanceDisplay />
          </View>
          <View style={styles.sortRow}>
            <SortDropdown
              options={SORT_OPTIONS}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayHabits.length === 0 ? (
          <View style={styles.emptyContainer}>
            <Text style={[styles.emptyText, { color: colors.muted }]}>
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

        <View style={[styles.footer, { borderTopColor: colors.border }]}>
          <Pressable
            onPress={handleAddHabit}
            style={[styles.addButton, { backgroundColor: colors.accent }]}
          >
            <Text style={styles.addButtonText}>Add Habit</Text>
          </Pressable>
        </View>

        <Modal
          visible={isHabitFormVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleFormClose}
        >
          <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
            <HabitForm
              key={formKey}
              habit={selectedHabit}
              userId={userId}
              onSave={handleSave}
              onClose={handleFormClose}
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
          <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
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

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
  },
  header: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  headerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: spacing[3],
  },
  title: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
  },
  sortRow: {
    flexDirection: "row",
    justifyContent: "flex-end",
    alignItems: "center",
  },
  emptyContainer: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: spacing[4],
  },
  emptyText: {
    textAlign: "center",
    marginBottom: spacing[4],
  },
  footer: {
    padding: spacing[4],
    borderTopWidth: 1,
  },
  addButton: {
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  addButtonText: {
    color: "white",
    fontWeight: fontWeight.semibold,
    fontSize: fontSize.base,
  },
});
