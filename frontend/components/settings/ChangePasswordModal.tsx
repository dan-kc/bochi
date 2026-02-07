import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  Modal,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { api, ApiError } from "@/lib/api";
import { getStoredTokens } from "@/lib/storage";

interface ChangePasswordModalProps {
  visible: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export function ChangePasswordModal({
  visible,
  onClose,
  onSuccess,
}: ChangePasswordModalProps) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const resetForm = () => {
    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setErrors([]);
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  const handleSubmit = async () => {
    setErrors([]);

    // Validate locally first
    const validationErrors: string[] = [];
    if (!currentPassword) {
      validationErrors.push("Current password is required");
    }
    if (newPassword.length < 8) {
      validationErrors.push("New password must be at least 8 characters");
    }
    if (newPassword.length > 64) {
      validationErrors.push("New password must be at most 64 characters");
    }
    if (newPassword !== confirmPassword) {
      validationErrors.push("Passwords do not match");
    }
    if (currentPassword === newPassword) {
      validationErrors.push("New password must be different from current password");
    }

    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    setIsLoading(true);
    try {
      // Get access token for native platforms
      const tokens = await getStoredTokens();
      await api.changePassword(currentPassword, newPassword, tokens?.accessToken);
      resetForm();
      onSuccess();
    } catch (error) {
      const apiError = error as ApiError;
      if (apiError.errors && Array.isArray(apiError.errors)) {
        setErrors(apiError.errors.map((e) => e.message ?? "An error occurred"));
      } else if (apiError.message) {
        setErrors([apiError.message]);
      } else {
        setErrors(["Failed to change password. Please try again."]);
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={handleClose}
    >
      <SafeAreaView className="flex-1 bg-zinc-900">
        <KeyboardAvoidingView
          behavior={Platform.OS === "ios" ? "padding" : "height"}
          className="flex-1"
        >
          {/* Header */}
          <View className="flex-row items-center justify-between px-4 py-3 border-b border-zinc-700">
            <Pressable onPress={handleClose} className="p-2">
              <Ionicons name="close" size={24} color="#9ca3af" />
            </Pressable>
            <Text className="text-lg font-semibold text-white">
              Change Password
            </Text>
            <Pressable
              onPress={handleSubmit}
              disabled={isLoading}
              className="p-2"
            >
              {isLoading ? (
                <ActivityIndicator size="small" color="#9ca3af" />
              ) : (
                <Ionicons name="checkmark" size={24} color="#9ca3af" />
              )}
            </Pressable>
          </View>

          <View className="flex-1 p-4">
            {errors.length > 0 && (
              <View className="bg-red-900/50 border border-red-700 rounded-lg p-4 mb-4">
                {errors.map((error, index) => (
                  <Text key={index} className="text-red-400 text-sm">
                    {error}
                  </Text>
                ))}
              </View>
            )}

            {/* Current Password */}
            <View className="bg-zinc-800 rounded-xl mb-6">
              <View className="flex-row items-center px-4 py-3">
                <Text className="text-gray-400 w-24">Current</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="current password"
                  placeholderTextColor="#6b7280"
                  value={currentPassword}
                  onChangeText={setCurrentPassword}
                  secureTextEntry
                  autoComplete="current-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            {/* New Password Section */}
            <View className="bg-zinc-800 rounded-xl mb-4">
              <View className="flex-row items-center px-4 py-3 border-b border-zinc-700">
                <Text className="text-gray-400 w-24">New</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="enter password"
                  placeholderTextColor="#6b7280"
                  value={newPassword}
                  onChangeText={setNewPassword}
                  secureTextEntry
                  autoComplete="new-password"
                  editable={!isLoading}
                />
              </View>
              <View className="flex-row items-center px-4 py-3">
                <Text className="text-gray-400 w-24">Confirm</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="re-enter password"
                  placeholderTextColor="#6b7280"
                  value={confirmPassword}
                  onChangeText={setConfirmPassword}
                  secureTextEntry
                  autoComplete="new-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text className="text-gray-400 text-sm px-1">
              Your password must be at least 8 characters long.{"\n"}
              Avoid common passwords or patterns.
            </Text>
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}
