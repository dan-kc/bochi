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
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { api, ApiError } from "@/lib/api";
import { getStoredTokens } from "@/lib/storage";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

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
  const colors = useColors();
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
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <KeyboardAvoidingView
          behavior={Platform.OS === "ios" ? "padding" : "height"}
          style={styles.flex1}
        >
          {/* Header */}
          <View style={[styles.header, { borderBottomColor: colors.border }]}>
            <Pressable onPress={handleClose} style={styles.headerButton}>
              <Ionicons name="close" size={24} color={colors.muted} />
            </Pressable>
            <Text style={[styles.headerTitle, { color: colors.foreground }]}>
              Change Password
            </Text>
            <Pressable
              onPress={handleSubmit}
              disabled={isLoading}
              style={styles.headerButton}
            >
              {isLoading ? (
                <ActivityIndicator size="small" color={colors.muted} />
              ) : (
                <Ionicons name="checkmark" size={24} color={colors.muted} />
              )}
            </Pressable>
          </View>

          <View style={styles.content}>
            {errors.length > 0 && (
              <View style={[styles.errorContainer, { backgroundColor: colors.surface, borderColor: colors.accent }]}>
                {errors.map((error, index) => (
                  <Text key={index} style={[styles.errorText, { color: colors.accent }]}>
                    {error}
                  </Text>
                ))}
              </View>
            )}

            {/* Current Password */}
            <View style={[styles.inputSection, { backgroundColor: colors.surface }]}>
              <View style={styles.inputRow}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>Current</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="current password"
                  placeholderTextColor={colors.muted}
                  value={currentPassword}
                  onChangeText={setCurrentPassword}
                  secureTextEntry
                  autoComplete="current-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            {/* New Password Section */}
            <View style={[styles.inputSection, { backgroundColor: colors.surface }]}>
              <View style={[styles.inputRow, styles.inputRowBorder, { borderBottomColor: colors.border }]}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>New</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="enter password"
                  placeholderTextColor={colors.muted}
                  value={newPassword}
                  onChangeText={setNewPassword}
                  secureTextEntry
                  autoComplete="new-password"
                  editable={!isLoading}
                />
              </View>
              <View style={styles.inputRow}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>Confirm</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="re-enter password"
                  placeholderTextColor={colors.muted}
                  value={confirmPassword}
                  onChangeText={setConfirmPassword}
                  secureTextEntry
                  autoComplete="new-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text style={[styles.helperText, { color: colors.muted }]}>
              Your password must be at least 8 characters long.{"\n"}
              Avoid common passwords or patterns.
            </Text>
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  flex1: {
    flex: 1,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    borderBottomWidth: 1,
  },
  headerButton: {
    padding: spacing[2],
  },
  headerTitle: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
  },
  content: {
    flex: 1,
    padding: spacing[4],
  },
  errorContainer: {
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    padding: spacing[4],
    marginBottom: spacing[4],
  },
  errorText: {
    fontSize: fontSize.sm,
  },
  inputSection: {
    borderRadius: borderRadius.xl,
    marginBottom: spacing[6],
  },
  inputRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
  },
  inputRowBorder: {
    borderBottomWidth: 1,
  },
  inputLabel: {
    width: 96,
  },
  input: {
    flex: 1,
    fontSize: fontSize.base,
  },
  helperText: {
    fontSize: fontSize.sm,
    paddingHorizontal: spacing[1],
  },
});
