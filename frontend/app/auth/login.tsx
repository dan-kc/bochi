import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Modal,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Link, router } from "expo-router";
import { useAuth } from "@/lib/AuthContext";
import { useSync } from "@/lib/sync";
import { validateAuthInput, getErrorMessage } from "@/lib/validation";
import { habitStore } from "@/lib/store/habitStore";
import { markHabitsDirty, clearAllDirtyFlags, clearLastSyncTime } from "@/lib/sync/syncStorage";
import type { ApiError } from "@/lib/api";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

export default function Login() {
  const colors = useColors();
  const { login, user, isAnonymous } = useAuth();
  const { waitForSync } = useSync();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [showMergeModal, setShowMergeModal] = useState(false);
  const [pendingLogin, setPendingLogin] = useState<{
    email: string;
    password: string;
  } | null>(null);

  const localHabitCount = user ? habitStore.getHabitCount(user.id) : 0;

  const performLogin = async (
    loginEmail: string,
    loginPassword: string,
    mergeHabits: boolean,
  ) => {
    setIsLoading(true);
    try {
      if (mergeHabits && user) {
        const habitIds = await habitStore.updateAllHabitsUserId("");

        for (const habitId of habitIds) {
          await habitStore.updateHabit(habitId, { difficulty_rank: null });
        }

        await markHabitsDirty(habitIds);
        await clearLastSyncTime();

        await login(loginEmail, loginPassword);

        await waitForSync();
      } else {
        await habitStore.clearAllHabits();
        await clearAllDirtyFlags();
        await clearLastSyncTime();

        await login(loginEmail, loginPassword);
      }

      router.replace("/settings");
    } catch (error) {
      const apiError = error as ApiError;
      if (apiError.status && apiError.status >= 400 && apiError.status < 500) {
        console.log("[Auth] Login error:", apiError.status, apiError.errors);
      }
      if (apiError.errors && Array.isArray(apiError.errors)) {
        setErrors(apiError.errors.map((e: any) => e.message ?? "An error occurred"));
      } else if (apiError.message) {
        setErrors([apiError.message]);
      } else {
        setErrors(["Invalid email or password"]);
      }
    } finally {
      setIsLoading(false);
      setShowMergeModal(false);
      setPendingLogin(null);
    }
  };

  const handleLogin = async () => {
    setErrors([]);

    const validationErrors = validateAuthInput(email, password);
    if (validationErrors.length > 0) {
      setErrors(validationErrors.map(getErrorMessage));
      return;
    }

    if (isAnonymous && localHabitCount > 0) {
      setPendingLogin({ email, password });
      setShowMergeModal(true);
      return;
    }

    await performLogin(email, password, false);
  };

  const handleMergeChoice = async (merge: boolean) => {
    if (!pendingLogin) return;
    await performLogin(pendingLogin.email, pendingLogin.password, merge);
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        style={styles.flex1}
      >
        <View style={styles.content}>
          <Text style={[styles.title, { color: colors.foreground }]}>
            Welcome back
          </Text>
          <Text style={[styles.subtitle, { color: colors.muted }]}>
            Log in to your Tofustash account
          </Text>

          {errors.length > 0 && (
            <View style={[styles.errorContainer, { backgroundColor: colors.surface, borderColor: colors.accent }]}>
              {errors.map((error, index) => (
                <Text key={index} style={[styles.errorText, { color: colors.accent }]}>
                  {error}
                </Text>
              ))}
            </View>
          )}

          <View style={styles.formContainer}>
            <View>
              <Text style={[styles.label, { color: colors.muted }]}>
                Email
              </Text>
              <TextInput
                style={[styles.input, { borderColor: colors.border, backgroundColor: colors.surface, color: colors.foreground }]}
                placeholder="you@example.com"
                placeholderTextColor={colors.muted}
                value={email}
                onChangeText={setEmail}
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                editable={!isLoading}
              />
            </View>

            <View>
              <Text style={[styles.label, { color: colors.muted }]}>
                Password
              </Text>
              <TextInput
                style={[styles.input, { borderColor: colors.border, backgroundColor: colors.surface, color: colors.foreground }]}
                placeholder="Enter your password"
                placeholderTextColor={colors.muted}
                value={password}
                onChangeText={setPassword}
                secureTextEntry
                autoComplete="password"
                editable={!isLoading}
              />
            </View>

            <Pressable
              onPress={handleLogin}
              disabled={isLoading}
              style={[styles.button, { backgroundColor: colors.accent }]}
            >
              {isLoading ? (
                <ActivityIndicator color={colors.white} />
              ) : (
                <Text style={[styles.buttonText, { color: colors.white }]}>
                  Log In
                </Text>
              )}
            </Pressable>
          </View>

          <View style={styles.linkRow}>
            <Text style={[styles.linkText, { color: colors.muted }]}>Don&apos;t have an account?</Text>
            <Link href="/auth/register" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    style={[styles.linkButton, { color: hovered ? colors.accent : colors.accent }]}
                  >
                    Register
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>

          <View style={styles.linkRowCentered}>
            <Link href="/settings" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    style={[styles.linkText, { color: hovered ? colors.foreground : colors.muted }]}
                  >
                    Back to Settings
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>
        </View>
      </KeyboardAvoidingView>

      {/* Merge Habits Modal */}
      <Modal
        visible={showMergeModal}
        transparent
        animationType="fade"
        onRequestClose={() => {
          setShowMergeModal(false);
          setPendingLogin(null);
        }}
      >
        <View style={[styles.modalOverlay, { backgroundColor: "rgba(0, 0, 0, 0.5)" }]}>
          <View style={[styles.modalContent, { backgroundColor: colors.background }]}>
            <Text style={[styles.modalTitle, { color: colors.foreground }]}>
              Merge Your Habits?
            </Text>
            <Text style={[styles.modalText, { color: colors.muted }]}>
              You have {localHabitCount} habit{localHabitCount !== 1 ? "s" : ""} on
              this device. Would you like to add them to your account?
            </Text>

            <View style={styles.modalButtons}>
              <Pressable
                onPress={() => handleMergeChoice(true)}
                disabled={isLoading}
                style={[styles.modalButton, { backgroundColor: colors.accent }]}
              >
                {isLoading ? (
                  <ActivityIndicator color={colors.white} />
                ) : (
                  <Text style={[styles.modalButtonText, { color: colors.white }]}>
                    Yes, merge my habits
                  </Text>
                )}
              </Pressable>

              <Pressable
                onPress={() => handleMergeChoice(false)}
                disabled={isLoading}
                style={[styles.modalButtonOutline, { borderColor: colors.border }]}
              >
                <Text style={[styles.modalButtonText, { color: colors.foreground }]}>
                  No, discard them
                </Text>
              </Pressable>

              <Pressable
                onPress={() => {
                  setShowMergeModal(false);
                  setPendingLogin(null);
                }}
                disabled={isLoading}
                style={styles.modalButtonCancel}
              >
                <Text style={[styles.linkText, { color: colors.muted }]}>Cancel</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  flex1: {
    flex: 1,
  },
  content: {
    flex: 1,
    padding: spacing[6],
    justifyContent: "center",
    maxWidth: 448,
    marginHorizontal: "auto",
    width: "100%",
  },
  title: {
    fontSize: fontSize["3xl"],
    fontWeight: fontWeight.bold,
    marginBottom: spacing[2],
  },
  subtitle: {
    marginBottom: spacing[8],
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
  formContainer: {
    gap: spacing[4],
  },
  label: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    marginBottom: spacing[1],
  },
  input: {
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    fontSize: fontSize.base,
  },
  button: {
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
    marginTop: spacing[2],
  },
  buttonText: {
    fontWeight: fontWeight.semibold,
    fontSize: fontSize.base,
  },
  linkRow: {
    flexDirection: "row",
    justifyContent: "center",
    marginTop: spacing[6],
    gap: spacing[1],
  },
  linkRowCentered: {
    flexDirection: "row",
    justifyContent: "center",
    marginTop: spacing[4],
  },
  linkText: {
    fontSize: fontSize.base,
  },
  linkButton: {
    fontWeight: fontWeight.semibold,
  },
  modalOverlay: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: spacing[6],
  },
  modalContent: {
    borderRadius: borderRadius["2xl"],
    padding: spacing[6],
    maxWidth: 384,
    width: "100%",
  },
  modalTitle: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    marginBottom: spacing[2],
  },
  modalText: {
    marginBottom: spacing[4],
  },
  modalButtons: {
    gap: spacing[3],
  },
  modalButton: {
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  modalButtonOutline: {
    borderWidth: 1,
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  modalButtonText: {
    fontWeight: fontWeight.semibold,
  },
  modalButtonCancel: {
    paddingVertical: spacing[2],
    alignItems: "center",
  },
});
