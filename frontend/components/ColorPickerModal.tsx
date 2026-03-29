import { useState } from "react";
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet } from "react-native";
import { BottomSheet } from "./BottomSheet";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

// Predefined color palette
const PRESET_COLORS = [
  // Reds
  "#ef4444", "#dc2626", "#b91c1c",
  // Oranges
  "#f97316", "#ea580c", "#c2410c",
  // Yellows
  "#eab308", "#ca8a04", "#a16207",
  // Greens
  "#22c55e", "#16a34a", "#15803d",
  // Teals
  "#14b8a6", "#0d9488", "#0f766e",
  // Blues
  "#3b82f6", "#2563eb", "#1d4ed8",
  // Indigos
  "#6366f1", "#4f46e5", "#4338ca",
  // Purples
  "#a855f7", "#9333ea", "#7e22ce",
  // Pinks
  "#ec4899", "#db2777", "#be185d",
  // Grays
  "#6b7280", "#4b5563", "#374151",
];

interface ColorPickerModalProps {
  visible: boolean;
  onClose: () => void;
  currentColor: string;
  onColorSelect: (color: string) => void;
}

export function ColorPickerModal({
  visible,
  onClose,
  currentColor,
  onColorSelect,
}: ColorPickerModalProps) {
  const colors = useColors();
  const [customColor, setCustomColor] = useState(currentColor);
  const [selectedColor, setSelectedColor] = useState(currentColor);

  const handleColorPress = (color: string) => {
    setSelectedColor(color);
    setCustomColor(color);
  };

  const handleCustomColorChange = (text: string) => {
    let color = text;
    if (!color.startsWith("#")) {
      color = "#" + color;
    }
    setCustomColor(color);

    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      setSelectedColor(color);
    }
  };

  const handleApply = () => {
    onColorSelect(selectedColor);
    onClose();
  };

  const isValidColor = /^#[0-9A-Fa-f]{6}$/.test(selectedColor);

  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <ScrollView style={styles.scrollView}>
        {/* Color Preview */}
        <View style={styles.previewContainer}>
          <View
            style={[
              styles.previewCircle,
              {
                backgroundColor: isValidColor ? selectedColor : "#ccc",
                borderColor: colors.border,
              }
            ]}
          />
          <Text style={[styles.previewText, { color: colors.muted }]}>
            {isValidColor ? selectedColor : "Invalid color"}
          </Text>
        </View>

        {/* Custom Color Input */}
        <View style={styles.inputContainer}>
          <TextInput
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                color: colors.foreground,
                borderColor: isValidColor ? colors.border : colors.accent,
              }
            ]}
            placeholder="#000000"
            placeholderTextColor={colors.muted}
            value={customColor}
            onChangeText={handleCustomColorChange}
            autoCapitalize="characters"
            maxLength={7}
          />
        </View>

        {/* Preset Colors */}
        <View style={styles.colorGrid}>
          {PRESET_COLORS.map((color) => (
            <Pressable
              key={color}
              onPress={() => handleColorPress(color)}
              style={[
                styles.colorSwatch,
                {
                  backgroundColor: color,
                  borderWidth: selectedColor === color ? 4 : 2,
                  borderColor: selectedColor === color ? colors.foreground : colors.border,
                }
              ]}
            />
          ))}
        </View>
      </ScrollView>

      {/* Actions */}
      <View style={[styles.actionsContainer, { borderTopColor: colors.border }]}>
        <Pressable
          onPress={onClose}
          style={[styles.button, { borderColor: colors.border }]}
        >
          <Text style={[styles.buttonText, { color: colors.foreground }]}>Cancel</Text>
        </Pressable>
        <Pressable
          onPress={handleApply}
          disabled={!isValidColor}
          style={[
            styles.button,
            { backgroundColor: isValidColor ? colors.accent : colors.surface }
          ]}
        >
          <Text style={styles.buttonTextWhite}>Apply</Text>
        </Pressable>
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
    maxHeight: 384,
  },
  previewContainer: {
    alignItems: "center",
    marginBottom: spacing[4],
  },
  previewCircle: {
    width: 64,
    height: 64,
    borderRadius: borderRadius.full,
    borderWidth: 4,
  },
  previewText: {
    marginTop: spacing[2],
    fontFamily: "monospace",
    fontSize: fontSize.sm,
  },
  inputContainer: {
    marginBottom: spacing[4],
  },
  input: {
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    fontSize: fontSize.base,
    fontFamily: "monospace",
  },
  colorGrid: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: spacing[3],
    marginBottom: spacing[4],
  },
  colorSwatch: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.full,
  },
  actionsContainer: {
    flexDirection: "row",
    gap: spacing[3],
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    borderTopWidth: 1,
  },
  button: {
    flex: 1,
    paddingVertical: spacing[3],
    borderRadius: borderRadius.lg,
    alignItems: "center",
    borderWidth: 1,
  },
  buttonText: {
    fontWeight: fontWeight.semibold,
  },
  buttonTextWhite: {
    color: "white",
    fontWeight: fontWeight.semibold,
  },
});
