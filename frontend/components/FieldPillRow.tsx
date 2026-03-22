import { ScrollView, Pressable, Text } from "react-native";

export interface FieldPill {
  key: string;
  label: string;
  isSet: boolean;
  onPress: () => void;
}

interface FieldPillRowProps {
  pills: FieldPill[];
}

export function FieldPillRow({ pills }: FieldPillRowProps) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: 8 }}
    >
      {pills.map((pill) => (
        <Pressable
          key={pill.key}
          onPress={pill.onPress}
          className={`px-4 py-1.5 rounded-full border ${
            pill.isSet ? "bg-surface border-border" : "bg-transparent border-border/50"
          }`}
        >
          <Text
            className={`text-sm font-medium ${pill.isSet ? "text-foreground" : "text-muted"}`}
          >
            {pill.label}
          </Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}
