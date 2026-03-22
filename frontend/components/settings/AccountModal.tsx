import { useState } from "react";
import { View, Text, Pressable } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "../BottomSheet";
import { UpdateEmailModal } from "./UpdateEmailModal";
import { ChangePasswordModal } from "./ChangePasswordModal";

interface AccountModalProps {
  visible: boolean;
  onClose: () => void;
  currentEmail: string;
  onEmailChanged: (newEmail: string) => void;
}

export function AccountModal({
  visible,
  onClose,
  currentEmail,
  onEmailChanged,
}: AccountModalProps) {
  const [showUpdateEmail, setShowUpdateEmail] = useState(false);
  const [showChangePassword, setShowChangePassword] = useState(false);

  const handleEmailSuccess = (newEmail: string) => {
    setShowUpdateEmail(false);
    onEmailChanged(newEmail);
    onClose();
  };

  const handlePasswordSuccess = () => {
    setShowChangePassword(false);
    onClose();
  };

  return (
    <>
      <BottomSheet
        visible={visible && !showUpdateEmail && !showChangePassword}
        onClose={onClose}
      >
        {/* Header */}
        <View className="p-4 border-b border-border">
          <Text className="text-lg font-semibold text-foreground text-center">
            Account
          </Text>
        </View>

        {/* Email Row */}
        <Pressable
          onPress={() => setShowUpdateEmail(true)}
          className="flex-row items-center px-4 py-4 border-b border-border"
        >
          <Text className="text-muted text-base">Email</Text>
          <View className="flex-1" />
          <Text className="text-foreground text-base mr-2" numberOfLines={1}>
            {currentEmail}
          </Text>
          <Ionicons name="chevron-forward" size={20} color="var(--color-muted)" />
        </Pressable>

        {/* Password Row */}
        <View className="px-4 py-4 pb-8">
          <Text className="text-muted text-base mb-3">Password</Text>
          <Pressable
            onPress={() => setShowChangePassword(true)}
            className="bg-surface rounded-xl py-4 items-center"
          >
            <Text className="text-foreground text-base">Change Password</Text>
          </Pressable>
        </View>
      </BottomSheet>

      <UpdateEmailModal
        visible={showUpdateEmail}
        onClose={() => setShowUpdateEmail(false)}
        currentEmail={currentEmail}
        onSuccess={handleEmailSuccess}
      />

      <ChangePasswordModal
        visible={showChangePassword}
        onClose={() => setShowChangePassword(false)}
        onSuccess={handlePasswordSuccess}
      />
    </>
  );
}
