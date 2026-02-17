package com.tofustash.app.ui.rewards

import androidx.compose.foundation.BorderStroke
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
import com.tofustash.app.ui.habits.HabitsViewModel
import com.tofustash.app.ui.habits.TrendDirection

@Composable
fun RewardItem(
    rewardWithPrice: RewardWithPrice,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reward = rewardWithPrice.reward
    val (trendText, trendDir) = HabitsViewModel.formatTrend(rewardWithPrice.price, rewardWithPrice.previousPrice)

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
                    text = reward.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                if (reward.description.isNotEmpty()) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = reward.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (reward.maxDailyFrequency != null && reward.maxDailyFrequency > 0) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "${HabitsViewModel.formatFrequency(reward.maxDailyFrequency)}/day max",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        maxLines = 1,
                    )
                }
            }

            Column(horizontalAlignment = Alignment.End) {
                val trendColor = when (trendDir) {
                    TrendDirection.UP -> MaterialTheme.colorScheme.error // price up = bad for buyer
                    TrendDirection.DOWN -> MaterialTheme.colorScheme.primary // price down = good for buyer
                    TrendDirection.NEUTRAL -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                Text(
                    text = trendText,
                    style = MaterialTheme.typography.bodySmall,
                    color = trendColor,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "${rewardWithPrice.price} T",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}
