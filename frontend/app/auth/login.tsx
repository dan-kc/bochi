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
import { taskStore } from "@/lib/store/taskStore";
import { markTasksDirty, clearAllDirtyFlags, clearLastSyncTime } from "@/lib/sync/syncStorage";
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

  const localTaskCount = user ? taskStore.getTaskCount(user.id) : 0;

  const performLogin = async (
    loginEmail: string,
    loginPassword: string,
    mergeTasks: boolean,
  ) => {
    setIsLoading(true);
    try {
      if (mergeTasks && user) {
        // Login first to get new user ID
        await login(loginEmail, loginPassword);

        // Mark all tasks dirty so they'll be pushed to the server
        // The server will assign them to the authenticated user
        const taskIds = await taskStore.updateAllTasksUserId("");
        await markTasksDirty(taskIds);
        await clearLastSyncTime(); // Force full sync

        // Wait for sync to complete before navigating
        // This ensures tasks are pushed to the server
        await waitForSync();
      } else {
        // Clear local tasks before login
        await taskStore.clearAllTasks();
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

    // Check if user is anonymous and has local tasks
    if (isAnonymous && localTaskCount > 0) {
      // Show merge dialog
      setPendingLogin({ email, password });
      setShowMergeModal(true);
      return;
    }

    // No local tasks or not anonymous - proceed with login
    await performLogin(email, password, false);
  };

  const handleMergeChoice = async (merge: boolean) => {
    if (!pendingLogin) return;
    await performLogin(pendingLogin.email, pendingLogin.password, merge);
  };

  return (
    <SafeAreaView className="flex-1 bg-white">
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        className="flex-1"
      >
        <View className="flex-1 p-6 justify-center max-w-md mx-auto w-full">
          <Text className="text-3xl font-bold text-gray-900 mb-2">
            Welcome back
          </Text>
          <Text className="text-gray-600 mb-8">
            Log in to your Tofustash account
          </Text>

          {errors.length > 0 && (
            <View className="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
              {errors.map((error, index) => (
                <Text key={index} className="text-red-600 text-sm">
                  {error}
                </Text>
              ))}
            </View>
          )}

          <View className="gap-4">
            <View>
              <Text className="text-sm font-medium text-gray-700 mb-1">
                Email
              </Text>
              <TextInput
                className="border border-gray-300 rounded-lg px-4 py-3 text-base"
                placeholder="you@example.com"
                value={email}
                onChangeText={setEmail}
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                editable={!isLoading}
              />
            </View>

            <View>
              <Text className="text-sm font-medium text-gray-700 mb-1">
                Password
              </Text>
              <TextInput
                className="border border-gray-300 rounded-lg px-4 py-3 text-base"
                placeholder="Enter your password"
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
              className="bg-blue-500 py-3 px-6 rounded-lg items-center mt-2"
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
            <Text className="text-gray-600">Don't have an account?</Text>
            <Link href="/auth/register" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    className={`font-semibold ${hovered ? "text-blue-700" : "text-blue-500"}`}
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
                    className={`${hovered ? "text-gray-900" : "text-gray-500"}`}
                  >
                    Back to Settings
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>
        </View>
      </KeyboardAvoidingView>

      {/* Merge Tasks Modal */}
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
          <View className="bg-white rounded-2xl p-6 max-w-sm w-full">
            <Text className="text-xl font-bold text-gray-900 mb-2">
              Merge Your Tasks?
            </Text>
            <Text className="text-gray-600 mb-4">
              You have {localTaskCount} task{localTaskCount !== 1 ? "s" : ""} on
              this device. Would you like to add them to your account?
            </Text>

            <View className="gap-3">
              <Pressable
                onPress={() => handleMergeChoice(true)}
                disabled={isLoading}
                className="bg-blue-500 py-3 px-6 rounded-lg items-center"
              >
                {isLoading ? (
                  <ActivityIndicator color="white" />
                ) : (
                  <Text className="text-white font-semibold">
                    Yes, merge my tasks
                  </Text>
                )}
              </Pressable>

              <Pressable
                onPress={() => handleMergeChoice(false)}
                disabled={isLoading}
                className="border border-gray-300 py-3 px-6 rounded-lg items-center"
              >
                <Text className="text-gray-700 font-semibold">
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
                <Text className="text-gray-500">Cancel</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}
