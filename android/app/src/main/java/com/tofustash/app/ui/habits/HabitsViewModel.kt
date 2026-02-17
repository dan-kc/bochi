package com.tofustash.app.ui.habits

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.tofustash.app.data.local.entity.HabitEntity
import com.tofustash.app.data.repository.AuthRepository
import com.tofustash.app.data.repository.AuthState
import com.tofustash.app.data.repository.HabitRepository
import com.tofustash.app.data.repository.TradeRepository
import com.tofustash.app.domain.calculation.HabitRewardCalculator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class SortOption(val label: String) {
    PRICE_DESC("Price: High to Low"),
    PRICE_ASC("Price: Low to High"),
    DIFFICULTY_DESC("Difficulty: Hardest First"),
    DIFFICULTY_ASC("Difficulty: Easiest First"),
    FREQUENCY_DESC("Frequency: Highest First"),
    FREQUENCY_ASC("Frequency: Lowest First"),
    NEWEST("Newest First"),
    OLDEST("Oldest First"),
}

data class HabitWithPrice(
    val habit: HabitEntity,
    val price: Int,
    val previousPrice: Int,
)

data class HabitsUiState(
    val habits: List<HabitWithPrice> = emptyList(),
    val balance: Int = 0,
    val sortOption: SortOption = SortOption.PRICE_DESC,
    val isLoading: Boolean = true,
)

@HiltViewModel
class HabitsViewModel @Inject constructor(
    private val habitRepository: HabitRepository,
    private val tradeRepository: TradeRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _sortOption = MutableStateFlow(SortOption.PRICE_DESC)
    val sortOption: StateFlow<SortOption> = _sortOption.asStateFlow()

    var formState by mutableStateOf<HabitFormState?>(null)
        private set

    val uiState: StateFlow<HabitsUiState> = authRepository.authState
        .flatMapLatest { authState ->
            val userId = (authState as? AuthState.Authenticated)?.userId
            if (userId == null) {
                flowOf(HabitsUiState(isLoading = false))
            } else {
                combine(
                    habitRepository.getAllActive(userId),
                    _sortOption,
                ) { habits, sort ->
                    val timeBucket = HabitRewardCalculator.getTimeBucket()
                    val previousTimeBucket = timeBucket - 1
                    val habitsWithPrices = habits.map { habit ->
                        val completions = tradeRepository.getTradesForHabitInPeriod(userId, habit.id, 7)
                        val price = HabitRewardCalculator.calculateReward(habit, habits, completions, timeBucket)
                        val prevPrice = HabitRewardCalculator.calculateReward(habit, habits, completions, previousTimeBucket)
                        HabitWithPrice(habit, price, prevPrice)
                    }
                    val balance = tradeRepository.getBalance(userId)
                    val sorted = sortHabits(habitsWithPrices, sort)
                    HabitsUiState(sorted, balance, sort, isLoading = false)
                }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), HabitsUiState())

    fun setSortOption(option: SortOption) {
        _sortOption.value = option
    }

    fun openCreateForm() {
        formState = HabitFormState()
    }

    fun openEditForm(habit: HabitEntity) {
        formState = HabitFormState(
            editingHabit = habit,
            name = habit.name,
            description = habit.description,
            frequency = habit.minDailyFrequency?.let { formatFrequency(it) } ?: "",
            frequencyPeriod = FrequencyPeriod.DAY,
        )
    }

    fun closeForm() {
        formState = null
    }

    fun saveHabit(
        name: String,
        description: String,
        minDailyFrequency: Double?,
    ) {
        val userId = getCurrentUserId() ?: return
        val existing = formState?.editingHabit

        viewModelScope.launch {
            if (existing != null) {
                habitRepository.update(
                    existing.copy(
                        name = name,
                        description = description,
                        minDailyFrequency = minDailyFrequency,
                    ),
                )
            } else {
                habitRepository.create(
                    userId = userId,
                    name = name,
                    description = description,
                    minDailyFrequency = minDailyFrequency,
                )
            }
            formState = null
        }
    }

    fun deleteHabit(id: String) {
        viewModelScope.launch {
            habitRepository.softDelete(id)
            formState = null
        }
    }

    fun completeHabit(habitWithPrice: HabitWithPrice) {
        val userId = getCurrentUserId() ?: return
        viewModelScope.launch {
            tradeRepository.createHabitTrade(userId, habitWithPrice.habit.id, habitWithPrice.price)
        }
    }

    fun updateDifficultyRank(habitId: String, rank: String) {
        viewModelScope.launch {
            val habit = habitRepository.getById(habitId) ?: return@launch
            habitRepository.update(habit.copy(difficultyRank = rank))
        }
    }

    private fun getCurrentUserId(): String? {
        val state = authRepository.authState.value
        return (state as? AuthState.Authenticated)?.userId
    }

    companion object {
        fun sortHabits(habits: List<HabitWithPrice>, option: SortOption): List<HabitWithPrice> =
            when (option) {
                SortOption.PRICE_DESC -> habits.sortedByDescending { it.price }
                SortOption.PRICE_ASC -> habits.sortedBy { it.price }
                SortOption.DIFFICULTY_DESC -> habits.sortedByDescending { it.habit.difficultyRank ?: "" }
                SortOption.DIFFICULTY_ASC -> habits.sortedBy { it.habit.difficultyRank ?: "" }
                SortOption.FREQUENCY_DESC -> habits.sortedByDescending { it.habit.minDailyFrequency ?: 0.0 }
                SortOption.FREQUENCY_ASC -> habits.sortedBy { it.habit.minDailyFrequency ?: 0.0 }
                SortOption.NEWEST -> habits.sortedByDescending { it.habit.createdAt }
                SortOption.OLDEST -> habits.sortedBy { it.habit.createdAt }
            }

        fun formatFrequency(dailyFrequency: Double): String {
            val formatted = dailyFrequency.toBigDecimal().stripTrailingZeros().toPlainString()
            return formatted
        }

        fun formatTrend(current: Int, previous: Int): Pair<String, TrendDirection> {
            if (previous == 0 || current == previous) return Pair("0%", TrendDirection.NEUTRAL)
            val change = ((current - previous).toDouble() / previous) * 100
            val formatted = if (kotlin.math.abs(change) >= 10) {
                "${change.toInt()}%"
            } else {
                val s = "%.1f".format(change)
                if (s.endsWith(".0")) "${s.dropLast(2)}%" else "$s%"
            }
            val prefix = if (change > 0) "+" else ""
            val direction = when {
                change > 0 -> TrendDirection.UP
                change < 0 -> TrendDirection.DOWN
                else -> TrendDirection.NEUTRAL
            }
            return Pair("$prefix$formatted", direction)
        }
    }
}

enum class TrendDirection { UP, DOWN, NEUTRAL }

enum class FrequencyPeriod(val label: String, val divisor: Double) {
    DAY("Day", 1.0),
    WEEK("Week", 7.0),
    MONTH("Month", 30.0),
}

data class HabitFormState(
    val editingHabit: HabitEntity? = null,
    val name: String = "",
    val description: String = "",
    val frequency: String = "",
    val frequencyPeriod: FrequencyPeriod = FrequencyPeriod.DAY,
) {
    val isEditing: Boolean get() = editingHabit != null
}
