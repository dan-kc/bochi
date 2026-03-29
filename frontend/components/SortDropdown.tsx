import { useState } from "react";
import { View, Text, Pressable, Modal, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface SortOption<K extends string> {
  key: K;
  label: string;
}

interface SortDropdownProps<K extends string> {
  options: SortOption<K>[];
  selectedKey: K;
  onSelect: (key: K) => void;
}

export function SortDropdown<K extends string>({
  options,
  selectedKey,
  onSelect,
}: SortDropdownProps<K>) {
  const [isOpen, setIsOpen] = useState(false);
  const colors = useColors();

  const selectedOption = options.find((opt) => opt.key === selectedKey);
  const selectedLabel = selectedOption?.label ?? "Sort";

  const handleSelect = (key: K) => {
    onSelect(key);
    setIsOpen(false);
  };

  return (
    <>
      <Pressable
        onPress={() => setIsOpen(true)}
        style={styles.trigger}
      >
        <Text style={[styles.sortByText, { color: colors.muted }]}>sort by </Text>
        <Text style={[styles.selectedText, { color: colors.accent }]}>
          {selectedLabel}
        </Text>
        <Ionicons
          name="chevron-down"
          size={14}
          color={colors.accent}
          style={styles.chevron}
        />
      </Pressable>

      <Modal
        visible={isOpen}
        transparent
        animationType="fade"
        onRequestClose={() => setIsOpen(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setIsOpen(false)}
        >
          <Pressable
            style={[styles.modalContent, { backgroundColor: colors.background }]}
            onPress={(e) => e.stopPropagation()}
          >
            <View style={[styles.modalHeader, { borderBottomColor: colors.border }]}>
              <Text style={[styles.modalTitle, { color: colors.foreground }]}>
                Sort By
              </Text>
            </View>
            <View style={styles.optionsContainer}>
              {options.map((option) => (
                <Pressable
                  key={option.key}
                  onPress={() => handleSelect(option.key)}
                  style={[
                    styles.optionItem,
                    option.key === selectedKey && { backgroundColor: colors.surface },
                  ]}
                >
                  <View style={styles.optionContent}>
                    <Text
                      style={[
                        styles.optionText,
                        {
                          color: option.key === selectedKey ? colors.accent : colors.foreground,
                          fontWeight: option.key === selectedKey ? fontWeight.medium : fontWeight.normal,
                        },
                      ]}
                    >
                      {option.label}
                    </Text>
                    {option.key === selectedKey && (
                      <Ionicons name="checkmark" size={20} color={colors.accent} />
                    )}
                  </View>
                </Pressable>
              ))}
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  trigger: {
    flexDirection: "row",
    alignItems: "center",
  },
  sortByText: {
    fontSize: fontSize.sm,
  },
  selectedText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
    textDecorationLine: "underline",
  },
  chevron: {
    marginLeft: 2,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.3)",
    justifyContent: "flex-end",
  },
  modalContent: {
    borderTopLeftRadius: borderRadius["2xl"],
    borderTopRightRadius: borderRadius["2xl"],
    paddingBottom: spacing[8],
  },
  modalHeader: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  modalTitle: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.semibold,
    textAlign: "center",
  },
  optionsContainer: {
    padding: spacing[2],
  },
  optionItem: {
    padding: spacing[4],
    borderRadius: borderRadius.lg,
  },
  optionContent: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  optionText: {
    fontSize: fontSize.base,
  },
});
