package com.tofustash.app.ui.rewards

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.tofustash.app.data.local.entity.RewardEntity
import com.tofustash.app.data.repository.AuthRepository
import com.tofustash.app.data.repository.AuthState
import com.tofustash.app.data.repository.RewardRepository
import com.tofustash.app.data.repository.TradeRepository
import com.tofustash.app.domain.calculation.RewardPriceCalculator
import com.tofustash.app.ui.habits.FrequencyPeriod
import com.tofustash.app.ui.habits.HabitsViewModel
import com.tofustash.app.ui.habits.SortOption
import com.tofustash.app.ui.habits.TrendDirection
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RewardWithPrice(
    val reward: RewardEntity,
    val price: Int,
    val previousPrice: Int,
)

data class RewardsUiState(
    val rewards: List<RewardWithPrice> = emptyList(),
    val balance: Int = 0,
    val sortOption: SortOption = SortOption.PRICE_DESC,
    val isLoading: Boolean = true,
)

data class RewardFormState(
    val editingReward: RewardEntity? = null,
    val name: String = "",
    val description: String = "",
    val frequency: String = "",
    val frequencyPeriod: FrequencyPeriod = FrequencyPeriod.DAY,
) {
    val isEditing: Boolean get() = editingReward != null
}

@HiltViewModel
class RewardsViewModel @Inject constructor(
    private val rewardRepository: RewardRepository,
    private val tradeRepository: TradeRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _sortOption = MutableStateFlow(SortOption.PRICE_DESC)
    val sortOption: StateFlow<SortOption> = _sortOption.asStateFlow()

    var formState by mutableStateOf<RewardFormState?>(null)
        private set

    val uiState: StateFlow<RewardsUiState> = authRepository.authState
        .flatMapLatest { authState ->
            val userId = (authState as? AuthState.Authenticated)?.userId
            if (userId == null) {
                flowOf(RewardsUiState(isLoading = false))
            } else {
                combine(
                    rewardRepository.getAllActive(userId),
                    _sortOption,
                ) { rewards, sort ->
                    val timeBucket = com.tofustash.app.domain.calculation.getTimeBucket()
                    val previousTimeBucket = timeBucket - 1
                    val rewardsWithPrices = rewards.map { reward ->
                        val purchases = tradeRepository.getTradesForRewardInPeriod(userId, reward.id, 60)
                        val price = RewardPriceCalculator.calculatePrice(reward, rewards, purchases, timeBucket)
                        val prevPrice = RewardPriceCalculator.calculatePrice(reward, rewards, purchases, previousTimeBucket)
                        RewardWithPrice(reward, price, prevPrice)
                    }
                    val balance = tradeRepository.getBalance(userId)
                    val sorted = sortRewards(rewardsWithPrices, sort)
                    RewardsUiState(sorted, balance, sort, isLoading = false)
                }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), RewardsUiState())

    fun setSortOption(option: SortOption) {
        _sortOption.value = option
    }

    fun openCreateForm() {
        formState = RewardFormState()
    }

    fun openEditForm(reward: RewardEntity) {
        formState = RewardFormState(
            editingReward = reward,
            name = reward.name,
            description = reward.description,
            frequency = reward.maxDailyFrequency?.let { HabitsViewModel.formatFrequency(it) } ?: "",
            frequencyPeriod = FrequencyPeriod.DAY,
        )
    }

    fun closeForm() {
        formState = null
    }

    fun saveReward(
        name: String,
        description: String,
        maxDailyFrequency: Double?,
    ) {
        val userId = getCurrentUserId() ?: return
        val existing = formState?.editingReward

        viewModelScope.launch {
            if (existing != null) {
                rewardRepository.update(
                    existing.copy(
                        name = name,
                        description = description,
                        maxDailyFrequency = maxDailyFrequency,
                    ),
                )
            } else {
                rewardRepository.create(
                    userId = userId,
                    name = name,
                    description = description,
                    maxDailyFrequency = maxDailyFrequency,
                )
            }
            formState = null
        }
    }

    fun deleteReward(id: String) {
        viewModelScope.launch {
            rewardRepository.softDelete(id)
            formState = null
        }
    }

    fun purchaseReward(rewardWithPrice: RewardWithPrice) {
        val userId = getCurrentUserId() ?: return
        viewModelScope.launch {
            tradeRepository.createRewardTrade(userId, rewardWithPrice.reward.id, rewardWithPrice.price)
        }
    }

    fun updateDamageRank(rewardId: String, rank: String) {
        viewModelScope.launch {
            val reward = rewardRepository.getById(rewardId) ?: return@launch
            rewardRepository.update(reward.copy(damageRank = rank))
        }
    }

    private fun getCurrentUserId(): String? {
        val state = authRepository.authState.value
        return (state as? AuthState.Authenticated)?.userId
    }

    companion object {
        fun sortRewards(rewards: List<RewardWithPrice>, option: SortOption): List<RewardWithPrice> =
            when (option) {
                SortOption.PRICE_DESC -> rewards.sortedByDescending { it.price }
                SortOption.PRICE_ASC -> rewards.sortedBy { it.price }
                SortOption.DIFFICULTY_DESC -> rewards.sortedByDescending { it.reward.damageRank ?: "" }
                SortOption.DIFFICULTY_ASC -> rewards.sortedBy { it.reward.damageRank ?: "" }
                SortOption.FREQUENCY_DESC -> rewards.sortedByDescending { it.reward.maxDailyFrequency ?: 0.0 }
                SortOption.FREQUENCY_ASC -> rewards.sortedBy { it.reward.maxDailyFrequency ?: 0.0 }
                SortOption.NEWEST -> rewards.sortedByDescending { it.reward.createdAt }
                SortOption.OLDEST -> rewards.sortedBy { it.reward.createdAt }
            }
    }
}
