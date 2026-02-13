import { View, Text } from "react-native";
import { usePriceUpdateOptional } from "@/lib/PriceUpdateContext";

interface PriceDisplayProps {
  habitId: string;
}

function formatTrend(
  current: number,
  previous: number
): { text: string; isPositive: boolean; isNeutral: boolean } {
  if (previous === 0 || current === previous) {
    return { text: "0%", isPositive: false, isNeutral: true };
  }

  const change = ((current - previous) / previous) * 100;
  const sign = change > 0 ? "+" : "";
  const formatted =
    Math.abs(change) >= 10
      ? Math.round(change).toString()
      : change.toFixed(1).replace(/\.0$/, "");

  return {
    text: `${sign}${formatted}%`,
    isPositive: change > 0,
    isNeutral: false,
  };
}

export function PriceDisplay({ habitId }: PriceDisplayProps) {
  const priceContext = usePriceUpdateOptional();

  if (!priceContext) return null;

  const priceData = priceContext.prices[habitId];
  if (!priceData) return null;

  const { current, previous } = priceData;
  const trend = formatTrend(current, previous);

  return (
    <View className="items-end">
      <Text
        className={`text-sm font-semibold ${
          trend.isNeutral
            ? "text-gray-500"
            : trend.isPositive
              ? "text-green-600"
              : "text-red-600"
        }`}
      >
        {trend.text}
      </Text>
      <Text className="text-base font-bold text-amber-700">{current} T</Text>
    </View>
  );
}
