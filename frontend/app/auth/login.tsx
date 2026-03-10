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
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Link, router } from "expo-router";
import { useAuth } from "@/lib/AuthContext";
import { useSync } from "@/lib/sync";
import { validateAuthInput, getErrorMessage } from "@/lib/validation";
import { habitStore } from "@/lib/store/habitStore";
import { markHabitsDirty, clearAllDirtyFlags, clearLastSyncTime } from "@/lib/sync/syncStorage";
import type { ApiError } from "@/lib/api";

export default function Login() {
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
    <SafeAreaView className="flex-1 bg-background">
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        className="flex-1"
      >
        <View className="flex-1 p-6 justify-center max-w-md mx-auto w-full">
          <Text className="text-3xl font-bold text-foreground mb-2">
            Welcome back
          </Text>
          <Text className="text-muted mb-8">
            Log in to your Tofustash account
          </Text>

          {errors.length > 0 && (
            <View className="bg-surface border border-accent rounded-lg p-4 mb-4">
              {errors.map((error, index) => (
                <Text key={index} className="text-accent text-sm">
                  {error}
                </Text>
              ))}
            </View>
          )}

          <View className="gap-4">
            <View>
              <Text className="text-sm font-medium text-muted mb-1">
                Email
              </Text>
              <TextInput
                className="border border-border bg-surface rounded-lg px-4 py-3 text-base text-foreground"
                placeholder="you@example.com"
                placeholderTextColor="var(--color-muted)"
                value={email}
                onChangeText={setEmail}
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                editable={!isLoading}
              />
            </View>

            <View>
              <Text className="text-sm font-medium text-muted mb-1">
                Password
              </Text>
              <TextInput
                className="border border-border bg-surface rounded-lg px-4 py-3 text-base text-foreground"
                placeholder="Enter your password"
                placeholderTextColor="var(--color-muted)"
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
              className="bg-accent py-3 px-6 rounded-lg items-center mt-2"
            >
              {isLoading ? (
                <ActivityIndicator color="white" />
              ) : (
                <Text className="text-white font-semibold text-base">
                  Log In
                </Text>
              )}
            </Pressable>
          </View>

          <View className="flex-row justify-center mt-6 gap-1">
            <Text className="text-muted">Don&apos;t have an account?</Text>
            <Link href="/auth/register" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    className={`font-semibold ${hovered ? "text-accent" : "text-accent"}`}
                  >
                    Register
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>

          <View className="flex-row justify-center mt-4">
            <Link href="/settings" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    className={`${hovered ? "text-foreground" : "text-muted"}`}
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
        <View className="flex-1 bg-black/50 justify-center items-center p-6">
          <View className="bg-background rounded-2xl p-6 max-w-sm w-full">
            <Text className="text-xl font-bold text-foreground mb-2">
              Merge Your Habits?
            </Text>
            <Text className="text-muted mb-4">
              You have {localHabitCount} habit{localHabitCount !== 1 ? "s" : ""} on
              this device. Would you like to add them to your account?
            </Text>

            <View className="gap-3">
              <Pressable
                onPress={() => handleMergeChoice(true)}
                disabled={isLoading}
                className="bg-accent py-3 px-6 rounded-lg items-center"
              >
                {isLoading ? (
                  <ActivityIndicator color="white" />
                ) : (
                  <Text className="text-white font-semibold">
                    Yes, merge my habits
                  </Text>
                )}
              </Pressable>

              <Pressable
                onPress={() => handleMergeChoice(false)}
                disabled={isLoading}
                className="border border-border py-3 px-6 rounded-lg items-center"
              >
                <Text className="text-foreground font-semibold">
                  No, discard them
                </Text>
              </Pressable>

              <Pressable
                onPress={() => {
                  setShowMergeModal(false);
                  setPendingLogin(null);
                }}
                disabled={isLoading}
                className="py-2 items-center"
              >
                <Text className="text-muted">Cancel</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}
