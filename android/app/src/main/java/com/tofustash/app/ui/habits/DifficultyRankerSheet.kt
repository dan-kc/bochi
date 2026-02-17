package com.tofustash.app.ui.habits

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tofustash.app.data.local.entity.HabitEntity
import com.tofustash.app.domain.calculation.generateKeyBetween
import kotlin.math.ceil
import kotlin.math.ln

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DifficultyRankerSheet(
    habit: HabitEntity,
    rankedHabits: List<HabitEntity>,
    onComplete: (rank: String) -> Unit,
    onSkip: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Binary search state
    var low by remember { mutableIntStateOf(0) }
    var high by remember { mutableIntStateOf(rankedHabits.size) }
    var comparisonCount by remember { mutableIntStateOf(0) }
    var isComplete by remember { mutableStateOf(false) }

    // Handle no existing ranked habits
    LaunchedEffect(rankedHabits.size) {
        if (rankedHabits.isEmpty()) {
            onComplete(generateKeyBetween(null, null))
        }
    }

    // Check if binary search is done
    LaunchedEffect(low, high) {
        if (low >= high && rankedHabits.isNotEmpty() && !isComplete) {
            isComplete = true
            val harderHabit = rankedHabits.getOrNull(low - 1)
            val easierHabit = rankedHabits.getOrNull(low)
            val newRank = generateKeyBetween(
                easierHabit?.difficultyRank,
                harderHabit?.difficultyRank,
            )
            onComplete(newRank)
        }
    }

    val mid = (low + high) / 2
    val comparisonHabit = rankedHabits.getOrNull(mid)

    ModalBottomSheet(
        onDismissRequest = onSkip,
        sheetState = sheetState,
    ) {
        if (isComplete) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Done!",
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Difficulty ranking set after $comparisonCount comparison${if (comparisonCount != 1) "s" else ""}.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else if (comparisonHabit != null) {
            val totalComparisons = ceil(ln((rankedHabits.size + 1).toDouble()) / ln(2.0)).toInt()

            Column(
                modifier = Modifier
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 32.dp),
            ) {
                Text(
                    text = "Set Difficulty",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "~${totalComparisons - comparisonCount} comparison${if (totalComparisons - comparisonCount != 1) "s" else ""} remaining",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                Spacer(Modifier.height(24.dp))

                // New habit card
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            text = "New Habit",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        Text(
                            text = habit.name,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        if (habit.description.isNotEmpty()) {
                            Text(
                                text = habit.description,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))

                Text(
                    text = "Is this habit harder or easier than:",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                Spacer(Modifier.height(16.dp))

                // Comparison habit card
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            text = "Compare with",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = comparisonHabit.name,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        if (comparisonHabit.description.isNotEmpty()) {
                            Text(
                                text = comparisonHabit.description,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))

                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = {
                            high = mid
                            comparisonCount++
                        },
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                        ),
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Harder", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "More difficult to complete",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }

                    Button(
                        onClick = {
                            low = mid + 1
                            comparisonCount++
                        },
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                        ),
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Easier", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "Less difficult to complete",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    OutlinedButton(
                        onClick = onSkip,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Skip for now")
                    }
                }
            }
        }
    }
}
