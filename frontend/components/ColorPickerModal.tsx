import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  Modal,
  ScrollView,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";

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
  const [customColor, setCustomColor] = useState(currentColor);
  const [selectedColor, setSelectedColor] = useState(currentColor);

  const handleColorPress = (color: string) => {
    setSelectedColor(color);
    setCustomColor(color);
  };

  const handleCustomColorChange = (text: string) => {
    // Ensure it starts with #
    let color = text;
    if (!color.startsWith("#")) {
      color = "#" + color;
    }
    setCustomColor(color);

    // Validate hex color
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
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View className="flex-1 bg-background">
        {/* Header */}
        <View className="flex-row items-center justify-between px-4 py-3 border-b border-border">
          <Text className="text-lg font-semibold text-foreground">Choose Color</Text>
          <Pressable onPress={onClose} className="p-2">
            <Ionicons name="close" size={24} color="var(--color-muted)" />
          </Pressable>
        </View>

        <ScrollView className="flex-1 px-4 py-4">
          {/* Color Preview */}
          <View className="items-center mb-6">
            <View
              className="w-20 h-20 rounded-full border-4 border-border"
              style={{ backgroundColor: isValidColor ? selectedColor : "#ccc" }}
            />
            <Text className="mt-2 font-mono text-muted">
              {isValidColor ? selectedColor : "Invalid color"}
            </Text>
          </View>

          {/* Custom Color Input */}
          <View className="mb-6">
            <Text className="text-sm font-medium text-muted mb-2">
              Custom Color (Hex)
            </Text>
            <TextInput
              className={`border rounded-lg px-4 py-3 text-base font-mono text-foreground bg-surface ${
                isValidColor ? "border-border" : "border-accent"
              }`}
              placeholder="#000000"
              placeholderTextColor="var(--color-muted)"
              value={customColor}
              onChangeText={handleCustomColorChange}
              autoCapitalize="characters"
              maxLength={7}
            />
          </View>

          {/* Preset Colors */}
          <View className="mb-6">
            <Text className="text-sm font-medium text-muted mb-3">
              Preset Colors
            </Text>
            <View className="flex-row flex-wrap gap-3">
              {PRESET_COLORS.map((color) => (
                <Pressable
                  key={color}
                  onPress={() => handleColorPress(color)}
                  className={`w-10 h-10 rounded-full ${
                    selectedColor === color
                      ? "border-4 border-foreground"
                      : "border-2 border-border"
                  }`}
                  style={{ backgroundColor: color }}
                />
              ))}
            </View>
          </View>
        </ScrollView>

        {/* Actions */}
        <View className="flex-row gap-3 px-4 py-3 border-t border-border">
          <Pressable
            onPress={onClose}
            className="flex-1 border border-border py-3 rounded-lg items-center"
          >
            <Text className="text-foreground font-semibold">Cancel</Text>
          </Pressable>
          <Pressable
            onPress={handleApply}
            disabled={!isValidColor}
            className={`flex-1 py-3 rounded-lg items-center ${
              isValidColor ? "bg-accent" : "bg-surface"
            }`}
          >
            <Text className="text-white font-semibold">Apply</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}
