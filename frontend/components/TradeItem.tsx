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
  const colorClass = isSold ? "text-green-600" : "text-red-600";

  return (
    <View className="border rounded-lg p-4 mb-3 bg-white border-gray-200">
      <FadingText numberOfLines={1} className="text-base font-medium text-gray-900">
        {`${type} ${name}`}
      </FadingText>
      <View className="flex-row justify-between items-center mt-1">
        <Text className="text-sm text-gray-500">{date}</Text>
        <Text className={`text-sm font-semibold ${colorClass}`}>
          {sign}{Math.abs(amount)}
        </Text>
      </View>
    </View>
  );
}
