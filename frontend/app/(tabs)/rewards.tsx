import { useState, useCallback, useEffect, useMemo } from "react";
import { View, Text, Pressable, Modal, Alert } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useRewardsContext } from "@/lib/RewardContext";
import { useRewardPriceUpdate } from "@/lib/RewardPriceUpdateContext";
import { RewardItem } from "@/components/RewardItem";
import { RewardForm } from "@/components/RewardForm";
import { DamageRanker } from "@/components/DamageRanker";
import { SyncStatusIcon } from "@/components/SyncStatusIcon";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import type { Reward, RewardInput } from "@/lib/reward";
import { REWARD_SORT_OPTIONS, DEFAULT_REWARD_SORT, type RewardSortKey } from "@/lib/rewardSortOptions";
import { sortRewards, getDisplayMode } from "@/lib/rewardSorting";

export default function Rewards() {
  const {
    rewards,
    rankedRewards,
    selectedReward,
    userId,
    createReward,
    updateReward,
    deleteReward,
    purchaseReward,
    selectReward,
    setIsEditing,
  } = useRewardsContext();

  const [isRewardFormVisible, setIsRewardFormVisible] = useState(false);
  const [isRankingVisible, setIsRankingVisible] = useState(false);
  const [rewardToRank, setRewardToRank] = useState<Reward | null>(null);
  const [sortKey, setSortKey] = useState<RewardSortKey>(DEFAULT_REWARD_SORT);

  // Price update context
  const { updatePrices, prices } = useRewardPriceUpdate();

  // Sort rewards
  const displayRewards = useMemo(() => {
    return sortRewards(rewards, sortKey, prices);
  }, [rewards, sortKey, prices]);

  const displayMode = getDisplayMode(sortKey);

  // Update prices when rewards change
  useEffect(() => {
    updatePrices(rewards);
  }, [rewards, updatePrices]);

  const handleAddReward = useCallback(() => {
    selectReward(null);
    setIsEditing(false);
    setIsRewardFormVisible(true);
  }, [selectReward, setIsEditing]);

  const handleRewardPress = useCallback(
    (reward: Reward) => {
      selectReward(reward);
      setIsEditing(true);
      setIsRewardFormVisible(true);
    },
    [selectReward, setIsEditing],
  );

  const handleSave = useCallback(
    async (input: RewardInput) => {
      if (selectedReward) {
        await updateReward(selectedReward.id, input);
        setIsRewardFormVisible(false);
        selectReward(null);
      } else {
        const newReward = await createReward(input);
        setIsRewardFormVisible(false);
        selectReward(null);
        // After creating a new reward, offer to set damage
        setRewardToRank(newReward);
        setIsRankingVisible(true);
      }
    },
    [selectedReward, updateReward, createReward, selectReward],
  );

  const handleCancel = useCallback(() => {
    setIsRewardFormVisible(false);
    selectReward(null);
  }, [selectReward]);

  const handleDelete = useCallback(async () => {
    if (selectedReward) {
      await deleteReward(selectedReward.id);
      setIsRewardFormVisible(false);
      selectReward(null);
    }
  }, [selectedReward, deleteReward, selectReward]);

  const handleRankComplete = useCallback(
    async (rank: string) => {
      if (rewardToRank) {
        await updateReward(rewardToRank.id, { damage_rank: rank });
      }
      setIsRankingVisible(false);
      setRewardToRank(null);
    },
    [rewardToRank, updateReward],
  );

  const handleRankSkip = useCallback(() => {
    setIsRankingVisible(false);
    setRewardToRank(null);
  }, []);

  const handlePurchase = useCallback(
    async (reward: Reward) => {
      try {
        const price = await purchaseReward(reward);
        // Recalculate prices since purchase count changed
        updatePrices(rewards);
        Alert.alert("Purchased!", `Spent ${price} tofu on "${reward.name}"`);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Failed to purchase reward";
        Alert.alert("Cannot Purchase", message);
      }
    },
    [purchaseReward, updatePrices, rewards],
  );

  const handleRerank = useCallback(() => {
    if (selectedReward) {
      setIsRewardFormVisible(false);
      setRewardToRank(selectedReward);
      setIsRankingVisible(true);
    }
  }, [selectedReward]);

  const renderItem = useCallback(
    ({ item }: { item: Reward }) => (
      <RewardItem
        reward={item}
        onPress={handleRewardPress}
        displayMode={displayMode}
      />
    ),
    [handleRewardPress, displayMode],
  );

  const keyExtractor = useCallback((item: Reward) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-border">
          <View className="flex-row justify-between items-center mb-3">
            <Text className="text-2xl font-bold text-foreground">Rewards</Text>
            <View className="flex-row items-center gap-2">
              <BalanceDisplay />
              <SyncStatusIcon />
            </View>
          </View>
          <View className="flex-row justify-end items-center">
            <SortDropdown
              options={REWARD_SORT_OPTIONS}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayRewards.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-muted text-center mb-4">
              No rewards yet. Add your first reward to get started.
            </Text>
          </View>
        ) : (
          <LegendList
            data={displayRewards}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            extraData={{ sortKey, displayMode }}
            contentContainerStyle={{ padding: 16 }}
            estimatedItemSize={100}
          />
        )}

        <View className="p-4 border-t border-border">
          <Pressable
            onPress={handleAddReward}
            className="bg-accent py-3 px-6 rounded-lg items-center"
          >
            <Text className="text-white font-semibold text-base">Add Reward</Text>
          </Pressable>
        </View>

        <Modal
          visible={isRewardFormVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleCancel}
        >
          <SafeAreaView className="flex-1 bg-background">
            <RewardForm
              reward={selectedReward}
              userId={userId}
              onSave={handleSave}
              onCancel={handleCancel}
              onDelete={selectedReward ? handleDelete : undefined}
              onRerank={selectedReward && rewards.length > 1 ? handleRerank : undefined}
              onPurchase={selectedReward ? handlePurchase : undefined}
            />
          </SafeAreaView>
        </Modal>

        <Modal
          visible={isRankingVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleRankSkip}
        >
          <SafeAreaView className="flex-1 bg-background">
            {rewardToRank && (
              <DamageRanker
                reward={rewardToRank}
                existingRewards={rankedRewards.filter(r => r.id !== rewardToRank.id && r.damage_rank !== null)}
                onComplete={handleRankComplete}
                onSkip={handleRankSkip}
              />
            )}
          </SafeAreaView>
        </Modal>
      </View>
    </SafeAreaView>
  );
}
