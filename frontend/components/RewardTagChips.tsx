import { View, Text } from "react-native";
import { useTagsForReward } from "@/lib/store/hooks";

interface RewardTagChipsProps {
  rewardId: string;
  maxTags?: number;
}

/**
 * Displays tag chips for a reward.
 * Shows up to maxTags tags with a "+N more" indicator if truncated.
 */
export function RewardTagChips({ rewardId, maxTags = 3 }: RewardTagChipsProps) {
  const tags = useTagsForReward(rewardId);

  if (tags.length === 0) return null;

  const visibleTags = tags.slice(0, maxTags);
  const remainingCount = tags.length - maxTags;

  return (
    <View className="flex-row flex-wrap gap-1 mt-1">
      {visibleTags.map((tag) => (
        <View
          key={tag.id}
          className="px-2 py-0.5 rounded"
          style={{ backgroundColor: tag.color_hex + "30" }}
        >
          <Text
            className="text-xs font-medium"
            style={{ color: tag.color_hex }}
            numberOfLines={1}
          >
            {tag.name}
          </Text>
        </View>
      ))}
      {remainingCount > 0 && (
        <View className="bg-gray-100 px-2 py-0.5 rounded">
          <Text className="text-xs text-gray-600">+{remainingCount} more</Text>
        </View>
      )}
    </View>
  );
}
