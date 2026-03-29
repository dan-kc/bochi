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
  const colors = useColors();
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
              Update Email Address
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

            {/* New Email Section */}
            <View style={[styles.inputSection, { backgroundColor: colors.surface }]}>
              <View style={[styles.inputRow, styles.inputRowBorder, { borderBottomColor: colors.border }]}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>New</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="enter email"
                  placeholderTextColor={colors.muted}
                  value={newEmail}
                  onChangeText={setNewEmail}
                  autoCapitalize="none"
                  autoComplete="email"
                  keyboardType="email-address"
                  editable={!isLoading}
                />
              </View>
              <View style={styles.inputRow}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>Confirm</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="re-enter email"
                  placeholderTextColor={colors.muted}
                  value={confirmEmail}
                  onChangeText={setConfirmEmail}
                  autoCapitalize="none"
                  autoComplete="email"
                  keyboardType="email-address"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text style={[styles.helperText, styles.helperTextMargin, { color: colors.muted }]}>
              Current email: {currentEmail}{"\n"}
              Enter a new email address for your Tofustash account.
            </Text>

            {/* Password Section */}
            <View style={[styles.inputSection, { backgroundColor: colors.surface }]}>
              <View style={styles.inputRow}>
                <Text style={[styles.inputLabel, { color: colors.muted }]}>Password</Text>
                <TextInput
                  style={[styles.input, { color: colors.foreground }]}
                  placeholder="enter password"
                  placeholderTextColor={colors.muted}
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry
                  autoComplete="current-password"
                  editable={!isLoading}
                />
              </View>
            </View>

            <Text style={[styles.helperText, { color: colors.muted }]}>
              Use your Tofustash password
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
    marginBottom: spacing[4],
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
  helperTextMargin: {
    marginBottom: spacing[6],
  },
});
