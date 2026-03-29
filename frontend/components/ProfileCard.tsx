import { View, Text, Pressable, Image, StyleSheet } from "react-native";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface ProfileCardProps {
  user?: {
    id: string;
    isAnonymous?: boolean;
    avatarUrl?: string;
  } | null;
  onRegister?: () => void;
  onLogin?: () => void;
  onLogout?: () => void;
  onClaimAccount?: () => void;
}

export default function ProfileCard({
  user,
  onRegister,
  onLogin,
  onLogout,
  onClaimAccount,
}: ProfileCardProps) {
  const colors = useColors();

  // Anonymous user - show claim account prompt
  if (user && user.isAnonymous) {
    return (
      <View style={[styles.card, { backgroundColor: colors.accent }]}>
        <View style={styles.anonymousHeader}>
          <View style={[styles.anonymousAvatar, { backgroundColor: "rgba(255, 255, 255, 0.2)" }]}>
            <Text style={[styles.anonymousAvatarText, { color: colors.white }]}>?</Text>
          </View>
          <View style={styles.flex1}>
            <Text style={[styles.anonymousTitle, { color: colors.white }]}>Anonymous Account</Text>
            <Text style={[styles.anonymousId, { color: colors.white }]}>
              ID: {user.id.slice(0, 8)}...
            </Text>
          </View>
        </View>
        <Text style={[styles.anonymousDescription, { color: colors.white }]}>
          Create an account to sync your data across devices and keep it safe.
        </Text>
        <View style={styles.buttonRow}>
          <Pressable
            onPress={onClaimAccount}
            style={[styles.buttonFlex, styles.buttonPrimary, { backgroundColor: colors.white }]}
          >
            {({ hovered }) => (
              <Text
                style={[styles.buttonTextBold, { color: hovered ? colors.accent : colors.accent }]}
              >
                Create Account
              </Text>
            )}
          </Pressable>
          <Pressable
            onPress={onLogin}
            style={[styles.buttonFlex, styles.buttonOutline, { borderColor: colors.white }]}
          >
            {({ hovered }) => (
              <Text
                style={[styles.buttonTextBold, { color: colors.white, opacity: hovered ? 0.8 : 1 }]}
              >
                Login
              </Text>
            )}
          </Pressable>
        </View>
      </View>
    );
  }

  // Logged in user (not anonymous)
  if (user) {
    return (
      <View style={[styles.card, styles.loggedInCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <View style={styles.loggedInHeader}>
          {user.avatarUrl ? (
            <Image
              source={{ uri: user.avatarUrl }}
              style={[styles.avatar, { backgroundColor: colors.surface }]}
            />
          ) : (
            <View style={[styles.avatar, { backgroundColor: colors.accent }]}>
              <Text style={[styles.avatarText, { color: colors.white }]}>
                {user.id.charAt(0).toUpperCase()}
              </Text>
            </View>
          )}
          <View style={styles.flex1}>
            <Text style={[styles.userName, { color: colors.foreground }]}>
              {user.id.slice(0, 8)}...
            </Text>
            <Text style={[styles.userStatus, { color: colors.accentSecondary }]}>Account synced</Text>
          </View>
        </View>
        {onLogout && (
          <Pressable
            onPress={onLogout}
            style={[styles.logoutButton, { borderColor: colors.border }]}
          >
            {({ hovered }) => (
              <Text
                style={[styles.logoutButtonText, { color: hovered ? colors.foreground : colors.muted }]}
              >
                Log Out
              </Text>
            )}
          </Pressable>
        )}
      </View>
    );
  }

  // No user at all (loading state or error)
  return (
    <View style={[styles.card, { backgroundColor: colors.accent }]}>
      <Text style={[styles.getStartedTitle, { color: colors.white }]}>
        Get Started with Tofustash
      </Text>
      <Text style={[styles.getStartedDescription, { color: colors.white }]}>
        Sign up to sync your habits across devices and unlock premium features.
      </Text>
      <View style={styles.buttonRow}>
        <Pressable
          onPress={onRegister}
          style={[styles.buttonFlex, styles.buttonPrimary, { backgroundColor: colors.white }]}
        >
          {({ hovered }) => (
            <Text
              style={[styles.buttonTextBold, { color: hovered ? colors.accent : colors.accent }]}
            >
              Register
            </Text>
          )}
        </Pressable>
        <Pressable
          onPress={onLogin}
          style={[styles.buttonFlex, styles.buttonOutline, { borderColor: colors.white }]}
        >
          {({ hovered }) => (
            <Text
              style={[styles.buttonTextBold, { color: colors.white, opacity: hovered ? 0.8 : 1 }]}
            >
              Login
            </Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: borderRadius.xl,
    padding: spacing[5],
    marginBottom: spacing[4],
  },
  flex1: {
    flex: 1,
  },
  anonymousHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing[3],
    marginBottom: spacing[3],
  },
  anonymousAvatar: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.full,
    alignItems: "center",
    justifyContent: "center",
  },
  anonymousAvatarText: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
  },
  anonymousTitle: {
    fontSize: fontSize.sm,
    opacity: 0.8,
  },
  anonymousId: {
    fontSize: fontSize.xs,
    opacity: 0.6,
  },
  anonymousDescription: {
    opacity: 0.9,
    marginBottom: spacing[4],
  },
  buttonRow: {
    flexDirection: "row",
    gap: spacing[3],
  },
  buttonFlex: {
    flex: 1,
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  buttonPrimary: {
    // backgroundColor set dynamically
  },
  buttonOutline: {
    borderWidth: 2,
  },
  buttonTextBold: {
    fontWeight: fontWeight.semibold,
  },
  loggedInCard: {
    borderWidth: 1,
    padding: spacing[4],
  },
  loggedInHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing[4],
  },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: borderRadius.full,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarText: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
  },
  userName: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
  },
  userStatus: {
    fontSize: fontSize.sm,
  },
  logoutButton: {
    marginTop: spacing[4],
    paddingVertical: spacing[2],
    paddingHorizontal: spacing[4],
    borderWidth: 1,
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  logoutButtonText: {
    fontWeight: fontWeight.medium,
  },
  getStartedTitle: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    marginBottom: spacing[2],
  },
  getStartedDescription: {
    opacity: 0.8,
    marginBottom: spacing[4],
  },
});
