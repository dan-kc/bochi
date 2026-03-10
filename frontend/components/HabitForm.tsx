import { useState, useEffect } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { z } from "zod";
import type { Habit, HabitInput } from "@/lib/habit";
import { createEmptyHabitInput } from "@/lib/habit";
import type { Tag } from "@/lib/tag";
import { useTagsForHabit, useTagActions } from "@/lib/store/hooks";
import { TagSelectionModal } from "./TagSelectionModal";
import { ColorPickerModal } from "./ColorPickerModal";

interface HabitFormProps {
  habit?: Habit | null;
  userId: string;
  onSave: (input: HabitInput) => Promise<void>;
  onCancel: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
  onComplete?: (habit: Habit) => Promise<void>;
}

const habitSchema = z.object({
  name: z
    .string()
    .min(1, "Name is required")
    .max(100, "Name must be 100 characters or less"),
  description: z
    .string()
    .max(10000, "Description must be 10,000 characters or less"),
  min_daily_frequency: z
    .number()
    .gt(0, "Frequency must be greater than 0")
    .lte(100, "Frequency must be 100 or less")
    .nullable(),
});

type FrequencyPeriod = "day" | "week" | "month";

const PERIOD_DIVISORS: Record<FrequencyPeriod, number> = {
  day: 1,
  week: 7,
  month: 30,
};

function formatFrequencySummary(frequency: number | null): string | null {
  if (frequency == null) return null;
  if (frequency >= 1) {
    const formatted = frequency.toFixed(2).replace(/\.?0+$/, "");
    return `${formatted}/day`;
  }
  const weekly = frequency * 7;
  if (weekly >= 1) {
    const formatted = weekly.toFixed(2).replace(/\.?0+$/, "");
    return `${formatted}/week`;
  }
  const monthly = frequency * 30;
  const formatted = monthly.toFixed(2).replace(/\.?0+$/, "");
  return `${formatted}/month`;
}

export function HabitForm({ habit, userId, onSave, onCancel, onDelete, onRerank, onComplete }: HabitFormProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [minDailyFrequency, setMinDailyFrequency] = useState("");
  const [frequencyPeriod, setFrequencyPeriod] = useState<FrequencyPeriod>("day");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[]>>({});
  const [showMore, setShowMore] = useState(false);

  // Tag selection state
  const [showTagModal, setShowTagModal] = useState(false);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [editingTag, setEditingTag] = useState<Tag | null>(null);

  const isEditing = !!habit;

  // Get tags for this habit (only when editing)
  const habitTags = useTagsForHabit(habit?.id ?? "");
  const { updateTag } = useTagActions();

  useEffect(() => {
    if (habit) {
      setName(habit.name);
      setDescription(habit.description);

      if (habit.min_daily_frequency !== null) {
        const dailyFreq = habit.min_daily_frequency;
        let bestPeriod: FrequencyPeriod = "day";
        let displayValue = dailyFreq;

        if (dailyFreq >= 1) {
          bestPeriod = "day";
          displayValue = dailyFreq;
        } else if (dailyFreq * 7 >= 1) {
          bestPeriod = "week";
          displayValue = dailyFreq * 7;
        } else {
          bestPeriod = "month";
          displayValue = dailyFreq * 30;
        }

        setFrequencyPeriod(bestPeriod);
        setMinDailyFrequency(String(displayValue));
      } else {
        setMinDailyFrequency("");
        setFrequencyPeriod("day");
      }
    } else {
      const empty = createEmptyHabitInput();
      setName(empty.name);
      setDescription(empty.description);
      setMinDailyFrequency("");
      setFrequencyPeriod("day");
    }
  }, [habit]);

  const handleSave = async () => {
    setErrors({});

    const rawFrequency = minDailyFrequency.trim()
      ? parseFloat(minDailyFrequency)
      : null;
    const frequency = rawFrequency !== null
      ? rawFrequency / PERIOD_DIVISORS[frequencyPeriod]
      : null;

    const input = {
      name: name.trim(),
      description: description.trim(),
      min_daily_frequency: frequency,
    };

    const result = habitSchema.safeParse(input);

    if (!result.success) {
      const fieldErrors: Record<string, string[]> = {};
      for (const issue of result.error.issues) {
        const path = issue.path.join(".") || "general";
        if (!fieldErrors[path]) {
          fieldErrors[path] = [];
        }
        fieldErrors[path].push(issue.message);
      }
      setErrors(fieldErrors);
      return;
    }

    const habitInput: HabitInput = {
      name: result.data.name,
      description: result.data.description,
      min_daily_frequency: result.data.min_daily_frequency,
    };

    setIsSaving(true);
    try {
      await onSave(habitInput);
    } catch {
      setErrors({ general: ["Failed to save habit"] });
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!onDelete) return;

    setIsDeleting(true);
    try {
      await onDelete();
    } catch {
      setErrors({ general: ["Failed to delete habit"] });
    } finally {
      setIsDeleting(false);
    }
  };

  const isLoading = isSaving || isDeleting;

  const allErrors = Object.values(errors).flat();

  const handleColorEdit = (tag: Tag) => {
    setEditingTag(tag);
    setShowColorPicker(true);
  };

  const handleColorSelect = async (color: string) => {
    if (editingTag) {
      await updateTag(editingTag.id, { color_hex: color });
      setEditingTag(null);
    }
  };

  const frequencySummary = habit ? formatFrequencySummary(habit.min_daily_frequency) : null;

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      className="flex-1"
    >
      <ScrollView className="flex-1 p-4">
        {/* Header */}
        <View className="flex-row items-center justify-between mb-6">
          <Pressable onPress={onCancel} disabled={isLoading}>
            <Ionicons name="close" size={28} color="var(--color-muted)" />
          </Pressable>
          {isEditing && (
            <Pressable onPress={handleSave} disabled={isLoading}>
              {isSaving ? (
                <ActivityIndicator color="var(--color-accent-secondary)" />
              ) : (
                <Text className="text-accent-secondary font-semibold text-base">Save</Text>
              )}
            </Pressable>
          )}
        </View>

        {allErrors.length > 0 && (
          <View className="bg-surface border border-accent rounded-lg p-4 mb-4">
            {allErrors.map((error, index) => (
              <Text key={index} className="text-accent text-sm">
                {error}
              </Text>
            ))}
          </View>
        )}

        <View className="gap-4">
          {/* Name input */}
          <TextInput
            className={`border-b px-1 py-3 text-lg text-foreground ${errors.name ? "border-accent" : "border-border"}`}
            placeholder="Habit name"
            placeholderTextColor="var(--color-muted)"
            value={name}
            onChangeText={setName}
            editable={!isLoading}
            maxLength={100}
          />

          {/* Description input */}
          <TextInput
            className={`border-b px-1 py-3 text-base text-foreground ${errors.description ? "border-accent" : "border-border"}`}
            placeholder="Description (optional)"
            placeholderTextColor="var(--color-muted)"
            value={description}
            onChangeText={setDescription}
            multiline
            numberOfLines={2}
            style={{ textAlignVertical: "top" }}
            editable={!isLoading}
            maxLength={10000}
          />

          {/* Show more / summary line */}
          {isEditing && !showMore && (frequencySummary || habitTags.length > 0) && (
            <View className="flex-row flex-wrap items-center gap-2">
              {frequencySummary && (
                <Text className="text-accent-secondary text-sm">{frequencySummary}</Text>
              )}
              {habitTags.map((tag) => (
                <View
                  key={tag.id}
                  className="px-2 py-0.5 rounded-full"
                  style={{ backgroundColor: tag.color_hex + "30" }}
                >
                  <Text className="text-xs font-medium" style={{ color: tag.color_hex }}>
                    {tag.name}
                  </Text>
                </View>
              ))}
            </View>
          )}

          <Pressable
            onPress={() => setShowMore(!showMore)}
            className="flex-row items-center gap-1"
          >
            <Text className="text-muted text-sm">
              {showMore ? "Show less" : "Show more"}
            </Text>
            <Ionicons
              name={showMore ? "chevron-up" : "chevron-down"}
              size={16}
              color="var(--color-muted)"
            />
          </Pressable>

          {/* Collapsible section */}
          {showMore && (
            <View className="gap-4">
              {/* Frequency */}
              <View>
                <Text className="text-sm font-medium text-muted mb-1">
                  Frequency
                </Text>
                <View className="flex-row gap-2 mb-2">
                  <TextInput
                    className={`flex-1 border rounded-lg px-4 py-3 text-base text-foreground bg-surface ${errors.min_daily_frequency ? "border-accent" : "border-border"}`}
                    placeholder="e.g., 1, 2, 3"
                    placeholderTextColor="var(--color-muted)"
                    value={minDailyFrequency}
                    onChangeText={setMinDailyFrequency}
                    keyboardType="decimal-pad"
                    editable={!isLoading}
                  />
                  <Text className="self-center text-muted">per</Text>
                </View>
                <View className="flex-row gap-2">
                  {(["day", "week", "month"] as const).map((period) => (
                    <Pressable
                      key={period}
                      onPress={() => setFrequencyPeriod(period)}
                      disabled={isLoading}
                      className={`flex-1 py-2 px-3 rounded-lg items-center border ${
                        frequencyPeriod === period
                          ? "bg-accent border-accent"
                          : "bg-surface border-border"
                      }`}
                    >
                      <Text
                        className={`font-medium ${
                          frequencyPeriod === period ? "text-white" : "text-foreground"
                        }`}
                      >
                        {period.charAt(0).toUpperCase() + period.slice(1)}
                      </Text>
                    </Pressable>
                  ))}
                </View>
              </View>

              {/* Tags Section (only for editing) */}
              {isEditing && habit && (
                <View>
                  <Text className="text-sm font-medium text-muted mb-2">
                    Tags
                  </Text>
                  <View className="flex-row flex-wrap gap-2 mb-2">
                    {habitTags.length === 0 ? (
                      <Text className="text-muted text-sm">No tags assigned</Text>
                    ) : (
                      habitTags.map((tag) => (
                        <View
                          key={tag.id}
                          className="px-3 py-1.5 rounded-full flex-row items-center"
                          style={{ backgroundColor: tag.color_hex + "30" }}
                        >
                          <Text
                            className="text-sm font-medium"
                            style={{ color: tag.color_hex }}
                          >
                            {tag.name}
                          </Text>
                        </View>
                      ))
                    )}
                  </View>
                  <Pressable
                    onPress={() => setShowTagModal(true)}
                    disabled={isLoading}
                    className="border border-border py-2 px-4 rounded-lg flex-row items-center justify-center"
                  >
                    <Ionicons name="pricetags-outline" size={16} color="var(--color-muted)" />
                    <Text className="text-muted ml-2">Manage Tags</Text>
                  </Pressable>
                </View>
              )}
            </View>
          )}

          {/* Create button (only in create mode) */}
          {!isEditing && (
            <Pressable
              onPress={handleSave}
              disabled={isLoading}
              className="bg-accent py-3 px-6 rounded-lg items-center mt-4"
            >
              {isSaving ? (
                <ActivityIndicator color="white" />
              ) : (
                <Text className="text-white font-semibold text-base">Create</Text>
              )}
            </Pressable>
          )}

          {/* Complete button - hero action (only in edit mode) */}
          {isEditing && onComplete && habit && (
            <View className="mt-6">
              <Pressable
                onPress={() => onComplete(habit)}
                disabled={isLoading}
                className="bg-accent py-4 px-6 rounded-lg items-center"
              >
                <Text className="text-white font-bold text-lg">
                  Complete
                </Text>
              </Pressable>
            </View>
          )}

          {/* Bottom actions (edit mode only) */}
          {isEditing && (
            <View className="flex-row justify-between items-center mt-4">
              {onRerank && (
                <Pressable onPress={onRerank} disabled={isLoading}>
                  <Text className="text-muted text-sm">
                    {habit?.difficulty_rank ? "Re-rank difficulty" : "Set difficulty"}
                  </Text>
                </Pressable>
              )}
              {onDelete && (
                <Pressable onPress={handleDelete} disabled={isLoading}>
                  {isDeleting ? (
                    <ActivityIndicator color="var(--color-accent)" size="small" />
                  ) : (
                    <Text className="text-muted text-sm">Delete</Text>
                  )}
                </Pressable>
              )}
            </View>
          )}
        </View>
      </ScrollView>

      {/* Tag Selection Modal */}
      {isEditing && habit && (
        <TagSelectionModal
          visible={showTagModal}
          onClose={() => setShowTagModal(false)}
          habitId={habit.id}
          userId={userId}
          selectedTagIds={habitTags.map((t) => t.id)}
          onColorEdit={handleColorEdit}
        />
      )}

      {/* Color Picker Modal */}
      <ColorPickerModal
        visible={showColorPicker}
        onClose={() => {
          setShowColorPicker(false);
          setEditingTag(null);
        }}
        currentColor={editingTag?.color_hex ?? "#6366f1"}
        onColorSelect={handleColorSelect}
      />
    </KeyboardAvoidingView>
  );
}
