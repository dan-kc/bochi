package com.tofustash.app.ui.habits

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HabitFormSheet(
    formState: HabitFormState,
    onSave: (name: String, description: String, minDailyFrequency: Double?) -> Unit,
    onDelete: ((String) -> Unit)?,
    onRankDifficulty: ((String) -> Unit)?,
    onDismiss: () -> Unit,
) {
    var name by remember(formState) { mutableStateOf(formState.name) }
    var description by remember(formState) { mutableStateOf(formState.description) }
    var frequency by remember(formState) { mutableStateOf(formState.frequency) }
    var period by remember(formState) { mutableStateOf(formState.frequencyPeriod) }
    var nameError by remember { mutableStateOf<String?>(null) }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                text = if (formState.isEditing) "Edit Habit" else "New Habit",
                style = MaterialTheme.typography.headlineSmall,
            )
            Spacer(Modifier.height(24.dp))

            OutlinedTextField(
                value = name,
                onValueChange = {
                    if (it.length <= 100) {
                        name = it
                        nameError = null
                    }
                },
                label = { Text("Name") },
                isError = nameError != null,
                supportingText = nameError?.let { { Text(it) } }
                    ?: { Text("${name.length}/100") },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = description,
                onValueChange = {
                    if (it.length <= 10_000) description = it
                },
                label = { Text("Description") },
                supportingText = { Text("${description.length}/10000") },
                minLines = 2,
                maxLines = 5,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(16.dp))

            Text(
                text = "Target Frequency",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedTextField(
                    value = frequency,
                    onValueChange = { frequency = it },
                    label = { Text("Times") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f),
                )
                FrequencyPeriod.entries.forEach { p ->
                    FilterChip(
                        selected = period == p,
                        onClick = { period = p },
                        label = { Text(p.label) },
                    )
                }
            }
            Spacer(Modifier.height(24.dp))

            // Action buttons
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Cancel")
                }
                Button(
                    onClick = {
                        if (name.isBlank()) {
                            nameError = "Name is required"
                            return@Button
                        }
                        val freq = frequency.toDoubleOrNull()
                        val dailyFreq = freq?.let { it / period.divisor }
                        onSave(name.trim(), description.trim(), dailyFreq)
                    },
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (formState.isEditing) "Save" else "Create")
                }
            }

            if (formState.isEditing) {
                Spacer(Modifier.height(16.dp))

                if (onRankDifficulty != null) {
                    OutlinedButton(
                        onClick = { onRankDifficulty(formState.editingHabit!!.id) },
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.tertiary,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            if (formState.editingHabit?.difficultyRank != null) "Re-rank Difficulty"
                            else "Set Difficulty",
                        )
                    }
                }

                if (onDelete != null) {
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { onDelete(formState.editingHabit!!.id) },
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Delete Habit")
                    }
                }
            }
        }
    }
}
