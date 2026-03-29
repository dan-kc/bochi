import { useState } from "react";
import { View, Text, Pressable, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { BottomSheet } from "../BottomSheet";
import { UpdateEmailModal } from "./UpdateEmailModal";
import { ChangePasswordModal } from "./ChangePasswordModal";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

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
  const colors = useColors();

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
      <BottomSheet
        visible={visible && !showUpdateEmail && !showChangePassword}
        onClose={onClose}
      >
        {/* Header */}
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <Text style={[styles.headerText, { color: colors.foreground }]}>
            Account
          </Text>
        </View>

        {/* Email Row */}
        <Pressable
          onPress={() => setShowUpdateEmail(true)}
          style={[styles.emailRow, { borderBottomColor: colors.border }]}
        >
          <Text style={[styles.labelText, { color: colors.muted }]}>Email</Text>
          <View style={styles.spacer} />
          <Text style={[styles.emailText, { color: colors.foreground }]} numberOfLines={1}>
            {currentEmail}
          </Text>
          <Ionicons name="chevron-forward" size={20} color={colors.muted} />
        </Pressable>

        {/* Password Row */}
        <View style={styles.passwordSection}>
          <Text style={[styles.passwordLabel, { color: colors.muted }]}>Password</Text>
          <Pressable
            onPress={() => setShowChangePassword(true)}
            style={[styles.changePasswordButton, { backgroundColor: colors.surface }]}
          >
            <Text style={[styles.changePasswordText, { color: colors.foreground }]}>Change Password</Text>
          </Pressable>
        </View>
      </BottomSheet>

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

const styles = StyleSheet.create({
  header: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  headerText: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
    textAlign: "center",
  },
  emailRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
    borderBottomWidth: 1,
  },
  labelText: {
    fontSize: fontSize.base,
  },
  spacer: {
    flex: 1,
  },
  emailText: {
    fontSize: fontSize.base,
    marginRight: spacing[2],
  },
  passwordSection: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[4],
    paddingBottom: spacing[8],
  },
  passwordLabel: {
    fontSize: fontSize.base,
    marginBottom: spacing[3],
  },
  changePasswordButton: {
    borderRadius: borderRadius.xl,
    paddingVertical: spacing[4],
    alignItems: "center",
  },
  changePasswordText: {
    fontSize: fontSize.base,
  },
});
