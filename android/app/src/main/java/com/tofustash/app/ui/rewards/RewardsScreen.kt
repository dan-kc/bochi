package com.tofustash.app.ui.rewards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tofustash.app.ui.habits.SortOption

@Composable
fun RewardsScreen(
    viewModel: RewardsViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    var showRanker by remember { mutableStateOf<String?>(null) }

    Box(modifier = modifier.fillMaxSize()) {
        Column {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Rewards",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )

                Surface(
                    color = MaterialTheme.colorScheme.tertiaryContainer,
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Text(
                        text = "${uiState.balance} tofu",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onTertiaryContainer,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }

            // Sort dropdown
            SortRow(
                selectedOption = uiState.sortOption,
                onOptionSelected = viewModel::setSortOption,
            )

            if (uiState.rewards.isEmpty() && !uiState.isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No rewards yet.\nAdd your first reward to get started.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(uiState.rewards, key = { it.reward.id }) { rewardWithPrice ->
                        RewardItem(
                            rewardWithPrice = rewardWithPrice,
                            onClick = { viewModel.openEditForm(rewardWithPrice.reward) },
                        )
                    }
                    item { Spacer(Modifier.height(80.dp)) }
                }
            }
        }

        FloatingActionButton(
            onClick = viewModel::openCreateForm,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
        ) {
            Icon(Icons.Default.Add, contentDescription = "Add reward")
        }
    }

    val formState = viewModel.formState
    if (formState != null) {
        RewardFormSheet(
            formState = formState,
            onSave = viewModel::saveReward,
            onDelete = if (formState.isEditing) viewModel::deleteReward else null,
            onRankDamage = if (formState.isEditing && uiState.rewards.size > 1) {
                { id -> showRanker = id }
            } else {
                null
            },
            onDismiss = viewModel::closeForm,
        )
    }

    val rankingRewardId = showRanker
    if (rankingRewardId != null) {
        val reward = uiState.rewards.find { it.reward.id == rankingRewardId }?.reward
        if (reward != null) {
            val rankedRewards = uiState.rewards
                .map { it.reward }
                .filter { it.damageRank != null && it.id != reward.id }
                .sortedByDescending { it.damageRank }

            DamageRankerSheet(
                reward = reward,
                rankedRewards = rankedRewards,
                onComplete = { rank ->
                    viewModel.updateDamageRank(rankingRewardId, rank)
                    showRanker = null
                },
                onSkip = { showRanker = null },
            )
        }
    }
}

@Composable
private fun SortRow(
    selectedOption: SortOption,
    onOptionSelected: (SortOption) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.End,
    ) {
        Box {
            TextButton(onClick = { expanded = true }) {
                Text(selectedOption.label, style = MaterialTheme.typography.bodySmall)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                SortOption.entries.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.label) },
                        onClick = {
                            onOptionSelected(option)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
