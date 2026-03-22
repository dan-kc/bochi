import { useState } from "react";
import { View, Text, TextInput, Pressable, ScrollView } from "react-native";
import { BottomSheet } from "./BottomSheet";

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
      <ScrollView className="px-4 py-4 max-h-96">
        {/* Color Preview */}
        <View className="items-center mb-4">
          <View
            className="w-16 h-16 rounded-full border-4 border-border"
            style={{ backgroundColor: isValidColor ? selectedColor : "#ccc" }}
          />
          <Text className="mt-2 font-mono text-muted text-sm">
            {isValidColor ? selectedColor : "Invalid color"}
          </Text>
        </View>

        {/* Custom Color Input */}
        <View className="mb-4">
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
        <View className="flex-row flex-wrap gap-3 mb-4">
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
    </BottomSheet>
  );
}
