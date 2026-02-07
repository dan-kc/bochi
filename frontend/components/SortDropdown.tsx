import { useState } from "react";
import { View, Text, Pressable, Modal } from "react-native";
import { Ionicons } from "@expo/vector-icons";

interface SortOption<K extends string> {
  key: K;
  label: string;
}

interface SortDropdownProps<K extends string> {
  options: SortOption<K>[];
  selectedKey: K;
  onSelect: (key: K) => void;
}

export function SortDropdown<K extends string>({
  options,
  selectedKey,
  onSelect,
}: SortDropdownProps<K>) {
  const [isOpen, setIsOpen] = useState(false);

  const selectedOption = options.find((opt) => opt.key === selectedKey);
  const selectedLabel = selectedOption?.label ?? "Sort";

  const handleSelect = (key: K) => {
    onSelect(key);
    setIsOpen(false);
  };

  return (
    <>
      <Pressable
        onPress={() => setIsOpen(true)}
        className="flex-row items-center"
      >
        <Text className="text-gray-500 text-sm">sort by </Text>
        <Text className="text-blue-600 text-sm font-medium underline">
          {selectedLabel}
        </Text>
        <Ionicons
          name="chevron-down"
          size={14}
          color="#2563eb"
          style={{ marginLeft: 2 }}
        />
      </Pressable>

      <Modal
        visible={isOpen}
        transparent
        animationType="fade"
        onRequestClose={() => setIsOpen(false)}
      >
        <Pressable
          className="flex-1 bg-black/30 justify-end"
          onPress={() => setIsOpen(false)}
        >
          <Pressable
            className="bg-white rounded-t-2xl pb-8"
            onPress={(e) => e.stopPropagation()}
          >
            <View className="p-4 border-b border-gray-200">
              <Text className="text-lg font-semibold text-gray-900 text-center">
                Sort By
              </Text>
            </View>
            <View className="p-2">
              {options.map((option) => (
                <Pressable
                  key={option.key}
                  onPress={() => handleSelect(option.key)}
                  className={`p-4 rounded-lg ${
                    option.key === selectedKey ? "bg-blue-50" : ""
                  }`}
                >
                  <View className="flex-row items-center justify-between">
                    <Text
                      className={`text-base ${
                        option.key === selectedKey
                          ? "text-blue-600 font-medium"
                          : "text-gray-700"
                      }`}
                    >
                      {option.label}
                    </Text>
                    {option.key === selectedKey && (
                      <Ionicons name="checkmark" size={20} color="#2563eb" />
                    )}
                  </View>
                </Pressable>
              ))}
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </>
  );
}
