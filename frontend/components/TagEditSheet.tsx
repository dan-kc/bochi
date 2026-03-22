import { useState } from "react";
import { View, Text, TextInput, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "./BottomSheet";
import { ColorPickerModal } from "./ColorPickerModal";

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
        <View className="px-4 py-3 flex-row items-center justify-between border-b border-border">
          <Text className="text-base font-semibold text-foreground">Edit Tag</Text>
          <Pressable onPress={handleClose} className="p-1">
            <Ionicons name="checkmark" size={24} color="var(--color-accent)" />
          </Pressable>
        </View>

        <View className="px-4 py-4 gap-4">
          {/* Name input */}
          <View>
            <Text className="text-sm font-medium text-muted mb-1">Name</Text>
            <TextInput
              className="border border-border rounded-lg px-4 py-3 text-base text-foreground bg-surface"
              value={name}
              onChangeText={setName}
              placeholder="Tag name"
              placeholderTextColor="var(--color-muted)"
              autoFocus
              maxLength={50}
            />
          </View>

          {/* Color row */}
          <Pressable
            onPress={() => setShowColorPicker(true)}
            className="flex-row items-center justify-between"
          >
            <Text className="text-sm font-medium text-muted">Color</Text>
            <View className="flex-row items-center gap-2">
              <View
                className="w-8 h-8 rounded-full border-2 border-border"
                style={{ backgroundColor: color }}
              />
              <Ionicons name="chevron-forward" size={20} color="var(--color-muted)" />
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
