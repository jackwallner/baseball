package com.jackwallner.baseball.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import com.jackwallner.baseball.R
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.baseball.model.normalizedTeamAbbreviation

private fun rgb(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())

/** The iOS palette and condensed type, adapted to Android touch targets. */
object SavantPalette {
    val canvas = rgb(0.94, 0.94, 0.95)
    val surface = Color.White
    val surfaceAlt = rgb(0.96, 0.96, 0.97)
    val surfaceSunk = rgb(0.91, 0.91, 0.92)
    val hairline = rgb(0.78, 0.78, 0.80)
    val divider = rgb(0.85, 0.85, 0.87)
    val ink = rgb(0.10, 0.10, 0.11)
    val inkSecondary = rgb(0.25, 0.25, 0.28)
    val inkTertiary = rgb(0.40, 0.40, 0.43)
    val inkOnDark = Color.White
    val midnight = rgb(0.06, 0.13, 0.32)
    val turf = rgb(0.78, 0.10, 0.13)
    val leather = rgb(0.06, 0.13, 0.32)
    val gold = rgb(0.84, 0.63, 0.19)
    val linkBlue = rgb(0.00, 0.36, 0.69)
    val performanceHigh = rgb(0.80, 0.15, 0.15)
    val performanceMid = rgb(0.75, 0.75, 0.78)
    val performanceLow = rgb(0.15, 0.35, 0.70)

    /** W green, L red, and a tie neither: it used to fall through to green. */
    fun resultColor(result: String?): Color = when (result) {
        "W" -> performanceHigh
        "L" -> performanceLow
        else -> inkSecondary
    }
    val up = rgb(0.16, 0.55, 0.27)
    val down = performanceLow
    val flat = inkTertiary
    val sky = rgb(0.30, 0.55, 0.85)

    private val hot = Triple(0.80, 0.15, 0.15)
    private val mid = Triple(0.75, 0.75, 0.78)
    private val cold = Triple(0.15, 0.35, 0.70)
    private val hotText = Triple(0.72, 0.09, 0.12)
    private val midText = Triple(0.28, 0.28, 0.32)
    private val coldText = Triple(0.10, 0.28, 0.62)

    fun color(percentile: Int): Color {
        val t = (percentile / 100.0).coerceIn(0.0, 1.0)
        return if (t < 0.5) lerp(cold, mid, t * 2) else lerp(mid, hot, (t - 0.5) * 2)
    }

    /** Percentile colour for type on a light surface: the middle is pulled dark so every value clears contrast. */
    fun textColor(percentile: Int): Color {
        val t = (percentile / 100.0).coerceIn(0.0, 1.0)
        return if (t < 0.5) lerp(coldText, midText, t * 2) else lerp(midText, hotText, (t - 0.5) * 2)
    }

    private fun lerp(a: Triple<Double, Double, Double>, b: Triple<Double, Double, Double>, t: Double) =
        rgb(a.first + (b.first - a.first) * t, a.second + (b.second - a.second) * t, a.third + (b.third - a.third) * t)
}

/**
 * iOS semantic styles at their default Dynamic Type sizes, in the platform
 * face. Values use tabular digits so columns line up.
 */
object SavantType {
    private val face = FontFamily(Font(R.font.roboto_condensed_regular), Font(R.font.roboto_condensed_medium, FontWeight.Medium), Font(R.font.roboto_condensed_bold, FontWeight.Bold), Font(R.font.roboto_condensed_black, FontWeight.Black))
    private const val TABULAR = "tnum"

    val playerName = TextStyle(fontFamily = face, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold)
    val pageTitle = TextStyle(fontFamily = face, fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold)
    val sectionTitle = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold)
    val cardTitle = TextStyle(fontFamily = face, fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp)
    val bodyBold = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
    val small = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp)
    val smallBold = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold)
    val micro = TextStyle(fontFamily = face, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.SemiBold)

    val statHero = TextStyle(fontFamily = face, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR)
    val statLarge = TextStyle(fontFamily = face, fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR)
    val statMed = TextStyle(fontFamily = face, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TABULAR)
    val statSmall = TextStyle(fontFamily = face, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = TABULAR)
}

object SavantGeo {
    val radiusCard = 4.dp
    val radiusBadge = 2.dp
    val hairline = 0.5.dp
    val barTrack = 4.dp
    val barMarker = 12.dp
    val padInline = 12.dp
    val padCard = 16.dp
    val padPage = 16.dp
    val padSection = 24.dp
    val rowHeight = 44.dp
    val rowHeightHeader = 28.dp
    val controlRowGap = 10.dp
    /** Android's minimum touch target. */
    val touchTarget = 48.dp
}

/** Baseball club colours from the iOS design system. */
object MLBTeamColor {
    private val primary = mapOf(
        "ARI" to rgb(0.65, 0.10, 0.20),
        "ATL" to rgb(0.79, 0.10, 0.18),
        "BAL" to rgb(0.87, 0.30, 0.07),
        "BOS" to rgb(0.74, 0.13, 0.18),
        "CHC" to rgb(0.04, 0.22, 0.46),
        "CWS" to rgb(0.10, 0.10, 0.10),
        "CIN" to rgb(0.78, 0.07, 0.13),
        "CLE" to rgb(0.04, 0.22, 0.42),
        "COL" to rgb(0.20, 0.16, 0.42),
        "DET" to rgb(0.05, 0.25, 0.45),
        "HOU" to rgb(0.92, 0.34, 0.13),
        "KC" to rgb(0.00, 0.27, 0.51),
        "LAA" to rgb(0.74, 0.13, 0.18),
        "LAD" to rgb(0.00, 0.30, 0.55),
        "MIA" to rgb(0.00, 0.65, 0.83),
        "MIL" to rgb(0.07, 0.20, 0.36),
        "MIN" to rgb(0.00, 0.27, 0.51),
        "NYM" to rgb(0.00, 0.27, 0.55),
        "NYY" to rgb(0.00, 0.18, 0.40),
        "OAK" to rgb(0.00, 0.32, 0.27),
        "PHI" to rgb(0.90, 0.16, 0.20),
        "PIT" to rgb(0.99, 0.78, 0.13),
        "SD" to rgb(0.18, 0.10, 0.07),
        "SEA" to rgb(0.00, 0.36, 0.46),
        "SF" to rgb(0.99, 0.36, 0.07),
        "STL" to rgb(0.78, 0.13, 0.20),
        "TB" to rgb(0.00, 0.21, 0.40),
        "TEX" to rgb(0.00, 0.20, 0.50),
        "TOR" to rgb(0.07, 0.30, 0.65),
        "WSH" to rgb(0.67, 0.10, 0.18)
    )

    fun color(abbr: String): Color = primary[normalizedTeamAbbreviation(abbr)] ?: SavantPalette.inkTertiary
}

@Composable
fun StatScoutTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = SavantPalette.turf,
            onPrimary = Color.White,
            background = SavantPalette.canvas,
            surface = SavantPalette.surface,
            onSurface = SavantPalette.ink,
            onBackground = SavantPalette.ink,
            surfaceVariant = SavantPalette.surfaceAlt,
            outline = SavantPalette.hairline,
            secondary = SavantPalette.turf,
            secondaryContainer = SavantPalette.surfaceAlt,
            onSecondaryContainer = SavantPalette.ink,
            primaryContainer = SavantPalette.surfaceAlt,
            onPrimaryContainer = SavantPalette.ink,
            surfaceTint = SavantPalette.surface,
        ),
        content = content,
    )
}
