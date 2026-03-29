import type { ReactNode } from "react";
import { View, Text, Pressable, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "./BottomSheet";
import { useColors, spacing, fontSize, fontWeight } from "@/lib/theme";

interface FieldEditSheetProps {
  visible: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
}

export function FieldEditSheet({ visible, onClose, title, children }: FieldEditSheetProps) {
  const colors = useColors();

  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <View style={[styles.header, { borderBottomColor: colors.border }]}>
        {title ? (
          <Text style={[styles.title, { color: colors.foreground }]}>{title}</Text>
        ) : (
          <View />
        )}
        <Pressable onPress={onClose} style={styles.closeButton}>
          <Ionicons name="close" size={24} color={colors.muted} />
        </Pressable>
      </View>
      <View style={styles.content}>{children}</View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    borderBottomWidth: 1,
  },
  title: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.semibold,
  },
  closeButton: {
    padding: spacing[1],
  },
  content: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
  },
});
