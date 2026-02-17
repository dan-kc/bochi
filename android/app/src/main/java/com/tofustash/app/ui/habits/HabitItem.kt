package com.tofustash.app.ui.habits

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun HabitItem(
    habitWithPrice: HabitWithPrice,
    onClick: () -> Unit,
    onComplete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val habit = habitWithPrice.habit
    val (trendText, trendDir) = HabitsViewModel.formatTrend(habitWithPrice.price, habitWithPrice.previousPrice)

    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = habit.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                if (habit.description.isNotEmpty()) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = habit.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (habit.minDailyFrequency != null && habit.minDailyFrequency > 0) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "${HabitsViewModel.formatFrequency(habit.minDailyFrequency)}/day",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        maxLines = 1,
                    )
                }
            }

            Column(horizontalAlignment = Alignment.End) {
                val trendColor = when (trendDir) {
                    TrendDirection.UP -> MaterialTheme.colorScheme.primary
                    TrendDirection.DOWN -> MaterialTheme.colorScheme.error
                    TrendDirection.NEUTRAL -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                Text(
                    text = trendText,
                    style = MaterialTheme.typography.bodySmall,
                    color = trendColor,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "${habitWithPrice.price} T",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}
