import { View, Text } from "react-native";
import { FadingText } from "./FadingText";

interface TradeItemProps {
  type: "Sold" | "Bought";
  name: string;
  amount: number;
  date: string;
}

export function TradeItem({ type, name, amount, date }: TradeItemProps) {
  const isSold = type === "Sold";
  const sign = isSold ? "+" : "-";
  const colorClass = isSold ? "text-accent-secondary" : "text-accent";

  return (
    <View className="border-b border-border py-4 px-2">
      <FadingText numberOfLines={1} className="text-base font-medium text-foreground">
        {`${type} ${name}`}
      </FadingText>
      <View className="flex-row justify-between items-center mt-1">
        <Text className="text-sm text-muted">{date}</Text>
        <Text className={`text-sm font-semibold ${colorClass}`}>
          {sign}{Math.abs(amount)}
        </Text>
      </View>
    </View>
  );
}
