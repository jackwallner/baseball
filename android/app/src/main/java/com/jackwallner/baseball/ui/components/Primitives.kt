package com.jackwallner.baseball.ui.components

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.jackwallner.baseball.model.*
import com.jackwallner.baseball.ui.LocalGraph
import com.jackwallner.baseball.ui.nav.LocalNavigator
import com.jackwallner.baseball.ui.nav.Route
import com.jackwallner.baseball.ui.theme.*

@Composable
fun SfIcon(name: String, size: Dp, tint: Color, modifier: Modifier = Modifier, contentDescription: String? = null) = Icon(sf(name), contentDescription, modifier.size(size), tint)
@Composable
fun SfIcon(icon: ImageVector, size: Dp, tint: Color, modifier: Modifier = Modifier) = Icon(icon, null, modifier.size(size), tint)
@Composable
fun TextAction(title: String, style: TextStyle, color: Color, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    TextButton(onClick, modifier.heightIn(min = 48.dp), enabled = enabled, contentPadding = PaddingValues(horizontal = 8.dp)) { Text(title, style = style, color = color) }
}
fun Modifier.savantCard() = background(SavantPalette.surface, RoundedCornerShape(4.dp)).border(0.5.dp, SavantPalette.hairline, RoundedCornerShape(4.dp))
@Composable
fun SectionBar(title: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().background(SavantPalette.midnight).padding(horizontal = 12.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), style = SavantType.sectionTitle, color = Color.White, modifier = Modifier.weight(1f))
        trailing?.let { Text(it, style = SavantType.micro, color = Color.White.copy(alpha = 0.8f)) }
    }
}
@Composable
fun PlayerIdentity(player: Player, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(MLBTeamColor.color(player.team)), contentAlignment = Alignment.Center) {
            Text(player.initials, style = SavantType.cardTitle, color = Color.White)
        }
        Column(Modifier.weight(1f)) {
            Text(player.name, style = SavantType.bodyBold, color = SavantPalette.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${normalizedTeamAbbreviation(player.team)} · ${player.displayPosition}", style = SavantType.small, color = SavantPalette.inkSecondary)
        }
    }
}
@Composable
fun PlayerRow(player: Player, metric: Metric? = player.headlineMetric, rank: Int? = null) {
    val navigator = LocalNavigator.current
    Row(Modifier.fillMaxWidth().clickable { navigator.push(Route.PlayerProfile(player)) }.background(SavantPalette.surface).heightIn(min = 64.dp).padding(horizontal = 12.dp, vertical = 8.dp).testTag("player-${player.playerId}"), verticalAlignment = Alignment.CenterVertically) {
        rank?.let { Text("$it", style = SavantType.statSmall, color = SavantPalette.inkTertiary, modifier = Modifier.width(28.dp)) }
        PlayerIdentity(player, Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(metric?.value ?: "", style = SavantType.statLarge, color = SavantPalette.ink)
            Text(metric?.let { "${it.percentile.ordinal} PCTL" } ?: "Unranked", style = SavantType.micro, color = metric?.let { SavantPalette.textColor(it.percentile) } ?: SavantPalette.inkTertiary)
        }
    }
    HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
}
@Composable
fun MetricBar(metric: Metric, onClick: (() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 10.dp).semantics { contentDescription = "${metric.label}, ${metric.value}, ${metric.percentile.ordinal} percentile" }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(metric.label, style = SavantType.bodyBold, color = SavantPalette.ink, modifier = Modifier.weight(1f))
            Text(metric.value, style = SavantType.statMed, color = SavantPalette.inkSecondary, modifier = Modifier.padding(end = 16.dp))
            Text("${metric.percentile}", style = SavantType.statMed, color = SavantPalette.textColor(metric.percentile), modifier = Modifier.width(28.dp))
        }
        Spacer(Modifier.height(6.dp))
        Box(Modifier.fillMaxWidth().height(6.dp).background(SavantPalette.surfaceSunk)) {
            Box(Modifier.fillMaxWidth((metric.percentile / 100f).coerceIn(0.01f, 1f)).fillMaxHeight().background(SavantPalette.color(metric.percentile)))
        }
    }
}
@Composable
fun SearchField(value: String, onValue: (String) -> Unit, placeholder: String = "Search players or teams") {
    OutlinedTextField(value, onValue, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp).testTag("search"), singleLine = true, placeholder = { Text(placeholder, style = SavantType.body) }, textStyle = SavantType.body, shape = RoundedCornerShape(4.dp))
}
@Composable
fun <T> ChoiceMenu(label: String, options: List<Pair<T, String>>, onSelect: (T) -> Unit, tag: String = label) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton({ expanded = true }, Modifier.heightIn(min = 48.dp).testTag(tag), shape = RoundedCornerShape(4.dp), contentPadding = PaddingValues(horizontal = 10.dp)) {
            Text(label, style = SavantType.smallBold, maxLines = 1)
            SfIcon("chevron.down", 14.dp, SavantPalette.inkSecondary, Modifier.padding(start = 4.dp))
        }
        DropdownMenu(expanded, { expanded = false }) {
            options.forEach { (value, text) -> DropdownMenuItem(text = { Text(text, style = SavantType.body) }, onClick = { expanded = false; onSelect(value) }) }
        }
    }
}
@Composable
fun EmptyMessage(title: String, detail: String = "", action: String? = null, onAction: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = SavantType.cardTitle, color = SavantPalette.ink)
        if (detail.isNotBlank()) Text(detail, style = SavantType.body, color = SavantPalette.inkSecondary)
        if (action != null) Button(onAction) { Text(action) }
    }
}
@Composable
fun LoadingRow() { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(28.dp)) } }

fun Modifier.topHairline(color: Color = SavantPalette.divider): Modifier = this.border(0.5.dp, color)
