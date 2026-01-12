import { View, Text, Pressable } from "react-native";
import type { TabType } from "@/lib/sortOptions";

interface TaskTabsProps {
  activeTab: TabType;
  onTabChange: (tab: TabType) => void;
}

const TABS: { key: TabType; label: string }[] = [
  { key: "both", label: "Both" },
  { key: "habit", label: "Habit" },
  { key: "todo", label: "Todo" },
];

export function TaskTabs({ activeTab, onTabChange }: TaskTabsProps) {
  return (
    <View className="flex-row gap-2">
      {TABS.map((tab) => (
        <Pressable
          key={tab.key}
          onPress={() => onTabChange(tab.key)}
          className={`py-2 px-3 rounded-lg items-center border ${
            activeTab === tab.key
              ? "bg-blue-500 border-blue-500"
              : "bg-white border-gray-300"
          }`}
        >
          <Text
            className={`font-medium text-sm ${
              activeTab === tab.key ? "text-white" : "text-gray-700"
            }`}
          >
            {tab.label}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}
