package com.tofustash.app.ui.rewards

import com.tofustash.app.data.local.entity.RewardEntity
import com.tofustash.app.ui.habits.SortOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RewardsViewModelTest {

    private fun makeReward(
        id: String = "r1",
        name: String = "Test",
        price: Int = 500,
        previousPrice: Int = 400,
        damageRank: String? = null,
        frequency: Double? = null,
        createdAt: String = "2024-01-01T00:00:00",
    ) = RewardWithPrice(
        reward = RewardEntity(
            id = id, userId = "u1", name = name, description = "",
            createdAt = createdAt, updatedAt = createdAt,
            damageRank = damageRank, maxDailyFrequency = frequency,
        ),
        price = price,
        previousPrice = previousPrice,
    )

    @Test
    fun sortByPriceDescending() {
        val rewards = listOf(makeReward("a", price = 100), makeReward("b", price = 500), makeReward("c", price = 300))
        val sorted = RewardsViewModel.sortRewards(rewards, SortOption.PRICE_DESC)
        assertEquals(listOf(500, 300, 100), sorted.map { it.price })
    }

    @Test
    fun sortByPriceAscending() {
        val rewards = listOf(makeReward("a", price = 500), makeReward("b", price = 100))
        val sorted = RewardsViewModel.sortRewards(rewards, SortOption.PRICE_ASC)
        assertEquals(listOf(100, 500), sorted.map { it.price })
    }

    @Test
    fun sortByDamageDescending() {
        val rewards = listOf(
            makeReward("a", damageRank = "b"),
            makeReward("b", damageRank = "m"),
            makeReward("c", damageRank = "a"),
        )
        val sorted = RewardsViewModel.sortRewards(rewards, SortOption.DIFFICULTY_DESC)
        assertEquals(listOf("m", "b", "a"), sorted.map { it.reward.damageRank })
    }

    @Test
    fun sortByNewest() {
        val rewards = listOf(
            makeReward("a", createdAt = "2024-01-01T00:00:00"),
            makeReward("b", createdAt = "2024-06-01T00:00:00"),
        )
        val sorted = RewardsViewModel.sortRewards(rewards, SortOption.NEWEST)
        assertEquals(listOf("b", "a"), sorted.map { it.reward.id })
    }

    @Test
    fun sortByFrequencyDescending() {
        val rewards = listOf(
            makeReward("a", frequency = 1.0),
            makeReward("b", frequency = 3.0),
            makeReward("c", frequency = null),
        )
        val sorted = RewardsViewModel.sortRewards(rewards, SortOption.FREQUENCY_DESC)
        assertEquals(listOf("b", "a", "c"), sorted.map { it.reward.id })
    }

    @Test
    fun formStateIsEditingWhenRewardPresent() {
        val reward = makeReward().reward
        val state = RewardFormState(editingReward = reward, name = reward.name)
        assertTrue(state.isEditing)
    }

    @Test
    fun formStateIsNotEditingWhenEmpty() {
        val state = RewardFormState()
        assertEquals(false, state.isEditing)
    }
}
