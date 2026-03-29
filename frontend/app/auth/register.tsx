import { useState } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Link, router } from "expo-router";
import { useAuth } from "@/lib/AuthContext";
import { validateAuthInput, getErrorMessage } from "@/lib/validation";
import type { ApiError } from "@/lib/api";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

export default function Register() {
  const colors = useColors();
  const { register } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const handleRegister = async () => {
    setErrors([]);

    if (password !== confirmPassword) {
      setErrors(["Passwords do not match"]);
      return;
    }

    const validationErrors = validateAuthInput(email, password);
    if (validationErrors.length > 0) {
      setErrors(validationErrors.map(getErrorMessage));
      return;
    }

    setIsLoading(true);
    try {
      await register(email, password);
      router.replace("/settings");
    } catch (error) {
      const apiError = error as ApiError;
      if (apiError.status && apiError.status >= 400 && apiError.status < 500) {
        console.log("[Auth] Register error:", apiError.status, apiError.errors);
      }
      if (apiError.errors && Array.isArray(apiError.errors)) {
        setErrors(apiError.errors.map((e: any) => e.message ?? "An error occurred"));
      } else if (apiError.message) {
        setErrors([apiError.message]);
      } else {
        setErrors(["Registration failed. Please try again."]);
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        style={styles.keyboardView}
      >
        <View style={styles.container}>
          <Text style={[styles.title, { color: colors.foreground }]}>
            Create account
          </Text>
          <Text style={[styles.subtitle, { color: colors.muted }]}>
            Sign up to start using Tofustash
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
                style={[styles.input, { backgroundColor: colors.surface, color: colors.foreground, borderColor: colors.border }]}
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
                style={[styles.input, { backgroundColor: colors.surface, color: colors.foreground, borderColor: colors.border }]}
                placeholder="At least 8 characters"
                placeholderTextColor={colors.muted}
                value={password}
                onChangeText={setPassword}
                secureTextEntry
                autoComplete="new-password"
                editable={!isLoading}
              />
            </View>

            <View>
              <Text style={[styles.label, { color: colors.muted }]}>
                Confirm Password
              </Text>
              <TextInput
                style={[styles.input, { backgroundColor: colors.surface, color: colors.foreground, borderColor: colors.border }]}
                placeholder="Confirm your password"
                placeholderTextColor={colors.muted}
                value={confirmPassword}
                onChangeText={setConfirmPassword}
                secureTextEntry
                autoComplete="new-password"
                editable={!isLoading}
              />
            </View>

            <Pressable
              onPress={handleRegister}
              disabled={isLoading}
              style={[styles.button, { backgroundColor: colors.accent }]}
            >
              {isLoading ? (
                <ActivityIndicator color="white" />
              ) : (
                <Text style={styles.buttonText}>
                  Create Account
                </Text>
              )}
            </Pressable>
          </View>

          <View style={styles.footerRow}>
            <Text style={[styles.footerText, { color: colors.muted }]}>Already have an account?</Text>
            <Link href="/auth/login" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    style={[styles.footerLink, { color: colors.accent }]}
                  >
                    Log In
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>

          <View style={styles.footerCenter}>
            <Link href="/settings" asChild>
              <Pressable>
                {({ hovered }) => (
                  <Text
                    style={{ color: hovered ? colors.foreground : colors.muted }}
                  >
                    Back to Settings
                  </Text>
                )}
              </Pressable>
            </Link>
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  keyboardView: {
    flex: 1,
  },
  container: {
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
    color: "white",
    fontWeight: fontWeight.semibold,
    fontSize: fontSize.base,
  },
  footerRow: {
    flexDirection: "row",
    justifyContent: "center",
    marginTop: spacing[6],
    gap: spacing[1],
  },
  footerText: {
    fontSize: fontSize.base,
  },
  footerLink: {
    fontWeight: fontWeight.semibold,
  },
  footerCenter: {
    flexDirection: "row",
    justifyContent: "center",
    marginTop: spacing[4],
  },
});
