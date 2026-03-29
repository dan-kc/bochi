import { useState, useMemo } from "react";
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import {
  useAllTagsIncludingDeleted,
  useTagActions,
} from "@/lib/store/hooks";
import { generateRandomColor } from "@/lib/tag";
import type { Tag } from "@/lib/tag";
import { BottomSheet } from "./BottomSheet";
import { TagEditSheet } from "./TagEditSheet";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

interface TagSelectionModalProps {
  visible: boolean;
  onClose: () => void;
  entityId: string;
  userId: string;
  selectedTagIds: string[];
  onColorEdit: (tag: Tag) => void;
  addTag: (userId: string, entityId: string, tagId: string) => Promise<any>;
  removeTag: (entityId: string, tagId: string) => Promise<unknown>;
}

export function TagSelectionModal({
  visible,
  onClose,
  entityId,
  userId,
  selectedTagIds,
  onColorEdit,
  addTag,
  removeTag,
}: TagSelectionModalProps) {
  const colors = useColors();
  const [search, setSearch] = useState("");
  const [isCreating, setIsCreating] = useState(false);
  const [editingTag, setEditingTag] = useState<Tag | null>(null);

  const allTags = useAllTagsIncludingDeleted(userId);
  const { createTag, restoreTag, updateTag } = useTagActions();

  // Filter tags by search query
  const filteredTags = useMemo(() => {
    if (!search.trim()) return allTags;
    const query = search.toLowerCase();
    return allTags.filter((tag) => tag.name.toLowerCase().includes(query));
  }, [allTags, search]);

  const selectedSet = useMemo(() => new Set(selectedTagIds), [selectedTagIds]);

  // Check if search matches any existing tag name exactly
  const searchMatchesExact = useMemo(() => {
    if (!search.trim()) return true;
    const query = search.trim().toLowerCase();
    return allTags.some((tag) => tag.name.toLowerCase() === query);
  }, [allTags, search]);

  const handleToggleTag = async (tag: Tag) => {
    if (selectedSet.has(tag.id)) {
      await removeTag(entityId, tag.id);
    } else {
      await addTag(userId, entityId, tag.id);
    }
  };

  const handleRestoreTag = async (tag: Tag) => {
    await restoreTag(tag.id);
  };

  const handleCreateFromSearch = async () => {
    const name = search.trim();
    if (!name) return;

    setIsCreating(true);
    try {
      const tag = await createTag(userId, {
        name,
        color_hex: generateRandomColor(),
      });
      await addTag(userId, entityId, tag.id);
      setSearch("");
      // Open edit sheet for the new tag
      setEditingTag(tag);
    } finally {
      setIsCreating(false);
    }
  };

  const handleTagEditSave = async (name: string, color: string) => {
    if (editingTag) {
      await updateTag(editingTag.id, { name, color_hex: color });
      setEditingTag(null);
    }
  };

  return (
    <>
      <BottomSheet visible={visible && !editingTag} onClose={onClose}>
        {/* Header */}
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <Pressable onPress={onClose} style={styles.headerButton}>
            <Ionicons name="close" size={24} color={colors.muted} />
          </Pressable>
          <Text style={[styles.headerText, { color: colors.foreground }]}>Tags</Text>
          <Pressable onPress={onClose} style={styles.headerButton}>
            <Ionicons name="checkmark" size={24} color={colors.accent} />
          </Pressable>
        </View>

        {/* Tag List */}
        <ScrollView style={styles.scrollView}>
          {filteredTags.map((tag) => {
            const isSelected = selectedSet.has(tag.id);
            const isDeleted = tag.deleted_at !== null;

            return (
              <View
                key={tag.id}
                style={[
                  styles.tagRow,
                  { borderBottomColor: colors.border, opacity: isDeleted ? 0.5 : 1 }
                ]}
              >
                {/* Checkbox */}
                {!isDeleted && (
                  <Pressable
                    onPress={() => handleToggleTag(tag)}
                    style={styles.checkboxContainer}
                  >
                    <View
                      style={[
                        styles.checkbox,
                        {
                          backgroundColor: isSelected ? colors.accent : "transparent",
                          borderColor: isSelected ? colors.accent : colors.border,
                        }
                      ]}
                    >
                      {isSelected && (
                        <Ionicons name="checkmark" size={16} color="white" />
                      )}
                    </View>
                  </Pressable>
                )}

                {/* Color dot + name (pressable to toggle) */}
                <Pressable
                  onPress={() => !isDeleted && handleToggleTag(tag)}
                  style={styles.tagContent}
                  disabled={isDeleted}
                >
                  <View
                    style={[styles.colorDot, { backgroundColor: tag.color_hex }]}
                  />
                  <Text
                    style={[
                      styles.tagName,
                      {
                        color: isDeleted ? colors.muted : colors.foreground,
                        textDecorationLine: isDeleted ? "line-through" : "none",
                      }
                    ]}
                  >
                    {tag.name}
                  </Text>
                </Pressable>

                {/* Edit button */}
                {!isDeleted && (
                  <Pressable
                    onPress={() => setEditingTag(tag)}
                    style={styles.editButton}
                  >
                    <Ionicons name="pencil" size={16} color={colors.muted} />
                  </Pressable>
                )}

                {/* Restore button for deleted tags */}
                {isDeleted && (
                  <Pressable
                    onPress={() => handleRestoreTag(tag)}
                    style={[styles.restoreButton, { backgroundColor: colors.surface }]}
                  >
                    <Text style={[styles.restoreText, { color: colors.accentSecondary }]}>
                      Restore
                    </Text>
                  </Pressable>
                )}
              </View>
            );
          })}

          {/* Add from search */}
          {search.trim() && !searchMatchesExact && (
            <Pressable
              onPress={handleCreateFromSearch}
              disabled={isCreating}
              style={styles.addFromSearchButton}
            >
              <Ionicons name="add-circle-outline" size={24} color={colors.accent} />
              <Text style={[styles.addFromSearchText, { color: colors.accent }]}>
                Add &quot;{search.trim()}&quot;
              </Text>
            </Pressable>
          )}
        </ScrollView>

        {/* Search */}
        <View style={[styles.searchContainer, { borderTopColor: colors.border }]}>
          <View style={[styles.searchInput, { backgroundColor: colors.surface }]}>
            <Ionicons name="search" size={20} color={colors.muted} />
            <TextInput
              style={[styles.searchInputText, { color: colors.foreground }]}
              placeholder="Search tags..."
              placeholderTextColor={colors.muted}
              value={search}
              onChangeText={setSearch}
            />
            {search ? (
              <Pressable onPress={() => setSearch("")}>
                <Ionicons name="close-circle" size={20} color={colors.muted} />
              </Pressable>
            ) : null}
          </View>
        </View>
      </BottomSheet>

      {/* Tag Edit Sheet */}
      {editingTag && (
        <TagEditSheet
          visible={!!editingTag}
          onClose={() => setEditingTag(null)}
          tagName={editingTag.name}
          tagColor={editingTag.color_hex}
          onSave={handleTagEditSave}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    borderBottomWidth: 1,
  },
  headerButton: {
    padding: spacing[1],
  },
  headerText: {
    fontSize: fontSize.base,
    fontWeight: fontWeight.semibold,
  },
  scrollView: {
    maxHeight: 320,
    paddingHorizontal: spacing[4],
  },
  tagRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: spacing[3],
    borderBottomWidth: 1,
  },
  checkboxContainer: {
    marginRight: spacing[3],
  },
  checkbox: {
    width: 24,
    height: 24,
    borderRadius: borderRadius.DEFAULT,
    borderWidth: 2,
    alignItems: "center",
    justifyContent: "center",
  },
  tagContent: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
  },
  colorDot: {
    width: 24,
    height: 24,
    borderRadius: borderRadius.full,
    marginRight: spacing[3],
  },
  tagName: {
    flex: 1,
    fontSize: fontSize.base,
  },
  editButton: {
    padding: spacing[2],
  },
  restoreButton: {
    paddingHorizontal: spacing[3],
    paddingVertical: spacing[1],
    borderRadius: borderRadius.DEFAULT,
  },
  restoreText: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.medium,
  },
  addFromSearchButton: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: spacing[3],
  },
  addFromSearchText: {
    marginLeft: spacing[2],
    fontSize: fontSize.base,
  },
  searchContainer: {
    paddingHorizontal: spacing[4],
    paddingVertical: spacing[3],
    borderTopWidth: 1,
  },
  searchInput: {
    flexDirection: "row",
    alignItems: "center",
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing[3],
    paddingVertical: spacing[2],
  },
  searchInputText: {
    flex: 1,
    marginLeft: spacing[2],
    fontSize: fontSize.base,
  },
});
