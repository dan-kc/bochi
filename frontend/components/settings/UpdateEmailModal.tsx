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

interface UpdateEmailModalProps {
  visible: boolean;
  onClose: () => void;
  currentEmail: string;
  onSuccess: (newEmail: string) => void;
}

export function UpdateEmailModal({
  visible,
  onClose,
  currentEmail,
  onSuccess,
}: UpdateEmailModalProps) {
  const [newEmail, setNewEmail] = useState("");
  const [confirmEmail, setConfirmEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const resetForm = () => {
    setNewEmail("");
    setConfirmEmail("");
    setPassword("");
    setErrors([]);
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  const isValidEmail = (email: string) => {
    return /^[\w.-]+@[a-zA-Z\d.-]+\.[a-zA-Z]{2,}$/.test(email);
  };

  const handleSubmit = async () => {
    setErrors([]);

    // Validate locally first
    const validationErrors: string[] = [];
    if (!newEmail) {
      validationErrors.push("New email is required");
    } else if (!isValidEmail(newEmail)) {
      validationErrors.push("Please enter a valid email address");
    }
    if (newEmail !== confirmEmail) {
      validationErrors.push("Email addresses do not match");
    }
    if (newEmail.toLowerCase() === currentEmail.toLowerCase()) {
      validationErrors.push("New email must be different from current email");
    }
    if (!password) {
      validationErrors.push("Password is required");
    }

    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    setIsLoading(true);
    try {
      // Get access token for native platforms
      const tokens = await getStoredTokens();
      await api.changeEmail(newEmail, password, tokens?.accessToken);
      resetForm();
      onSuccess(newEmail);
    } catch (error) {
      const apiError = error as ApiError;
      if (apiError.errors && Array.isArray(apiError.errors)) {
        setErrors(apiError.errors.map((e) => e.message ?? "An error occurred"));
      } else if (apiError.message) {
        setErrors([apiError.message]);
      } else {
        setErrors(["Failed to change email. Please try again."]);
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
              Update Email Address
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

            {/* New Email Section */}
            <View className="bg-zinc-800 rounded-xl mb-4">
              <View className="flex-row items-center px-4 py-3 border-b border-zinc-700">
                <Text className="text-gray-400 w-24">New</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="enter email"
                  placeholderTextColor="#6b7280"
                  value={newEmail}
                  onChangeText={setNewEmail}
                  autoCapitalize="none"
                  autoComplete="email"
                  keyboardType="email-address"
                  editable={!isLoading}
                />
              </View>
              <View className="flex-row items-center px-4 py-3">
                <Text className="text-gray-400 w-24">Confirm</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="re-enter email"
                  placeholderTextColor="#6b7280"
                  value={confirmEmail}
                  onChangeText={setConfirmEmail}
                  autoCapitalize="none"
                  autoComplete="email"
                  keyboardType="email-address"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text className="text-gray-400 text-sm px-1 mb-6">
              Current email: {currentEmail}{"\n"}
              Enter a new email address for your Tofustash account.
            </Text>

            {/* Password Section */}
            <View className="bg-zinc-800 rounded-xl mb-4">
              <View className="flex-row items-center px-4 py-3">
                <Text className="text-gray-400 w-24">Password</Text>
                <TextInput
                  className="flex-1 text-white text-base"
                  placeholder="enter password"
                  placeholderTextColor="#6b7280"
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry
                  autoComplete="current-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text className="text-gray-400 text-sm px-1">
              Use your Tofustash password
            </Text>
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}
