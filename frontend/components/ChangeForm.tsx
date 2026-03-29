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
  StyleSheet,
} from "react-native";
import Animated, { FadeIn, LinearTransition } from "react-native-reanimated";
import { Ionicons } from "@expo/vector-icons";
import { z } from "zod";
import type { Tag, TagInput } from "@/lib/tag";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

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
  const colors = useColors();
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

  // Description value that only updates from entity sync or after successful saves
  const [savedDescription, setSavedDescription] = useState(entity?.description ?? "");

  // Delay enabling animations until after the initial layout has settled,
  // so entering/layout animations only fire for user-driven changes
  const [isSettled, setIsSettled] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setIsSettled(true), 100);
    return () => clearTimeout(timer);
  }, []);

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
      setSavedDescription(entity.description);
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
      setSavedDescription(description.trim());
    } catch {
      setErrors({ general: [`Failed to save ${config.entityLabel.toLowerCase()}`] });
    } finally {
      setIsSaving(false);
    }
  }, [isEditing, buildInput, onSave, config.frequencyField, config.entityLabel, description]);

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
      description: isEditing ? savedDescription : description,
      tags: tags.map((t) => t.id),
      frequency: frequencySummary,
      frequencyLabel: config.frequencyLabel,
      rankLabel: config.rankLabel,
      isCreateMode: !isEditing,
    });
  }, [isEditing, savedDescription, description, tags, frequencySummary, config.frequencyLabel, config.rankLabel]);

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
              // Tags can only be added after entity is created
              if (isEditing) {
                setShowTagModal(true);
              }
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
    [pills, onRerank, isEditing],
  );

  const isLoading = isSaving || isDeleting;
  const allErrors = Object.values(errors).flat();

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      style={styles.flex1}
    >
      <ScrollView style={[styles.flex1, styles.scrollContent]}>
        {/* Header */}
        <View style={styles.header}>
          <Pressable onPress={onClose} disabled={isLoading}>
            {isSaving ? (
              <ActivityIndicator color={colors.muted} />
            ) : (
              <Ionicons name="close" size={28} color={colors.muted} />
            )}
          </Pressable>
        </View>

        {allErrors.length > 0 && (
          <View style={[styles.errorContainer, { backgroundColor: colors.surface, borderColor: colors.accent }]}>
            {allErrors.map((error, index) => (
              <Text key={index} style={[styles.errorText, { color: colors.accent }]}>
                {error}
              </Text>
            ))}
          </View>
        )}

        <View style={styles.contentGap}>
          {/* Name - pressable text */}
          <Pressable onPress={() => setActiveSheet("name")}>
            <Text
              style={[styles.nameText, { color: name.trim() ? colors.foreground : colors.muted }]}
              numberOfLines={2}
            >
              {name.trim() || `${config.entityLabel} name`}
            </Text>
          </Pressable>

          {/* Description - pressable text (only shown when set) */}
          {isEditing && savedDescription ? (
            <Animated.View
              entering={isSettled ? FadeIn.duration(250) : undefined}
            >
              <Pressable onPress={() => setActiveSheet("description")}>
                <Text style={[styles.descriptionText, { color: colors.foreground }]} numberOfLines={3}>
                  {savedDescription}
                </Text>
              </Pressable>
            </Animated.View>
          ) : null}

          {/* Tags row (only in edit mode with tags) */}
          {isEditing && tags.length > 0 && (
            <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined}>
              <Pressable onPress={() => setShowTagModal(true)}>
                <View style={styles.tagRow}>
                  {tags.map((tag) => (
                    <View
                      key={tag.id}
                      style={[styles.tag, { backgroundColor: tag.color_hex + "30" }]}
                    >
                      <Text style={[styles.tagText, { color: tag.color_hex }]}>
                        {tag.name}
                      </Text>
                    </View>
                  ))}
                </View>
              </Pressable>
            </Animated.View>
          )}

          {/* Pill row */}
          <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined}>
            <FieldPillRow pills={pillActions} isSettled={isSettled} />
          </Animated.View>

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
                <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined} style={styles.heroButton}>
                  <Pressable
                    onPress={() => onAction(entity)}
                    disabled={isLoading}
                    style={[styles.actionButton, { backgroundColor: colors.accent }]}
                  >
                    <Text style={[styles.actionButtonText, { color: colors.white }]}>
                      {config.actionLabel}{amountStr}
                    </Text>
                  </Pressable>
                </Animated.View>
              );
            }
            if (!hasRank && onRerank) {
              const setRankLabel = config.entityType === "habit"
                ? "Set Difficulty"
                : "Set Damage";
              return (
                <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined} style={styles.heroButton}>
                  <Pressable
                    onPress={onRerank}
                    disabled={isLoading}
                    style={[styles.actionButton, { backgroundColor: colors.surface }]}
                  >
                    <Text style={[styles.actionButtonText, { color: colors.muted }]}>
                      {setRankLabel}
                    </Text>
                  </Pressable>
                </Animated.View>
              );
            }
            return null;
          })()}

          {/* Delete button (edit mode) */}
          {isEditing && onDelete && (
            <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined}>
              <Pressable
                onPress={handleDelete}
                disabled={isLoading}
                style={[styles.actionButton, { backgroundColor: colors.surface }]}
              >
                {isDeleting ? (
                  <ActivityIndicator color={colors.muted} />
                ) : (
                  <Text style={[styles.actionButtonText, { color: colors.muted }]}>Delete</Text>
                )}
              </Pressable>
            </Animated.View>
          )}

          {/* Trade history (edit mode) */}
          {isEditing && entity && (
            <Animated.View layout={isSettled ? LinearTransition.duration(250) : undefined}>
              <TradeHistory
                userId={userId}
                {...(config.entityType === "habit"
                  ? { habitId: entity.id }
                  : { rewardId: entity.id })}
              />
            </Animated.View>
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
          style={[styles.sheetInput, { borderBottomColor: colors.border, color: colors.foreground }]}
          placeholder={`${config.entityLabel} name`}
          placeholderTextColor={colors.muted}
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
          style={[styles.sheetInputMultiline, { borderBottomColor: colors.border, color: colors.foreground }]}
          placeholder="Description (optional)"
          placeholderTextColor={colors.muted}
          value={description}
          onChangeText={setDescription}
          multiline
          numberOfLines={4}
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
        <View style={styles.frequencyContainer}>
          <View style={styles.frequencyInputRow}>
            <TextInput
              style={[styles.frequencyInput, { borderColor: colors.border, backgroundColor: colors.surface, color: colors.foreground }]}
              placeholder="e.g., 1, 2, 3"
              placeholderTextColor={colors.muted}
              value={frequencyStr}
              onChangeText={setFrequencyStr}
              keyboardType="decimal-pad"
              autoFocus
            />
            <Text style={[styles.frequencyPer, { color: colors.muted }]}>per</Text>
          </View>
          <View style={styles.frequencyPeriodRow}>
            {(["day", "week", "month"] as const).map((period) => (
              <Pressable
                key={period}
                onPress={() => setFrequencyPeriod(period)}
                style={[
                  styles.frequencyPeriodButton,
                  {
                    backgroundColor: frequencyPeriod === period ? colors.accent : colors.surface,
                    borderColor: frequencyPeriod === period ? colors.accent : colors.border,
                  }
                ]}
              >
                <Text
                  style={[
                    styles.frequencyPeriodText,
                    { color: frequencyPeriod === period ? colors.white : colors.foreground }
                  ]}
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

const styles = StyleSheet.create({
  flex1: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing[4],
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: spacing[6],
  },
  errorContainer: {
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    padding: spacing[4],
    marginBottom: spacing[4],
  },
  errorText: {
    fontSize: fontSize.sm,
  },
  contentGap: {
    gap: spacing[4],
  },
  nameText: {
    fontSize: fontSize.lg,
  },
  descriptionText: {
    fontSize: fontSize.base,
  },
  tagRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: spacing[2],
  },
  tag: {
    paddingHorizontal: spacing[3],
    paddingVertical: spacing[1.5],
    borderRadius: borderRadius.full,
  },
  tagText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
  heroButton: {
    marginTop: spacing[6],
  },
  actionButton: {
    paddingVertical: spacing[4],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  actionButtonText: {
    fontWeight: fontWeight.bold,
    fontSize: fontSize.lg,
  },
  sheetInput: {
    borderBottomWidth: 1,
    paddingHorizontal: spacing[1],
    paddingVertical: spacing[3],
    fontSize: fontSize.lg,
  },
  sheetInputMultiline: {
    borderBottomWidth: 1,
    paddingHorizontal: spacing[1],
    paddingVertical: spacing[3],
    fontSize: fontSize.base,
    textAlignVertical: "top",
    minHeight: 120,
  },
  frequencyContainer: {
    gap: spacing[4],
  },
  frequencyInputRow: {
    flexDirection: "row",
    gap: spacing[2],
  },
  frequencyInput: {
    flex: 1,
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    fontSize: fontSize.base,
  },
  frequencyPer: {
    alignSelf: "center",
  },
  frequencyPeriodRow: {
    flexDirection: "row",
    gap: spacing[2],
  },
  frequencyPeriodButton: {
    flex: 1,
    paddingVertical: spacing[2],
    paddingHorizontal: spacing[3],
    borderRadius: borderRadius.lg,
    alignItems: "center",
    borderWidth: 1,
  },
  frequencyPeriodText: {
    fontWeight: fontWeight.medium,
  },
});
