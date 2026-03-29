import { useState } from "react";
import { View, Text, TextInput, Pressable, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "./BottomSheet";
import { ColorPickerModal } from "./ColorPickerModal";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface TagEditSheetProps {
  visible: boolean;
  onClose: () => void;
  tagName: string;
  tagColor: string;
  onSave: (name: string, color: string) => void;
}

export function TagEditSheet({
  visible,
  onClose,
  tagName,
  tagColor,
  onSave,
}: TagEditSheetProps) {
  const [name, setName] = useState(tagName);
  const [color, setColor] = useState(tagColor);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const colors = useColors();

  const handleClose = () => {
    if (name.trim()) {
      onSave(name.trim(), color);
    }
    onClose();
  };

  const handleColorSelect = (newColor: string) => {
    setColor(newColor);
  };

  return (
    <>
      <BottomSheet visible={visible && !showColorPicker} onClose={handleClose}>
        {/* Header */}
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <Text style={[styles.headerText, { color: colors.foreground }]}>Edit Tag</Text>
          <Pressable onPress={handleClose} style={styles.checkButton}>
            <Ionicons name="checkmark" size={24} color={colors.accent} />
          </Pressable>
        </View>

        <View style={styles.content}>
          {/* Name input */}
          <View>
            <Text style={[styles.label, { color: colors.muted }]}>Name</Text>
            <TextInput
              style={[
                styles.input,
                {
                  borderColor: colors.border,
                  color: colors.foreground,
                  backgroundColor: colors.surface,
                },
              ]}
              value={name}
              onChangeText={setName}
              placeholder="Tag name"
              placeholderTextColor={colors.muted}
              autoFocus
              maxLength={50}
            />
          </View>

          {/* Color row */}
          <Pressable
            onPress={() => setShowColorPicker(true)}
            style={styles.colorRow}
          >
            <Text style={[styles.colorLabel, { color: colors.muted }]}>Color</Text>
            <View style={styles.colorRowRight}>
              <View
                style={[styles.colorSwatch, { backgroundColor: color, borderColor: colors.border }]}
              />
              <Ionicons name="chevron-forward" size={20} color={colors.muted} />
            </View>
          </Pressable>
        </View>
      </BottomSheet>

      <ColorPickerModal
        visible={showColorPicker}
        onClose={() => setShowColorPicker(false)}
        currentColor={color}
        onColorSelect={handleColorSelect}
      />
    </>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    borderBottomWidth: 1,
  },
  headerText: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.semibold,
  },
  checkButton: {
    padding: spacing[1],
  },
  content: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
    gap: spacing[4],
  },
  label: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    marginBottom: spacing[1],
  },
  input: {
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    fontSize: fontSize.base,
  },
  colorRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  colorLabel: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
  colorRowRight: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing[2],
  },
  colorSwatch: {
    width: 32,
    height: 32,
    borderRadius: borderRadius.full,
    borderWidth: 2,
  },
});
