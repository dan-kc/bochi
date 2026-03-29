import { useState, useCallback, useEffect, useMemo, useRef } from "react";
import { View, Text, Pressable, Modal, Alert, StyleSheet } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useRewardsContext } from "@/lib/RewardContext";
import { useRewardPriceUpdate } from "@/lib/RewardPriceUpdateContext";
import { RewardItem } from "@/components/RewardItem";
import { RewardForm } from "@/components/RewardForm";
import { DamageRanker } from "@/components/DamageRanker";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { SortDropdown } from "@/components/SortDropdown";
import type { Reward, RewardInput } from "@/lib/reward";
import { REWARD_SORT_OPTIONS, DEFAULT_REWARD_SORT, type RewardSortKey } from "@/lib/rewardSortOptions";
import { sortRewards, getDisplayMode } from "@/lib/rewardSorting";
import { useColors, spacing, fontSize, fontWeight, borderRadius } from "@/lib/theme";

export default function Rewards() {
  const colors = useColors();
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
  const [formKey, setFormKey] = useState(0);
  const rankerFromForm = useRef(false);

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
    setFormKey(k => k + 1);
    setIsRewardFormVisible(true);
  }, [selectReward, setIsEditing]);

  const handleRewardPress = useCallback(
    (reward: Reward) => {
      selectReward(reward);
      setIsEditing(true);
      setFormKey(k => k + 1);
      setIsRewardFormVisible(true);
    },
    [selectReward, setIsEditing],
  );

  const handleSave = useCallback(
    async (input: RewardInput) => {
      if (selectedReward) {
        await updateReward(selectedReward.id, input);
      } else {
        const newReward = await createReward(input);
        selectReward(newReward);
        setIsEditing(true);
      }
    },
    [selectedReward, updateReward, createReward, selectReward, setIsEditing],
  );

  const handleFormClose = useCallback(() => {
    setIsRewardFormVisible(false);
  }, []);

  const handleDelete = useCallback(async () => {
    if (selectedReward) {
      await deleteReward(selectedReward.id);
      setIsRewardFormVisible(false);
    }
  }, [selectedReward, deleteReward]);

  const handleRankComplete = useCallback(
    async (rank: string) => {
      if (rewardToRank) {
        await updateReward(rewardToRank.id, { damage_rank: rank });
      }
      setIsRankingVisible(false);
      setRewardToRank(null);
      rankerFromForm.current = false;
    },
    [rewardToRank, updateReward],
  );

  const handleRankSkip = useCallback(() => {
    setIsRankingVisible(false);
    setRewardToRank(null);
    rankerFromForm.current = false;
  }, []);

  const handlePurchase = useCallback(
    async (reward: Reward) => {
      setIsRewardFormVisible(false);
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
      rankerFromForm.current = true;
      setRewardToRank(selectedReward);
      setIsRankingVisible(true);
    }
  }, [selectedReward]);

  const handleSetRank = useCallback(
    (reward: Reward) => {
      setRewardToRank(reward);
      setIsRankingVisible(true);
    },
    [],
  );

  const renderItem = useCallback(
    ({ item }: { item: Reward }) => (
      <RewardItem
        reward={item}
        onPress={handleRewardPress}
        onPurchase={handlePurchase}
        displayMode={displayMode}
        onSetRank={handleSetRank}
      />
    ),
    [handleRewardPress, handlePurchase, displayMode, handleSetRank],
  );

  const keyExtractor = useCallback((item: Reward) => item.id, []);

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]} edges={["top"]}>
      <View style={styles.container}>
        <View style={[styles.header, { borderBottomColor: colors.border }]}>
          <View style={styles.headerRow}>
            <Text style={[styles.title, { color: colors.foreground }]}>Rewards</Text>
            <BalanceDisplay />
          </View>
          <View style={styles.sortRow}>
            <SortDropdown
              options={REWARD_SORT_OPTIONS}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayRewards.length === 0 ? (
          <View style={styles.emptyContainer}>
            <Text style={[styles.emptyText, { color: colors.muted }]}>
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

        <View style={[styles.footer, { borderTopColor: colors.border }]}>
          <Pressable
            onPress={handleAddReward}
            style={[styles.addButton, { backgroundColor: colors.accent }]}
          >
            <Text style={styles.addButtonText}>Add Reward</Text>
          </Pressable>
        </View>

        <Modal
          visible={isRewardFormVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleFormClose}
        >
          <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
            <RewardForm
              key={formKey}
              reward={selectedReward}
              userId={userId}
              onSave={handleSave}
              onClose={handleFormClose}
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
          <SafeAreaView style={[styles.safeArea, { backgroundColor: colors.background }]}>
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

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
  },
  header: {
    padding: spacing[4],
    borderBottomWidth: 1,
  },
  headerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: spacing[3],
  },
  title: {
    fontSize: fontSize["2xl"],
    fontWeight: fontWeight.bold,
  },
  sortRow: {
    flexDirection: "row",
    justifyContent: "flex-end",
    alignItems: "center",
  },
  emptyContainer: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: spacing[4],
  },
  emptyText: {
    textAlign: "center",
    marginBottom: spacing[4],
  },
  footer: {
    padding: spacing[4],
    borderTopWidth: 1,
  },
  addButton: {
    paddingVertical: spacing[3],
    paddingHorizontal: spacing[6],
    borderRadius: borderRadius.lg,
    alignItems: "center",
  },
  addButtonText: {
    color: "white",
    fontWeight: fontWeight.semibold,
    fontSize: fontSize.base,
  },
});
