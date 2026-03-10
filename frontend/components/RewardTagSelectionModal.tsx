import { useState, useMemo } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  Modal,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import {
  useAllTagsIncludingDeleted,
  useTagActions,
  useRewardTagActions,
} from "@/lib/store/hooks";
import { generateRandomColor } from "@/lib/tag";
import type { Tag } from "@/lib/tag";

interface RewardTagSelectionModalProps {
  visible: boolean;
  onClose: () => void;
  rewardId: string;
  userId: string;
  selectedTagIds: string[];
  onColorEdit: (tag: Tag) => void;
}

export function RewardTagSelectionModal({
  visible,
  onClose,
  rewardId,
  userId,
  selectedTagIds,
  onColorEdit,
}: RewardTagSelectionModalProps) {
  const [search, setSearch] = useState("");
  const [newTagName, setNewTagName] = useState("");
  const [isCreating, setIsCreating] = useState(false);

  const allTags = useAllTagsIncludingDeleted(userId);
  const { createTag, restoreTag } = useTagActions();
  const { addTagToReward, removeTagFromReward } = useRewardTagActions();

  // Filter tags by search query
  const filteredTags = useMemo(() => {
    if (!search.trim()) return allTags;
    const query = search.toLowerCase();
    return allTags.filter((tag) => tag.name.toLowerCase().includes(query));
  }, [allTags, search]);

  const selectedSet = useMemo(() => new Set(selectedTagIds), [selectedTagIds]);

  const handleToggleTag = async (tag: Tag) => {
    if (selectedSet.has(tag.id)) {
      await removeTagFromReward(rewardId, tag.id);
    } else {
      await addTagToReward(userId, rewardId, tag.id);
    }
  };

  const handleRestoreTag = async (tag: Tag) => {
    await restoreTag(tag.id);
  };

  const handleCreateTag = async () => {
    const name = newTagName.trim();
    if (!name) return;

    setIsCreating(true);
    try {
      const tag = await createTag(userId, {
        name,
        color_hex: generateRandomColor(),
      });
      // Auto-select the new tag
      await addTagToReward(userId, rewardId, tag.id);
      setNewTagName("");
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View className="flex-1 bg-background">
        {/* Header */}
        <View className="flex-row items-center justify-between px-4 py-3 border-b border-border">
          <Text className="text-lg font-semibold text-foreground">Select Tags</Text>
          <Pressable onPress={onClose} className="p-2">
            <Ionicons name="close" size={24} color="var(--color-muted)" />
          </Pressable>
        </View>

        {/* Search */}
        <View className="px-4 py-3 border-b border-border">
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

        {/* Tag List */}
        <ScrollView className="flex-1 px-4">
          {filteredTags.length === 0 && !search && (
            <View className="py-8 items-center">
              <Text className="text-muted">No tags yet. Create one below.</Text>
            </View>
          )}
          {filteredTags.length === 0 && search && (
            <View className="py-8 items-center">
              <Text className="text-muted">
                No tags matching &quot;{search}&quot;
              </Text>
            </View>
          )}
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

                {/* Color circle */}
                <Pressable
                  onPress={() => !isDeleted && onColorEdit(tag)}
                  className="mr-3"
                  disabled={isDeleted}
                >
                  <View
                    className="w-8 h-8 rounded-full items-center justify-center"
                    style={{ backgroundColor: tag.color_hex }}
                  >
                    <Ionicons name="color-palette-outline" size={16} color="white" />
                  </View>
                </Pressable>

                {/* Tag name */}
                <Text
                  className={`flex-1 text-base ${
                    isDeleted ? "text-muted line-through" : "text-foreground"
                  }`}
                >
                  {tag.name}
                </Text>

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
        </ScrollView>

        {/* Create new tag */}
        <View className="px-4 py-3 border-t border-border">
          <View className="flex-row items-center gap-2">
            <TextInput
              className="flex-1 border border-border rounded-lg px-4 py-2 text-base text-foreground bg-surface"
              placeholder="New tag name..."
              placeholderTextColor="var(--color-muted)"
              value={newTagName}
              onChangeText={setNewTagName}
              editable={!isCreating}
            />
            <Pressable
              onPress={handleCreateTag}
              disabled={!newTagName.trim() || isCreating}
              className={`px-4 py-2 rounded-lg ${
                newTagName.trim() && !isCreating
                  ? "bg-accent"
                  : "bg-surface"
              }`}
            >
              <Text className="text-white font-medium">Add</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}
