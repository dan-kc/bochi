import { useState } from "react";
import { View, Text, Pressable, Modal } from "react-native";
import { Ionicons } from "@expo/vector-icons";
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
      <Modal
        visible={visible && !showUpdateEmail && !showChangePassword}
        transparent
        animationType="fade"
        onRequestClose={onClose}
      >
        <Pressable
          className="flex-1 bg-black/30 justify-end"
          onPress={onClose}
        >
          <Pressable
            className="bg-zinc-800 rounded-t-2xl pb-8"
            onPress={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <View className="p-4 border-b border-zinc-700">
              <Text className="text-lg font-semibold text-white text-center">
                Account
              </Text>
            </View>

            {/* Email Row */}
            <Pressable
              onPress={() => setShowUpdateEmail(true)}
              className="flex-row items-center px-4 py-4 border-b border-zinc-700"
            >
              <Text className="text-gray-400 text-base">Email</Text>
              <View className="flex-1" />
              <Text className="text-white text-base mr-2" numberOfLines={1}>
                {currentEmail}
              </Text>
              <Ionicons name="chevron-forward" size={20} color="#6b7280" />
            </Pressable>

            {/* Password Row */}
            <View className="px-4 py-4">
              <Text className="text-gray-400 text-base mb-3">Password</Text>
              <Pressable
                onPress={() => setShowChangePassword(true)}
                className="bg-zinc-700 rounded-xl py-4 items-center"
              >
                <Text className="text-white text-base">Change Password</Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>

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
