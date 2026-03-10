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
        <Text className="text-muted text-sm">sort by </Text>
        <Text className="text-accent text-sm font-medium underline">
          {selectedLabel}
        </Text>
        <Ionicons
          name="chevron-down"
          size={14}
          color="#f54900"
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
            className="bg-background rounded-t-2xl pb-8"
            onPress={(e) => e.stopPropagation()}
          >
            <View className="p-4 border-b border-border">
              <Text className="text-lg font-semibold text-foreground text-center">
                Sort By
              </Text>
            </View>
            <View className="p-2">
              {options.map((option) => (
                <Pressable
                  key={option.key}
                  onPress={() => handleSelect(option.key)}
                  className={`p-4 rounded-lg ${
                    option.key === selectedKey ? "bg-surface" : ""
                  }`}
                >
                  <View className="flex-row items-center justify-between">
                    <Text
                      className={`text-base ${
                        option.key === selectedKey
                          ? "text-accent font-medium"
                          : "text-foreground"
                      }`}
                    >
                      {option.label}
                    </Text>
                    {option.key === selectedKey && (
                      <Ionicons name="checkmark" size={20} color="#f54900" />
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
