import { Text, StyleSheet } from "react-native";
import { usePriceUpdateOptional } from "@/lib/PriceUpdateContext";
import { useColors, fontSize, fontWeight } from "@/lib/theme";

interface PriceDisplayProps {
  habitId: string;
}

export function PriceDisplay({ habitId }: PriceDisplayProps) {
  const colors = useColors();
  const priceContext = usePriceUpdateOptional();

  if (!priceContext) return null;

  const priceData = priceContext.prices[habitId];
  if (!priceData) return null;

  return (
    <Text style={[styles.text, { color: colors.accent }]}>
      {priceData.current} tofu
    </Text>
  );
}

const styles = StyleSheet.create({
  text: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.bold,
  },
});
