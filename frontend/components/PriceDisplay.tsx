import { Text } from "react-native";
import { usePriceUpdateOptional } from "@/lib/PriceUpdateContext";

interface PriceDisplayProps {
  habitId: string;
}

export function PriceDisplay({ habitId }: PriceDisplayProps) {
  const priceContext = usePriceUpdateOptional();

  if (!priceContext) return null;

  const priceData = priceContext.prices[habitId];
  if (!priceData) return null;

  return (
    <Text className="text-base font-bold text-accent">
      {priceData.current} tofu
    </Text>
  );
}
