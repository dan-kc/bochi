import { useState, useEffect, useCallback, useRef } from "react";
import { View, Text, Pressable, ScrollView, StyleSheet } from "react-native";
import type { Habit } from "@/lib/habit";
import { generateKeyBetween } from "@/lib/fractionalIndex";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface DifficultyRankerProps {
  habit: Habit;
  existingHabits: Habit[]; // Already-ranked habits, sorted by difficulty (hardest first)
  onComplete: (rank: string) => void;
  onSkip: () => void;
}

type RankingState = "comparing" | "complete";

export function DifficultyRanker({
  habit,
  existingHabits,
  onComplete,
  onSkip,
}: DifficultyRankerProps) {
  const colors = useColors();
  const [low, setLow] = useState(0);
  const [high, setHigh] = useState(existingHabits.length);
  const [state, setState] = useState<RankingState>("comparing");
  const [comparisonCount, setComparisonCount] = useState(0);
  const hasCompletedRef = useRef(false);

  // Calculate the midpoint for binary search
  const mid = Math.floor((low + high) / 2);
  const comparisonHabit = existingHabits[mid];

  // Check if we've found the insertion point
  useEffect(() => {
    if (low >= high && existingHabits.length > 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      setState("complete");
      const harderHabit = existingHabits[low - 1];
      const easierHabit = existingHabits[low];
      const harderRank = harderHabit?.difficulty_rank ?? null;
      const easierRank = easierHabit?.difficulty_rank ?? null;
      const newRank = generateKeyBetween(easierRank, harderRank);
      onComplete(newRank);
    }
  }, [low, high, existingHabits, onComplete]);

  // Handle case where there are no existing ranked habits
  useEffect(() => {
    if (existingHabits.length === 0 && !hasCompletedRef.current) {
      hasCompletedRef.current = true;
      const newRank = generateKeyBetween(null, null);
      onComplete(newRank);
    }
  }, [existingHabits.length, onComplete]);

  const handleHarder = useCallback(() => {
    setHigh(mid);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  const handleEasier = useCallback(() => {
    setLow(mid + 1);
    setComparisonCount((c) => c + 1);
  }, [mid]);

  // If no habits to compare against, show loading
  if (existingHabits.length === 0) {
    return (
      <View style={styles.loadingContainer}>
        <Text style={[styles.loadingText, { color: colors.muted }]}>Setting up difficulty ranking...</Text>
      </View>
    );
  }

  // If comparison habit is undefined (brief window before effect transitions to complete)
  if (!comparisonHabit) {
    return (
      <View style={styles.loadingContainer}>
        <Text style={[styles.loadingText, { color: colors.muted }]}>Finalizing ranking...</Text>
      </View>
    );
  }

  // If complete, show confirmation
  if (state === "complete") {
    return (
      <View style={styles.loadingContainer}>
        <Text style={[styles.completeTitle, { color: colors.accentSecondary }]}>Done!</Text>
        <Text style={[styles.completeText, { color: colors.muted }]}>
          Difficulty ranking has been set after {comparisonCount} comparison{comparisonCount !== 1 ? "s" : ""}.
        </Text>
      </View>
    );
  }

  const remainingComparisons = Math.ceil(Math.log2(existingHabits.length + 1)) - comparisonCount;

  return (
    <ScrollView style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.content}>
        <View style={styles.headerSection}>
          <Text style={[styles.headerTitle, { color: colors.foreground }]}>
            Set Difficulty
          </Text>
          <Text style={[styles.headerSubtitle, { color: colors.muted }]}>
            Compare with existing habits to find where this fits
          </Text>
          <Text style={[styles.headerRemaining, { color: colors.muted }]}>
            ~{remainingComparisons} comparison{remainingComparisons !== 1 ? "s" : ""} remaining
          </Text>
        </View>

        <View style={[styles.entityCard, { backgroundColor: colors.surface }]}>
          <Text style={[styles.entityLabel, { color: colors.accent }]}>New Habit</Text>
          <Text style={[styles.entityName, { color: colors.foreground }]}>{habit.name}</Text>
          {habit.description ? (
            <Text style={[styles.entityDescription, { color: colors.muted }]} numberOfLines={2}>
              {habit.description}
            </Text>
          ) : null}
        </View>

        <Text style={[styles.questionText, { color: colors.foreground }]}>
          Is this habit harder or easier than:
        </Text>

        <View style={[styles.entityCard, styles.comparisonCard, { backgroundColor: colors.surface }]}>
          <Text style={[styles.comparisonLabel, { color: colors.muted }]}>Compare with</Text>
          <Text style={[styles.entityName, { color: colors.foreground }]}>{comparisonHabit.name}</Text>
          {comparisonHabit.description ? (
            <Text style={[styles.entityDescription, { color: colors.muted }]} numberOfLines={2}>
              {comparisonHabit.description}
            </Text>
          ) : null}
        </View>

        <View style={styles.buttonContainer}>
          <Pressable
            onPress={handleHarder}
            style={[styles.choiceButton, { backgroundColor: colors.accent }]}
          >
            <Text style={[styles.choiceButtonTitle, { color: colors.white }]}>Harder</Text>
            <Text style={[styles.choiceButtonSubtitle, { color: colors.white }]}>More difficult to complete</Text>
          </Pressable>

          <Pressable
            onPress={handleEasier}
            style={[styles.choiceButton, { backgroundColor: colors.accentSecondary }]}
          >
            <Text style={[styles.choiceButtonTitle, { color: colors.white }]}>Easier</Text>
            <Text style={[styles.choiceButtonSubtitle, { color: colors.white }]}>Less difficult to complete</Text>
          </Pressable>

          <Pressable
            onPress={onSkip}
            style={[styles.skipButton, { borderColor: colors.border }]}
          >
            <Text style={[styles.skipButtonText, { color: colors.muted }]}>Skip for now</Text>
          </Pressable>
        </View>

        <View style={[styles.footer, { borderTopColor: colors.border }]}>
          <Text style={[styles.footerText, { color: colors.muted }]}>
            Comparison {comparisonCount + 1} of ~{Math.ceil(Math.log2(existingHabits.length + 1))}
          </Text>
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: spacing[6],
  },
  loadingContainer: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: spacing[6],
  },
  loadingText: {
    fontSize: fontSize.base,
  },
  completeTitle: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
    marginBottom: spacing[2],
  },
  completeText: {
    textAlign: "center",
  },
  headerSection: {
    marginBottom: spacing[8],
  },
  headerTitle: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
    marginBottom: spacing[2],
    textAlign: "center",
  },
  headerSubtitle: {
    textAlign: "center",
  },
  headerRemaining: {
    fontSize: fontSize.sm,
    textAlign: "center",
    marginTop: spacing[1],
  },
  entityCard: {
    borderRadius: borderRadius.xl,
    padding: spacing[4],
    marginBottom: spacing[6],
  },
  comparisonCard: {
    marginBottom: spacing[8],
  },
  entityLabel: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    marginBottom: spacing[1],
  },
  comparisonLabel: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    marginBottom: spacing[1],
  },
  entityName: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
  },
  entityDescription: {
    fontSize: fontSize.sm,
    marginTop: spacing[1],
  },
  questionText: {
    textAlign: "center",
    fontSize: fontSize.lg,
    marginBottom: spacing[4],
  },
  buttonContainer: {
    gap: spacing[3],
  },
  choiceButton: {
    paddingVertical: spacing[4],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.xl,
    alignItems: "center",
  },
  choiceButtonTitle: {
    fontWeight: fontWeight.bold,
    fontSize: fontSize.lg,
  },
  choiceButtonSubtitle: {
    fontSize: fontSize.sm,
    marginTop: spacing[1],
    opacity: 0.7,
  },
  skipButton: {
    borderWidth: 1,
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.xl,
    alignItems: "center",
    marginTop: spacing[4],
  },
  skipButtonText: {
    fontWeight: fontWeight.medium,
  },
  footer: {
    marginTop: spacing[8],
    paddingTop: spacing[4],
    borderTopWidth: 1,
  },
  footerText: {
    textAlign: "center",
    fontSize: fontSize.sm,
  },
});
