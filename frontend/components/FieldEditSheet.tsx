import type { ReactNode } from "react";
import { View, Text, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "./BottomSheet";

interface FieldEditSheetProps {
  visible: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
}

export function FieldEditSheet({ visible, onClose, title, children }: FieldEditSheetProps) {
  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <View className="px-4 py-3 flex-row items-center justify-between border-b border-border">
        {title ? (
          <Text className="text-base font-semibold text-foreground">{title}</Text>
        ) : (
          <View />
        )}
        <Pressable onPress={onClose} className="p-1">
          <Ionicons name="close" size={24} color="var(--color-muted)" />
        </Pressable>
      </View>
      <View className="px-4 py-4">{children}</View>
    </BottomSheet>
  );
}
