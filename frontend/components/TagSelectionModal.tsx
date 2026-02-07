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
  useHabitTagActions,
} from "@/lib/store/hooks";
import { generateRandomColor } from "@/lib/tag";
import type { Tag } from "@/lib/tag";

interface TagSelectionModalProps {
  visible: boolean;
  onClose: () => void;
  habitId: string;
  userId: string;
  selectedTagIds: string[];
  onColorEdit: (tag: Tag) => void;
}

export function TagSelectionModal({
  visible,
  onClose,
  habitId,
  userId,
  selectedTagIds,
  onColorEdit,
}: TagSelectionModalProps) {
  const [search, setSearch] = useState("");
  const [newTagName, setNewTagName] = useState("");
  const [isCreating, setIsCreating] = useState(false);

  const allTags = useAllTagsIncludingDeleted(userId);
  const { createTag, restoreTag } = useTagActions();
  const { addTagToHabit, removeTagFromHabit } = useHabitTagActions();

  // Filter tags by search query
  const filteredTags = useMemo(() => {
    if (!search.trim()) return allTags;
    const query = search.toLowerCase();
    return allTags.filter((tag) => tag.name.toLowerCase().includes(query));
  }, [allTags, search]);

  const selectedSet = useMemo(() => new Set(selectedTagIds), [selectedTagIds]);

  const handleToggleTag = async (tag: Tag) => {
    if (selectedSet.has(tag.id)) {
      await removeTagFromHabit(habitId, tag.id);
    } else {
      await addTagToHabit(userId, habitId, tag.id);
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
      await addTagToHabit(userId, habitId, tag.id);
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
      <View className="flex-1 bg-white">
        {/* Header */}
        <View className="flex-row items-center justify-between px-4 py-3 border-b border-gray-200">
          <Text className="text-lg font-semibold">Select Tags</Text>
          <Pressable onPress={onClose} className="p-2">
            <Ionicons name="close" size={24} color="#374151" />
          </Pressable>
        </View>

        {/* Search */}
        <View className="px-4 py-3 border-b border-gray-100">
          <View className="flex-row items-center bg-gray-100 rounded-lg px-3 py-2">
            <Ionicons name="search" size={20} color="#9ca3af" />
            <TextInput
              className="flex-1 ml-2 text-base"
              placeholder="Search tags..."
              value={search}
              onChangeText={setSearch}
            />
            {search ? (
              <Pressable onPress={() => setSearch("")}>
                <Ionicons name="close-circle" size={20} color="#9ca3af" />
              </Pressable>
            ) : null}
          </View>
        </View>

        {/* Tag List */}
        <ScrollView className="flex-1 px-4">
          {filteredTags.length === 0 && !search && (
            <View className="py-8 items-center">
              <Text className="text-gray-500">No tags yet. Create one below.</Text>
            </View>
          )}
          {filteredTags.length === 0 && search && (
            <View className="py-8 items-center">
              <Text className="text-gray-500">
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
                className={`flex-row items-center py-3 border-b border-gray-100 ${
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
                          ? "bg-purple-500 border-purple-500"
                          : "border-gray-300"
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
                    isDeleted ? "text-gray-400 line-through" : "text-gray-900"
                  }`}
                >
                  {tag.name}
                </Text>

                {/* Restore button for deleted tags */}
                {isDeleted && (
                  <Pressable
                    onPress={() => handleRestoreTag(tag)}
                    className="bg-blue-100 px-3 py-1 rounded"
                  >
                    <Text className="text-blue-600 text-sm font-medium">
                      Restore
                    </Text>
                  </Pressable>
                )}
              </View>
            );
          })}
        </ScrollView>

        {/* Create new tag */}
        <View className="px-4 py-3 border-t border-gray-200">
          <View className="flex-row items-center gap-2">
            <TextInput
              className="flex-1 border border-gray-300 rounded-lg px-4 py-2 text-base"
              placeholder="New tag name..."
              value={newTagName}
              onChangeText={setNewTagName}
              editable={!isCreating}
            />
            <Pressable
              onPress={handleCreateTag}
              disabled={!newTagName.trim() || isCreating}
              className={`px-4 py-2 rounded-lg ${
                newTagName.trim() && !isCreating
                  ? "bg-purple-500"
                  : "bg-gray-300"
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
