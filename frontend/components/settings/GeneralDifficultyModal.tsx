import { useState } from "react";
import { View, Text, Pressable, Modal, TextInput, StyleSheet } from "react-native";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface GeneralDifficultyModalProps {
  visible: boolean;
  onClose: () => void;
  currentValue: number;
  onSave: (value: number) => void;
}

export function GeneralDifficultyModal({
  visible,
  onClose,
  currentValue,
  onSave,
}: GeneralDifficultyModalProps) {
  const colors = useColors();
  const [inputValue, setInputValue] = useState(currentValue.toString());
  const [error, setError] = useState<string | null>(null);

  const handleSave = () => {
    const parsed = parseFloat(inputValue);
    if (isNaN(parsed) || parsed <= 0 || parsed >= 1000) {
      setError("Must be a number greater than 0 and less than 1000");
      return;
    }
    setError(null);
    onSave(parsed);
    onClose();
  };

  const handleOpen = () => {
    setInputValue(currentValue.toString());
    setError(null);
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
      onShow={handleOpen}
    >
      <Pressable
        style={styles.overlay}
        onPress={onClose}
      >
        <Pressable
          style={[styles.modal, { backgroundColor: colors.background }]}
          onPress={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <View style={[styles.header, { borderBottomColor: colors.border }]}>
            <Text style={[styles.headerText, { color: colors.foreground }]}>
              General Difficulty
            </Text>
          </View>

          <View style={styles.content}>
            <Text style={[styles.description, { color: colors.muted }]}>
              Controls the overall scale of rewards and costs. Higher values mean
              larger rewards and costs. Default is 5.
            </Text>

            <TextInput
              style={[
                styles.input,
                {
                  backgroundColor: colors.surface,
                  color: colors.foreground,
                  borderColor: colors.border,
                }
              ]}
              value={inputValue}
              onChangeText={(text) => {
                setInputValue(text);
                setError(null);
              }}
              keyboardType="decimal-pad"
              placeholder="e.g. 5.0"
              placeholderTextColor={colors.muted}
              autoFocus
            />

            {error && (
              <Text style={[styles.errorText, { color: colors.accent }]}>{error}</Text>
            )}

            <View style={styles.buttonRow}>
              <Pressable
                onPress={onClose}
                style={[styles.button, { backgroundColor: colors.surface }]}
              >
                <Text style={[styles.buttonText, { color: colors.foreground }]}>Cancel</Text>
              </Pressable>
              <Pressable
                onPress={handleSave}
                style={[styles.button, { backgroundColor: colors.accent }]}
              >
                <Text style={styles.buttonTextWhite}>Save</Text>
              </Pressable>
            </View>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.3)",
    justifyContent: "flex-end",
  },
  modal: {
    borderTopLeftRadius: borderRadius["2xl"],
    borderTopRightRadius: borderRadius["2xl"],
    paddingBottom: spacing[8],
  },
  header: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  headerText: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
    textAlign: "center",
  },
  content: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
  },
  description: {
    fontSize: fontSize.sm,
    marginBottom: spacing[3],
  },
  input: {
    fontSize: fontSize.base,
    borderRadius: borderRadius.xl,
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    marginBottom: spacing[2],
    borderWidth: 1,
  },
  errorText: {
    fontSize: fontSize.sm,
    marginBottom: spacing[2],
  },
  buttonRow: {
    flexDirection: "row",
    gap: spacing[3],
    marginTop: spacing[2],
  },
  button: {
    flex: 1,
    borderRadius: borderRadius.xl,
    paddingVertical: spacing[4],
    alignItems: "center",
  },
  buttonText: {
    fontSize: fontSize.base,
  },
  buttonTextWhite: {
    color: "white",
    fontSize: fontSize.base,
    fontWeight: fontWeight.semibold,
  },
});
