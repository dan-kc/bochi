import type { ReactNode } from "react";
import { Modal, Pressable, KeyboardAvoidingView, Platform } from "react-native";

interface BottomSheetProps {
  visible: boolean;
  onClose: () => void;
  children: ReactNode;
}

export function BottomSheet({ visible, onClose, children }: BottomSheetProps) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable className="flex-1 bg-black/30 justify-end" onPress={onClose}>
        <Pressable
          className="bg-background rounded-t-2xl"
          onPress={(e) => e.stopPropagation()}
        >
          <KeyboardAvoidingView
            behavior={Platform.OS === "ios" ? "padding" : undefined}
          >
            {children}
          </KeyboardAvoidingView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
