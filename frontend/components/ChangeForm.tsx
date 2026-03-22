import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  Alert,
  ActivityIndicator,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { z } from "zod";
import type { Tag, TagInput } from "@/lib/tag";

function confirmDiscard(title: string, message: string, onDiscard: () => void) {
  if (Platform.OS === "web") {
    if (window.confirm(`${title}\n${message}`)) {
      onDiscard();
    }
  } else {
    Alert.alert(title, message, [
      { text: "Cancel", style: "cancel" },
      { text: "Discard", style: "destructive", onPress: onDiscard },
    ]);
  }
}
import type { FrequencyPeriod } from "@/lib/frequency";
import { formatFrequencySummary, fromDailyFrequency } from "@/lib/frequency";
import { parseZodErrors, buildFrequencyInput } from "@/lib/formValidation";
import { getVisiblePills } from "@/lib/formUtils";
import { FieldPillRow } from "./FieldPillRow";
import { FieldEditSheet } from "./FieldEditSheet";
import { TagSelectionModal } from "./TagSelectionModal";
import { ColorPickerModal } from "./ColorPickerModal";
import { TradeHistory } from "./TradeHistory";

export interface ChangeFormConfig {
  entityType: "habit" | "reward";
  entityLabel: string;
  frequencyLabel: string;
  frequencyField: string;
  frequencyPrefix?: string;
  rankLabel: string;
  actionLabel: string;
}

export interface ChangeFormEntity {
  id: string;
  user_id: string;
  name: string;
  description: string;
  min_daily_frequency?: number | null;
  max_daily_frequency?: number | null;
  difficulty_rank?: string | null;
  damage_rank?: string | null;
}

export interface ChangeFormProps {
  config: ChangeFormConfig;
  entity?: ChangeFormEntity | null;
  userId: string;
  tags: Tag[];
  tradeAmount?: number | null;
  onSave: (input: Record<string, unknown>) => Promise<void>;
  onClose: () => void;
  onDelete?: () => Promise<void>;
  onRerank?: () => void;
  onAction?: (entity: ChangeFormEntity) => Promise<void>;
  tagActions: {
    addTag: (userId: string, entityId: string, tagId: string) => Promise<unknown>;
    removeTag: (entityId: string, tagId: string) => Promise<unknown>;
  };
  updateTag: (id: string, input: Partial<TagInput>) => Promise<unknown>;
}

const nameSchema = z
  .string()
  .min(1, "Name is required")
  .max(100, "Name must be 100 characters or less");

const descriptionSchema = z
  .string()
  .max(10000, "Description must be 10,000 characters or less");

const frequencySchema = z
  .number()
  .gt(0, "Frequency must be greater than 0")
  .lte(100, "Frequency must be 100 or less")
  .nullable();

type ActiveSheet = "name" | "description" | "frequency" | null;

export function ChangeForm({
  config,
  entity,
  userId,
  tags,
  tradeAmount,
  onSave,
  onClose,
  onDelete,
  onRerank,
  onAction,
  tagActions,
  updateTag,
}: ChangeFormProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [frequencyStr, setFrequencyStr] = useState("");
  const [frequencyPeriod, setFrequencyPeriod] = useState<FrequencyPeriod>("day");
  const [errors, setErrors] = useState<Record<string, string[]>>({});
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [activeSheet, setActiveSheet] = useState<ActiveSheet>(null);

  const [showTagModal, setShowTagModal] = useState(false);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [editingTag, setEditingTag] = useState<Tag | null>(null);

  const isEditing = !!entity;
  const nameInputRef = useRef<TextInput>(null);

  // Track original values for revert on empty name
  const originalName = useRef("");

  // Get the frequency value from the entity
  const getEntityFrequency = useCallback(
    (e: ChangeFormEntity | null | undefined): number | null => {
      if (!e) return null;
      return config.frequencyField === "min_daily_frequency"
        ? (e.min_daily_frequency ?? null)
        : (e.max_daily_frequency ?? null);
    },
    [config.frequencyField],
  );

  // Initialize form from entity
  useEffect(() => {
    if (entity) {
      setName(entity.name);
      setDescription(entity.description);
      originalName.current = entity.name;

      const freq = getEntityFrequency(entity);
      if (freq !== null) {
        const { value, period } = fromDailyFrequency(freq);
        setFrequencyPeriod(period);
        setFrequencyStr(String(value));
      } else {
        setFrequencyStr("");
        setFrequencyPeriod("day");
      }
    } else {
      setName("");
      setDescription("");
      setFrequencyStr("");
      setFrequencyPeriod("day");
      originalName.current = "";
    }
  }, [entity, getEntityFrequency]);

  // Auto-open name sheet in create mode
  useEffect(() => {
    if (!entity) {
      setActiveSheet("name");
    }
  }, [entity]);

  // Build the input object for saving
  const buildInput = useCallback((): Record<string, unknown> => {
    const frequency = buildFrequencyInput(frequencyStr, frequencyPeriod);
    return {
      name: name.trim(),
      description: description.trim(),
      [config.frequencyField]: frequency,
    };
  }, [name, description, frequencyStr, frequencyPeriod, config.frequencyField]);

  // Save current field values
  const handleFieldSave = useCallback(async () => {
    if (!isEditing) return;

    const input = buildInput();

    // Validate
    const nameResult = nameSchema.safeParse(input.name);
    const descResult = descriptionSchema.safeParse(input.description);
    const freqResult = frequencySchema.safeParse(input[config.frequencyField]);

    if (!nameResult.success || !descResult.success || !freqResult.success) {
      const allErrors: Record<string, string[]> = {};
      if (!nameResult.success) Object.assign(allErrors, parseZodErrors(nameResult.error));
      if (!descResult.success) Object.assign(allErrors, parseZodErrors(descResult.error));
      if (!freqResult.success) Object.assign(allErrors, { [config.frequencyField]: freqResult.error.issues.map((i) => i.message) });
      setErrors(allErrors);
      return;
    }

    setErrors({});
    setIsSaving(true);
    try {
      await onSave(input);
    } catch {
      setErrors({ general: [`Failed to save ${config.entityLabel.toLowerCase()}`] });
    } finally {
      setIsSaving(false);
    }
  }, [isEditing, buildInput, onSave, config.frequencyField, config.entityLabel]);

  // Close a field sheet (saves in edit mode)
  const closeSheet = useCallback(
    async (sheet: ActiveSheet) => {
      if (sheet === "name" && !isEditing) {
        // Create mode: closing name sheet
        const trimmedName = name.trim();
        if (!trimmedName) {
          confirmDiscard(
            `Discard New ${config.entityLabel}?`,
            "No name was entered.",
            onClose,
          );
          return;
        }

        // Create the entity with the name
        setIsSaving(true);
        try {
          await onSave({
            name: trimmedName,
            description: "",
            [config.frequencyField]: null,
          });
        } catch {
          setErrors({ general: [`Failed to create ${config.entityLabel.toLowerCase()}`] });
        } finally {
          setIsSaving(false);
        }
        setActiveSheet(null);
        return;
      }

      if (sheet === "name" && isEditing) {
        const trimmedName = name.trim();
        if (!trimmedName) {
          confirmDiscard("Discard changes?", "Name cannot be empty.", () => {
            setName(originalName.current);
            setActiveSheet(null);
          });
          return;
        }
      }

      setActiveSheet(null);
      await handleFieldSave();
    },
    [isEditing, name, config.entityLabel, config.frequencyField, onSave, onClose, handleFieldSave],
  );

  const handleDelete = useCallback(async () => {
    if (!onDelete) return;
    setIsDeleting(true);
    try {
      await onDelete();
    } catch {
      setErrors({ general: [`Failed to delete ${config.entityLabel.toLowerCase()}`] });
    } finally {
      setIsDeleting(false);
    }
  }, [onDelete, config.entityLabel]);

  const handleColorEdit = useCallback((tag: Tag) => {
    setEditingTag(tag);
    setShowColorPicker(true);
  }, []);

  const handleColorSelect = useCallback(
    async (color: string) => {
      if (editingTag) {
        await updateTag(editingTag.id, { color_hex: color });
        setEditingTag(null);
      }
    },
    [editingTag, updateTag],
  );

  // Frequency summary for pill display
  const frequencySummary = useMemo(() => {
    const freq = getEntityFrequency(entity);
    return freq !== null ? formatFrequencySummary(freq, config.frequencyPrefix) : null;
  }, [entity, getEntityFrequency, config.frequencyPrefix]);

  // Build pills
  const pills = useMemo(() => {
    return getVisiblePills({
      description: isEditing ? entity?.description ?? "" : description,
      tags: tags.map((t) => t.id),
      frequency: frequencySummary,
      frequencyLabel: config.frequencyLabel,
      rankLabel: config.rankLabel,
      isCreateMode: !isEditing,
    });
  }, [isEditing, entity, description, tags, frequencySummary, config.frequencyLabel, config.rankLabel]);

  const pillActions = useMemo(
    () =>
      pills.map((pill) => ({
        ...pill,
        onPress: () => {
          switch (pill.key) {
            case "description":
              setActiveSheet("description");
              break;
            case "tags":
              setShowTagModal(true);
              break;
            case "frequency":
              setActiveSheet("frequency");
              break;
            case "rank":
              onRerank?.();
              break;
          }
        },
      })),
    [pills, onRerank],
  );

  const isLoading = isSaving || isDeleting;
  const allErrors = Object.values(errors).flat();

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      className="flex-1"
    >
      <ScrollView className="flex-1 p-4">
        {/* Header */}
        <View className="flex-row items-center justify-between mb-6">
          <Pressable onPress={onClose} disabled={isLoading}>
            {isSaving ? (
              <ActivityIndicator color="var(--color-muted)" />
            ) : (
              <Ionicons name="close" size={28} color="var(--color-muted)" />
            )}
          </Pressable>
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
          {/* Name - pressable text */}
          <Pressable onPress={() => setActiveSheet("name")}>
            <Text
              className={`text-lg ${name.trim() ? "text-foreground" : "text-muted"}`}
              numberOfLines={2}
            >
              {name.trim() || `${config.entityLabel} name`}
            </Text>
          </Pressable>

          {/* Description - pressable text (only shown when set) */}
          {isEditing && (entity?.description || description) ? (
            <Pressable onPress={() => setActiveSheet("description")}>
              <Text className="text-foreground text-base" numberOfLines={3}>
                {entity?.description || description}
              </Text>
            </Pressable>
          ) : null}

          {/* Tags row (only in edit mode with tags) */}
          {isEditing && tags.length > 0 && (
            <Pressable onPress={() => setShowTagModal(true)}>
              <View className="flex-row flex-wrap gap-2">
                {tags.map((tag) => (
                  <View
                    key={tag.id}
                    className="px-3 py-1.5 rounded-full"
                    style={{ backgroundColor: tag.color_hex + "30" }}
                  >
                    <Text className="text-sm font-medium" style={{ color: tag.color_hex }}>
                      {tag.name}
                    </Text>
                  </View>
                ))}
              </View>
            </Pressable>
          )}

          {/* Pill row */}
          <FieldPillRow pills={pillActions} />

          {/* Hero action button (edit mode) */}
          {isEditing && entity && (() => {
            const hasRank = config.entityType === "habit"
              ? entity.difficulty_rank != null
              : entity.damage_rank != null;
            if (hasRank && onAction) {
              const amountStr = tradeAmount != null
                ? ` ${tradeAmount > 0 ? "+" : ""}${tradeAmount}`
                : "";
              return (
                <View className="mt-6">
                  <Pressable
                    onPress={() => onAction(entity)}
                    disabled={isLoading}
                    className="bg-accent py-4 px-6 rounded-lg items-center"
                  >
                    <Text className="text-white font-bold text-lg">
                      {config.actionLabel}{amountStr}
                    </Text>
                  </Pressable>
                </View>
              );
            }
            if (!hasRank && onRerank) {
              const setRankLabel = config.entityType === "habit"
                ? "Set Difficulty"
                : "Set Damage";
              return (
                <View className="mt-6">
                  <Pressable
                    onPress={onRerank}
                    disabled={isLoading}
                    className="bg-surface py-4 px-6 rounded-lg items-center"
                  >
                    <Text className="text-muted font-bold text-lg">
                      {setRankLabel}
                    </Text>
                  </Pressable>
                </View>
              );
            }
            return null;
          })()}

          {/* Delete button (edit mode) */}
          {isEditing && onDelete && (
            <Pressable
              onPress={handleDelete}
              disabled={isLoading}
              className="bg-surface py-4 px-6 rounded-lg items-center"
            >
              {isDeleting ? (
                <ActivityIndicator color="var(--color-muted)" />
              ) : (
                <Text className="text-muted font-bold text-lg">Delete</Text>
              )}
            </Pressable>
          )}

          {/* Trade history (edit mode) */}
          {isEditing && entity && (
            <TradeHistory
              userId={userId}
              {...(config.entityType === "habit"
                ? { habitId: entity.id }
                : { rewardId: entity.id })}
            />
          )}
        </View>
      </ScrollView>

      {/* Name edit sheet */}
      <FieldEditSheet
        visible={activeSheet === "name"}
        onClose={() => closeSheet("name")}
        title="Name"
      >
        <TextInput
          ref={nameInputRef}
          className="border-b border-border px-1 py-3 text-lg text-foreground"
          placeholder={`${config.entityLabel} name`}
          placeholderTextColor="var(--color-muted)"
          value={name}
          onChangeText={setName}
          autoFocus
          maxLength={100}
          onSubmitEditing={() => closeSheet("name")}
        />
      </FieldEditSheet>

      {/* Description edit sheet */}
      <FieldEditSheet
        visible={activeSheet === "description"}
        onClose={() => closeSheet("description")}
        title="Description"
      >
        <TextInput
          className="border-b border-border px-1 py-3 text-base text-foreground"
          placeholder="Description (optional)"
          placeholderTextColor="var(--color-muted)"
          value={description}
          onChangeText={setDescription}
          multiline
          numberOfLines={4}
          style={{ textAlignVertical: "top", minHeight: 120 }}
          autoFocus
          maxLength={10000}
        />
      </FieldEditSheet>

      {/* Frequency edit sheet */}
      <FieldEditSheet
        visible={activeSheet === "frequency"}
        onClose={() => closeSheet("frequency")}
        title={config.frequencyLabel}
      >
        <View className="gap-4">
          <View className="flex-row gap-2">
            <TextInput
              className="flex-1 border rounded-lg px-4 py-3 text-base text-foreground bg-surface border-border"
              placeholder="e.g., 1, 2, 3"
              placeholderTextColor="var(--color-muted)"
              value={frequencyStr}
              onChangeText={setFrequencyStr}
              keyboardType="decimal-pad"
              autoFocus
            />
            <Text className="self-center text-muted">per</Text>
          </View>
          <View className="flex-row gap-2">
            {(["day", "week", "month"] as const).map((period) => (
              <Pressable
                key={period}
                onPress={() => setFrequencyPeriod(period)}
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
      </FieldEditSheet>

      {/* Tag Selection Modal */}
      {isEditing && entity && (
        <TagSelectionModal
          visible={showTagModal}
          onClose={() => {
            setShowTagModal(false);
            handleFieldSave();
          }}
          entityId={entity.id}
          userId={userId}
          selectedTagIds={tags.map((t) => t.id)}
          onColorEdit={handleColorEdit}
          addTag={tagActions.addTag}
          removeTag={tagActions.removeTag}
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
