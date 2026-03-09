import { useState } from "react";
import { View, Text, Pressable, Modal, TextInput } from "react-native";

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
        className="flex-1 bg-black/30 justify-end"
        onPress={onClose}
      >
        <Pressable
          className="bg-zinc-800 rounded-t-2xl pb-8"
          onPress={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <View className="p-4 border-b border-zinc-700">
            <Text className="text-lg font-semibold text-white text-center">
              General Difficulty
            </Text>
          </View>

          <View className="px-4 py-4">
            <Text className="text-gray-400 text-sm mb-3">
              Controls the overall scale of rewards and costs. Higher values mean
              larger rewards and costs. Default is 5.
            </Text>

            <TextInput
              className="bg-zinc-700 text-white text-base rounded-xl px-4 py-3 mb-2"
              value={inputValue}
              onChangeText={(text) => {
                setInputValue(text);
                setError(null);
              }}
              keyboardType="decimal-pad"
              placeholder="e.g. 5.0"
              placeholderTextColor="#6b7280"
              autoFocus
            />

            {error && (
              <Text className="text-red-400 text-sm mb-2">{error}</Text>
            )}

            <View className="flex-row gap-3 mt-2">
              <Pressable
                onPress={onClose}
                className="flex-1 bg-zinc-700 rounded-xl py-4 items-center"
              >
                <Text className="text-white text-base">Cancel</Text>
              </Pressable>
              <Pressable
                onPress={handleSave}
                className="flex-1 bg-blue-600 rounded-xl py-4 items-center"
              >
                <Text className="text-white text-base font-semibold">Save</Text>
              </Pressable>
            </View>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
