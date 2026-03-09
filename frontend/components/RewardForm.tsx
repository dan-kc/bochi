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
import { useTagsForReward, useTagActions } from "@/lib/store/hooks";
import { RewardTagSelectionModal } from "./RewardTagSelectionModal";
import { ColorPickerModal } from "./ColorPickerModal";

interface RewardFormProps {
  reward?: Reward | null;
  userId: string;
  onSave: (input: RewardInput) => Promise<void>;
  onCancel: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
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

type FrequencyPeriod = "day" | "week" | "month";

const PERIOD_DIVISORS: Record<FrequencyPeriod, number> = {
  day: 1,
  week: 7,
  month: 30,
};

export function RewardForm({ reward, userId, onSave, onCancel, onDelete, onRerank }: RewardFormProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [maxDailyFrequency, setMaxDailyFrequency] = useState("");
  const [frequencyPeriod, setFrequencyPeriod] = useState<FrequencyPeriod>("day");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[]>>({});

  // Tag selection state
  const [showTagModal, setShowTagModal] = useState(false);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [editingTag, setEditingTag] = useState<Tag | null>(null);

  const isEditing = !!reward;

  // Get tags for this reward (only when editing)
  const rewardTags = useTagsForReward(reward?.id ?? "");
  const { updateTag } = useTagActions();

  useEffect(() => {
    if (reward) {
      setName(reward.name);
      setDescription(reward.description);

      if (reward.max_daily_frequency !== null) {
        const dailyFreq = reward.max_daily_frequency;
        // Determine best period to display based on the stored daily frequency
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
        setMaxDailyFrequency(String(displayValue));
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

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      className="flex-1"
    >
      <ScrollView className="flex-1 p-4">
        <View className="flex-row items-center justify-between mb-6">
          <Text className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit" : "New"} Reward
          </Text>
          <View className="bg-red-100 px-3 py-1 rounded-full">
            <Text className="text-red-700 font-medium text-sm">Reward</Text>
          </View>
        </View>

        {allErrors.length > 0 && (
          <View className="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
            {allErrors.map((error, index) => (
              <Text key={index} className="text-red-600 text-sm">
                {error}
              </Text>
            ))}
          </View>
        )}

        <View className="gap-4">
          <View>
            <Text className="text-sm font-medium text-gray-700 mb-1">
              Name *
            </Text>
            <TextInput
              className={`border rounded-lg px-4 py-3 text-base ${errors.name ? "border-red-500" : "border-gray-300"}`}
              placeholder="Reward name"
              value={name}
              onChangeText={setName}
              editable={!isLoading}
              maxLength={100}
            />
            <Text className="text-xs text-gray-500 mt-1">
              {name.length}/100 characters
            </Text>
          </View>

          <View>
            <Text className="text-sm font-medium text-gray-700 mb-1">
              Description
            </Text>
            <TextInput
              className={`border rounded-lg px-4 py-3 text-base ${errors.description ? "border-red-500" : "border-gray-300"}`}
              placeholder="Reward description"
              value={description}
              onChangeText={setDescription}
              multiline
              numberOfLines={4}
              style={{ minHeight: 100, textAlignVertical: "top" }}
              editable={!isLoading}
              maxLength={10000}
            />
            <Text className="text-xs text-gray-500 mt-1">
              {description.length}/10,000 characters
            </Text>
          </View>

          <View>
            <Text className="text-sm font-medium text-gray-700 mb-1">
              Max Frequency
            </Text>
            <View className="flex-row gap-2 mb-2">
              <TextInput
                className={`flex-1 border rounded-lg px-4 py-3 text-base ${errors.max_daily_frequency ? "border-red-500" : "border-gray-300"}`}
                placeholder="e.g., 1, 2, 3"
                value={maxDailyFrequency}
                onChangeText={setMaxDailyFrequency}
                keyboardType="decimal-pad"
                editable={!isLoading}
              />
              <Text className="self-center text-gray-500">per</Text>
            </View>
            <View className="flex-row gap-2">
              {(["day", "week", "month"] as const).map((period) => (
                <Pressable
                  key={period}
                  onPress={() => setFrequencyPeriod(period)}
                  disabled={isLoading}
                  className={`flex-1 py-2 px-3 rounded-lg items-center border ${
                    frequencyPeriod === period
                      ? "bg-red-500 border-red-500"
                      : "bg-white border-gray-300"
                  }`}
                >
                  <Text
                    className={`font-medium ${
                      frequencyPeriod === period ? "text-white" : "text-gray-700"
                    }`}
                  >
                    {period.charAt(0).toUpperCase() + period.slice(1)}
                  </Text>
                </Pressable>
              ))}
            </View>
            <Text className="text-xs text-gray-500 mt-2">
              {frequencyPeriod === "day" && "Max times per day (e.g., 1 = once daily, 2 = twice daily)"}
              {frequencyPeriod === "week" && "Max times per week (e.g., 3 = three times a week)"}
              {frequencyPeriod === "month" && "Max times per month (e.g., 2 = twice a month)"}
            </Text>
          </View>

          {/* Tags Section (only for editing) */}
          {isEditing && reward && (
            <View>
              <Text className="text-sm font-medium text-gray-700 mb-2">
                Tags
              </Text>
              <View className="flex-row flex-wrap gap-2 mb-2">
                {rewardTags.length === 0 ? (
                  <Text className="text-gray-500 text-sm">No tags assigned</Text>
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
                className="border border-gray-300 py-2 px-4 rounded-lg flex-row items-center justify-center"
              >
                <Ionicons name="pricetags-outline" size={16} color="#6b7280" />
                <Text className="text-gray-600 ml-2">Manage Tags</Text>
              </Pressable>
            </View>
          )}

          <View className="flex-row gap-3 mt-4">
            <Pressable
              onPress={onCancel}
              disabled={isLoading}
              className="flex-1 border border-gray-300 py-3 px-6 rounded-lg items-center"
            >
              <Text className="text-gray-700 font-semibold text-base">
                Cancel
              </Text>
            </Pressable>
            <Pressable
              onPress={handleSave}
              disabled={isLoading}
              className="flex-1 py-3 px-6 rounded-lg items-center bg-red-500"
            >
              {isSaving ? (
                <ActivityIndicator color="white" />
              ) : (
                <Text className="text-white font-semibold text-base">
                  {isEditing ? "Save" : "Create"}
                </Text>
              )}
            </Pressable>
          </View>

          {isEditing && onRerank && (
            <Pressable
              onPress={onRerank}
              disabled={isLoading}
              className="border border-red-300 py-3 px-6 rounded-lg items-center mt-2"
            >
              <Text className="text-red-600 font-semibold text-base">
                {reward?.damage_rank ? "Re-rank Damage" : "Set Damage"}
              </Text>
            </Pressable>
          )}

          {isEditing && onDelete && (
            <Pressable
              onPress={handleDelete}
              disabled={isLoading}
              className="border border-red-300 py-3 px-6 rounded-lg items-center mt-2"
            >
              {isDeleting ? (
                <ActivityIndicator color="#dc2626" />
              ) : (
                <Text className="text-red-600 font-semibold text-base">
                  Delete Reward
                </Text>
              )}
            </Pressable>
          )}
        </View>
      </ScrollView>

      {/* Tag Selection Modal */}
      {isEditing && reward && (
        <RewardTagSelectionModal
          visible={showTagModal}
          onClose={() => setShowTagModal(false)}
          rewardId={reward.id}
          userId={userId}
          selectedTagIds={rewardTags.map((t) => t.id)}
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
