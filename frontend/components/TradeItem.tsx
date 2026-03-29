import { View, Text, StyleSheet } from "react-native";
import { FadingText } from "./FadingText";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

interface TradeItemProps {
  type: "Sold" | "Bought";
  name: string;
  amount: number;
  date: string;
}

export function TradeItem({ type, name, amount, date }: TradeItemProps) {
  const colors = useColors();
  const isSold = type === "Sold";
  const sign = isSold ? "+" : "-";
  const amountColor = isSold ? colors.accentSecondary : colors.accent;

  return (
    <View style={[styles.container, { borderBottomColor: colors.border }]}>
      <FadingText
        numberOfLines={1}
        style={[styles.title, { color: colors.foreground }]}
      >
        {`${type} ${name}`}
      </FadingText>
      <View style={styles.row}>
        <Text style={[styles.date, { color: colors.muted }]}>{date}</Text>
        <Text style={[styles.amount, { color: amountColor }]}>
          {sign}{Math.abs(amount)}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderBottomWidth: 1,
    paddingVertical: spacing[4],
    paddingHorizontal: spacing[2],
  },
  title: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.medium,
  },
  row: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginTop: spacing[1],
  },
  date: {
    fontSize: fontSize.sm,
  },
  amount: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.semibold,
  },
});
