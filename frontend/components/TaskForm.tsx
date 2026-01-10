import { useState, useEffect, useRef } from "react";
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
import DateTimePicker, {
  DateTimePickerEvent,
} from "@react-native-community/datetimepicker";
import { z } from "zod";
import type { Task, TaskInput } from "@/lib/task";
import { createEmptyTaskInput } from "@/lib/task";

function formatDateForInput(date: Date | null): string {
  if (!date) return "";
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getTomorrowString(): string {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  return formatDateForInput(tomorrow);
}

interface DatePickerFieldProps {
  label: string;
  value: Date | null;
  onChange: (date: Date | null) => void;
  hasError?: boolean;
  disabled?: boolean;
  placeholder?: string;
}

function DatePickerField({
  label,
  value,
  onChange,
  hasError,
  disabled,
  placeholder,
}: DatePickerFieldProps) {
  const [showPicker, setShowPicker] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleNativeChange = (
    event: DateTimePickerEvent,
    selectedDate?: Date,
  ) => {
    setShowPicker(Platform.OS === "ios");
    if (event.type === "set" && selectedDate) {
      onChange(selectedDate);
    }
  };

  const handleWebChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    if (val) {
      onChange(new Date(val + "T00:00:00"));
    } else {
      onChange(null);
    }
  };

  if (Platform.OS === "web") {
    return (
      <View>
        <Text className="text-sm font-medium text-gray-700 mb-1">{label}</Text>
        <Pressable
          onPress={() => inputRef.current?.showPicker?.()}
          disabled={disabled}
          className={`border rounded-lg px-4 py-3 ${hasError ? "border-red-500" : "border-gray-300"}`}
        >
          <input
            ref={inputRef}
            type="date"
            value={formatDateForInput(value)}
            onChange={handleWebChange}
            min={getTomorrowString()}
            disabled={disabled}
            style={{
              border: "none",
              background: "transparent",
              fontSize: 16,
              width: "100%",
              outline: "none",
              color: value ? "#111827" : "#9ca3af",
              cursor: disabled ? "not-allowed" : "pointer",
            }}
          />
        </Pressable>
        {value && (
          <Pressable onPress={() => onChange(null)} className="mt-1">
            <Text className="text-blue-500 text-sm">Clear</Text>
          </Pressable>
        )}
      </View>
    );
  }

  return (
    <View>
      <Text className="text-sm font-medium text-gray-700 mb-1">{label}</Text>
      <Pressable
        onPress={() => setShowPicker(true)}
        disabled={disabled}
        className={`border rounded-lg px-4 py-3 ${hasError ? "border-red-500" : "border-gray-300"}`}
      >
        <Text className={value ? "text-gray-900" : "text-gray-400"}>
          {value ? value.toLocaleDateString() : placeholder || "Select date"}
        </Text>
      </Pressable>
      {value && (
        <Pressable onPress={() => onChange(null)} className="mt-1">
          <Text className="text-blue-500 text-sm">Clear</Text>
        </Pressable>
      )}
      {showPicker && (
        <DateTimePicker
          value={value || new Date()}
          mode="date"
          display="default"
          onChange={handleNativeChange}
          minimumDate={new Date()}
        />
      )}
    </View>
  );
}

interface TaskFormProps {
  task?: Task | null;
  onSave: (input: TaskInput) => Promise<void>;
  onCancel: () => void;
  onDelete?: () => Promise<void>;
}

const taskSchema = z
  .object({
    name: z
      .string()
      .min(1, "Name is required")
      .max(100, "Name must be 100 characters or less"),
    description: z
      .string()
      .max(10000, "Description must be 10,000 characters or less"),
    hidden_until: z
      .date()
      .refine((date) => date > new Date(), {
        message: "Hidden until must be a future date",
      })
      .nullable(),
    due_by: z
      .date()
      .refine((date) => date > new Date(), {
        message: "Due by must be a future date",
      })
      .nullable(),
    min_daily_frequency: z
      .number()
      .gt(0, "Frequency must be greater than 0")
      .lte(100, "Frequency must be 100 or less")
      .nullable(),
  })
  .refine(
    (data) => !(data.due_by !== null && data.min_daily_frequency !== null),
    {
      message: "Cannot set both due date and daily frequency",
      path: ["due_by"],
    },
  );

type TaskMode = "task" | "habit";
type FrequencyPeriod = "day" | "week" | "month";

const PERIOD_DIVISORS: Record<FrequencyPeriod, number> = {
  day: 1,
  week: 7,
  month: 30,
};

export function TaskForm({ task, onSave, onCancel, onDelete }: TaskFormProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [hiddenUntil, setHiddenUntil] = useState<Date | null>(null);
  const [dueBy, setDueBy] = useState<Date | null>(null);
  const [minDailyFrequency, setMinDailyFrequency] = useState("");
  const [frequencyPeriod, setFrequencyPeriod] = useState<FrequencyPeriod>("day");
  const [mode, setMode] = useState<TaskMode>("task");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[]>>({});

  const isEditing = !!task;

  useEffect(() => {
    if (task) {
      setName(task.name);
      setDescription(task.description);
      setHiddenUntil(task.hidden_until ? new Date(task.hidden_until) : null);
      setDueBy(task.due_by ? new Date(task.due_by) : null);

      if (task.min_daily_frequency !== null) {
        const dailyFreq = task.min_daily_frequency;
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
        setMinDailyFrequency(String(displayValue));
      } else {
        setMinDailyFrequency("");
        setFrequencyPeriod("day");
      }
      setMode(task.min_daily_frequency !== null ? "habit" : "task");
    } else {
      const empty = createEmptyTaskInput();
      setName(empty.name);
      setDescription(empty.description);
      setHiddenUntil(null);
      setDueBy(null);
      setMinDailyFrequency("");
      setFrequencyPeriod("day");
      setMode("task");
    }
  }, [task]);

  const handleModeChange = (newMode: TaskMode) => {
    setMode(newMode);
  };

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
      hidden_until: hiddenUntil,
      due_by: mode === "task" ? dueBy : null,
      min_daily_frequency: mode === "habit" ? frequency : null,
    };

    const result = taskSchema.safeParse(input);

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

    const taskInput: TaskInput = {
      name: result.data.name,
      description: result.data.description,
      hidden_until: result.data.hidden_until?.toISOString() ?? null,
      due_by: result.data.due_by?.toISOString() ?? null,
      min_daily_frequency: result.data.min_daily_frequency,
    };

    setIsSaving(true);
    try {
      await onSave(taskInput);
    } catch (error) {
      setErrors({ general: ["Failed to save task"] });
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!onDelete) return;

    setIsDeleting(true);
    try {
      await onDelete();
    } catch (error) {
      setErrors({ general: ["Failed to delete task"] });
    } finally {
      setIsDeleting(false);
    }
  };

  const isLoading = isSaving || isDeleting;

  const allErrors = Object.values(errors).flat();

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      className="flex-1"
    >
      <ScrollView className="flex-1 p-4">
        <View className="flex-row items-center justify-between mb-6">
          <Text className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit" : "New"} {mode === "habit" ? "Habit" : "Task"}
          </Text>
          {mode === "habit" && (
            <View className="bg-purple-100 px-3 py-1 rounded-full">
              <Text className="text-purple-700 font-medium text-sm">Habit</Text>
            </View>
          )}
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
              placeholder="Task name"
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
              placeholder="Task description"
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
            <Text className="text-sm font-medium text-gray-700 mb-2">Type</Text>
            <View className="flex-row gap-2">
              <Pressable
                onPress={() => handleModeChange("task")}
                disabled={isLoading}
                className={`flex-1 py-3 px-4 rounded-lg items-center border ${
                  mode === "task"
                    ? "bg-blue-500 border-blue-500"
                    : "bg-white border-gray-300"
                }`}
              >
                <Text
                  className={`font-semibold ${
                    mode === "task" ? "text-white" : "text-gray-700"
                  }`}
                >
                  Task
                </Text>
                <Text
                  className={`text-xs mt-1 ${
                    mode === "task" ? "text-blue-100" : "text-gray-500"
                  }`}
                >
                  One-time
                </Text>
              </Pressable>
              <Pressable
                onPress={() => handleModeChange("habit")}
                disabled={isLoading}
                className={`flex-1 py-3 px-4 rounded-lg items-center border ${
                  mode === "habit"
                    ? "bg-purple-500 border-purple-500"
                    : "bg-white border-gray-300"
                }`}
              >
                <Text
                  className={`font-semibold ${
                    mode === "habit" ? "text-white" : "text-gray-700"
                  }`}
                >
                  Habit
                </Text>
                <Text
                  className={`text-xs mt-1 ${
                    mode === "habit" ? "text-purple-100" : "text-gray-500"
                  }`}
                >
                  Recurring daily goal
                </Text>
              </Pressable>
            </View>
          </View>

          {mode === "task" && (
            <DatePickerField
              label="Due By"
              value={dueBy}
              onChange={setDueBy}
              hasError={!!errors.due_by}
              disabled={isLoading}
              placeholder="Select due date"
            />
          )}

          {mode === "habit" && (
            <View>
              <Text className="text-sm font-medium text-gray-700 mb-1">
                Frequency *
              </Text>
              <View className="flex-row gap-2 mb-2">
                <TextInput
                  className={`flex-1 border rounded-lg px-4 py-3 text-base ${errors.min_daily_frequency ? "border-red-500" : "border-gray-300"}`}
                  placeholder="e.g., 1, 2, 3"
                  value={minDailyFrequency}
                  onChangeText={setMinDailyFrequency}
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
                        ? "bg-purple-500 border-purple-500"
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
                {frequencyPeriod === "day" && "Times per day (e.g., 1 = once daily, 2 = twice daily)"}
                {frequencyPeriod === "week" && "Times per week (e.g., 3 = three times a week)"}
                {frequencyPeriod === "month" && "Times per month (e.g., 2 = twice a month)"}
              </Text>
            </View>
          )}

          <DatePickerField
            label="Hidden Until"
            value={hiddenUntil}
            onChange={setHiddenUntil}
            hasError={!!errors.hidden_until}
            disabled={isLoading}
            placeholder="Select date to hide until"
          />

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
              className={`flex-1 py-3 px-6 rounded-lg items-center ${
                mode === "habit" ? "bg-purple-500" : "bg-blue-500"
              }`}
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
                  Delete {mode === "habit" ? "Habit" : "Task"}
                </Text>
              )}
            </Pressable>
          )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
