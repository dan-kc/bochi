import type { ZodError, ZodType } from "zod";
import type { FrequencyPeriod } from "./frequency";
import { PERIOD_DIVISORS } from "./frequency";

export function parseZodErrors(error: ZodError): Record<string, string[]> {
  const fieldErrors: Record<string, string[]> = {};
  for (const issue of error.issues) {
    const path = issue.path.join(".") || "general";
    if (!fieldErrors[path]) {
      fieldErrors[path] = [];
    }
    fieldErrors[path].push(issue.message);
  }
  return fieldErrors;
}

export function buildFrequencyInput(frequencyStr: string, period: FrequencyPeriod): number | null {
  const raw = frequencyStr.trim() ? parseFloat(frequencyStr) : null;
  return raw !== null ? raw / PERIOD_DIVISORS[period] : null;
}

export async function autoSaveOnClose<T>({
  currentValues,
  originalValues,
  schema,
  onSave,
  onCancel,
}: {
  currentValues: Record<string, unknown>;
  originalValues: Record<string, unknown>;
  schema: ZodType<T>;
  onSave: (input: T) => Promise<void>;
  onCancel: () => void;
}) {
  const keys = Object.keys(currentValues);
  const hasChanges = keys.some((k) => currentValues[k] !== originalValues[k]);

  if (!hasChanges) {
    onCancel();
    return;
  }

  const result = schema.safeParse(currentValues);
  if (!result.success) {
    onCancel();
    return;
  }

  try {
    await onSave(result.data);
  } catch {
    onCancel();
  }
}
