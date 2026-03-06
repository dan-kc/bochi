import { View, Text, Pressable } from "react-native";

interface FilterOption<K extends string> {
  key: K;
  label: string;
}

interface FilterChipsProps<K extends string> {
  options: FilterOption<K>[];
  selectedKey: K;
  onSelect: (key: K) => void;
}

export function FilterChips<K extends string>({
  options,
  selectedKey,
  onSelect,
}: FilterChipsProps<K>) {
  return (
    <View className="flex-row gap-2">
      {options.map((option) => {
        const isActive = option.key === selectedKey;
        return (
          <Pressable
            key={option.key}
            onPress={() => onSelect(option.key)}
            className={`px-4 py-1.5 rounded-full ${
              isActive
                ? "bg-blue-500"
                : "bg-white border border-gray-300"
            }`}
          >
            <Text
              className={`text-sm font-medium ${
                isActive ? "text-white" : "text-gray-600"
              }`}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
