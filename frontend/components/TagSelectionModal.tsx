import { useState, useMemo } from "react";
import { View, Text, TextInput, Pressable, ScrollView } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import {
  useAllTagsIncludingDeleted,
  useTagActions,
} from "@/lib/store/hooks";
import { generateRandomColor } from "@/lib/tag";
import type { Tag } from "@/lib/tag";
import { BottomSheet } from "./BottomSheet";
import { TagEditSheet } from "./TagEditSheet";

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
        <View className="flex-row items-center justify-between px-4 py-3 border-b border-border">
          <Pressable onPress={onClose} className="p-1">
            <Ionicons name="close" size={24} color="var(--color-muted)" />
          </Pressable>
          <Text className="text-base font-semibold text-foreground">Tags</Text>
          <Pressable onPress={onClose} className="p-1">
            <Ionicons name="checkmark" size={24} color="var(--color-accent)" />
          </Pressable>
        </View>

        {/* Tag List */}
        <ScrollView className="max-h-80 px-4">
          {filteredTags.map((tag) => {
            const isSelected = selectedSet.has(tag.id);
            const isDeleted = tag.deleted_at !== null;

            return (
              <View
                key={tag.id}
                className={`flex-row items-center py-3 border-b border-border ${
                  isDeleted ? "opacity-50" : ""
                }`}
              >
                {/* Checkbox */}
                {!isDeleted && (
                  <Pressable
                    onPress={() => handleToggleTag(tag)}
                    className="mr-3"
                  >
                    <View
                      className={`w-6 h-6 rounded border-2 items-center justify-center ${
                        isSelected
                          ? "bg-accent border-accent"
                          : "border-border"
                      }`}
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
                  className="flex-1 flex-row items-center"
                  disabled={isDeleted}
                >
                  <View
                    className="w-6 h-6 rounded-full mr-3"
                    style={{ backgroundColor: tag.color_hex }}
                  />
                  <Text
                    className={`flex-1 text-base ${
                      isDeleted ? "text-muted line-through" : "text-foreground"
                    }`}
                  >
                    {tag.name}
                  </Text>
                </Pressable>

                {/* Edit button */}
                {!isDeleted && (
                  <Pressable
                    onPress={() => setEditingTag(tag)}
                    className="p-2"
                  >
                    <Ionicons name="pencil" size={16} color="var(--color-muted)" />
                  </Pressable>
                )}

                {/* Restore button for deleted tags */}
                {isDeleted && (
                  <Pressable
                    onPress={() => handleRestoreTag(tag)}
                    className="bg-surface px-3 py-1 rounded"
                  >
                    <Text className="text-accent-secondary text-sm font-medium">
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
              className="flex-row items-center py-3"
            >
              <Ionicons name="add-circle-outline" size={24} color="var(--color-accent)" />
              <Text className="text-accent ml-2 text-base">
                Add &quot;{search.trim()}&quot;
              </Text>
            </Pressable>
          )}
        </ScrollView>

        {/* Search */}
        <View className="px-4 py-3 border-t border-border">
          <View className="flex-row items-center bg-surface rounded-lg px-3 py-2">
            <Ionicons name="search" size={20} color="var(--color-muted)" />
            <TextInput
              className="flex-1 ml-2 text-base text-foreground"
              placeholder="Search tags..."
              placeholderTextColor="var(--color-muted)"
              value={search}
              onChangeText={setSearch}
            />
            {search ? (
              <Pressable onPress={() => setSearch("")}>
                <Ionicons name="close-circle" size={20} color="var(--color-muted)" />
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
