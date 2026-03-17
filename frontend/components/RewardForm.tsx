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
import type { Reward, RewardInput } from "@/lib/reward";
import { createEmptyRewardInput } from "@/lib/reward";
import type { Tag } from "@/lib/tag";
import { useTagsForReward, useTagActions, useRewardTagActions } from "@/lib/store/hooks";
import { TagSelectionModal } from "./TagSelectionModal";
import { ColorPickerModal } from "./ColorPickerModal";
import { TradeHistory } from "./TradeHistory";
import type { FrequencyPeriod } from "@/lib/frequency";
import { PERIOD_DIVISORS, formatFrequencySummary, fromDailyFrequency } from "@/lib/frequency";
import { parseZodErrors } from "@/lib/formValidation";

interface RewardFormProps {
  reward?: Reward | null;
  userId: string;
  onSave: (input: RewardInput) => Promise<void>;
  onCancel: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
  onPurchase?: (reward: Reward) => Promise<void>;
}

const rewardSchema = z.object({
  name: z
    .string()
    .min(1, "Name is required")
    .max(100, "Name must be 100 characters or less"),
  description: z
    .string()
    .max(10000, "Description must be 10,000 characters or less"),
  max_daily_frequency: z
    .number()
    .gt(0, "Frequency must be greater than 0")
    .lte(100, "Frequency must be 100 or less")
    .nullable(),
});

export function RewardForm({ reward, userId, onSave, onCancel, onDelete, onRerank, onPurchase }: RewardFormProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [maxDailyFrequency, setMaxDailyFrequency] = useState("");
  const [frequencyPeriod, setFrequencyPeriod] = useState<FrequencyPeriod>("day");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[]>>({});
  const [showMore, setShowMore] = useState(false);

  // Tag selection state
  const [showTagModal, setShowTagModal] = useState(false);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [editingTag, setEditingTag] = useState<Tag | null>(null);

  const isEditing = !!reward;

  // Get tags for this reward (only when editing)
  const rewardTags = useTagsForReward(reward?.id ?? "");
  const { updateTag } = useTagActions();
  const { addTagToReward, removeTagFromReward } = useRewardTagActions();

  useEffect(() => {
    if (reward) {
      setName(reward.name);
      setDescription(reward.description);

      if (reward.max_daily_frequency !== null) {
        const { value, period } = fromDailyFrequency(reward.max_daily_frequency);
        setFrequencyPeriod(period);
        setMaxDailyFrequency(String(value));
      } else {
        setMaxDailyFrequency("");
        setFrequencyPeriod("day");
      }
    } else {
      const empty = createEmptyRewardInput();
      setName(empty.name);
      setDescription(empty.description);
      setMaxDailyFrequency("");
      setFrequencyPeriod("day");
    }
  }, [reward]);

  const handleSave = async () => {
    setErrors({});

    const rawFrequency = maxDailyFrequency.trim()
      ? parseFloat(maxDailyFrequency)
      : null;
    const frequency = rawFrequency !== null
      ? rawFrequency / PERIOD_DIVISORS[frequencyPeriod]
      : null;

    const input = {
      name: name.trim(),
      description: description.trim(),
      max_daily_frequency: frequency,
    };

    const result = rewardSchema.safeParse(input);

    if (!result.success) {
      setErrors(parseZodErrors(result.error));
      return;
    }

    const rewardInput: RewardInput = {
      name: result.data.name,
      description: result.data.description,
      max_daily_frequency: result.data.max_daily_frequency,
    };

    setIsSaving(true);
    try {
      await onSave(rewardInput);
    } catch {
      setErrors({ general: ["Failed to save reward"] });
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
      setErrors({ general: ["Failed to delete reward"] });
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

  const frequencySummary = reward ? formatFrequencySummary(reward.max_daily_frequency, "max") : null;

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
            placeholder="Reward name"
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
          {isEditing && !showMore && (frequencySummary || rewardTags.length > 0) && (
            <View className="flex-row flex-wrap items-center gap-2">
              {frequencySummary && (
                <Text className="text-accent-secondary text-sm">{frequencySummary}</Text>
              )}
              {rewardTags.map((tag) => (
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
              {/* Max Frequency */}
              <View>
                <Text className="text-sm font-medium text-muted mb-1">
                  Max Frequency
                </Text>
                <View className="flex-row gap-2 mb-2">
                  <TextInput
                    className={`flex-1 border rounded-lg px-4 py-3 text-base text-foreground bg-surface ${errors.max_daily_frequency ? "border-accent" : "border-border"}`}
                    placeholder="e.g., 1, 2, 3"
                    placeholderTextColor="var(--color-muted)"
                    value={maxDailyFrequency}
                    onChangeText={setMaxDailyFrequency}
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
              {isEditing && reward && (
                <View>
                  <Text className="text-sm font-medium text-muted mb-2">
                    Tags
                  </Text>
                  <View className="flex-row flex-wrap gap-2 mb-2">
                    {rewardTags.length === 0 ? (
                      <Text className="text-muted text-sm">No tags assigned</Text>
                    ) : (
                      rewardTags.map((tag) => (
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

          {/* Purchase button - hero action (only in edit mode) */}
          {isEditing && onPurchase && reward && (
            <View className="mt-6">
              <Pressable
                onPress={() => onPurchase(reward)}
                disabled={isLoading}
                className="bg-accent py-4 px-6 rounded-lg items-center"
              >
                <Text className="text-white font-bold text-lg">
                  Purchase
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
                    {reward?.damage_rank ? "Re-rank damage" : "Set damage"}
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

          {/* Trade history (edit mode only) */}
          {isEditing && reward && (
            <TradeHistory userId={userId} rewardId={reward.id} />
          )}
        </View>
      </ScrollView>

      {/* Tag Selection Modal */}
      {isEditing && reward && (
        <TagSelectionModal
          visible={showTagModal}
          onClose={() => setShowTagModal(false)}
          entityId={reward.id}
          userId={userId}
          selectedTagIds={rewardTags.map((t) => t.id)}
          onColorEdit={handleColorEdit}
          addTag={addTagToReward}
          removeTag={removeTagFromReward}
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
