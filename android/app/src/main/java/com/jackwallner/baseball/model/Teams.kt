package com.jackwallner.baseball.model

val teamAliases = mapOf(
    "ARIZONA DIAMONDBACKS" to "ARI",
    "AZ" to "ARI",
    "ATLANTA BRAVES" to "ATL",
    "BALTIMORE ORIOLES" to "BAL",
    "BOSTON RED SOX" to "BOS",
    "CHICAGO CUBS" to "CHC",
    "CHICAGO WHITE SOX" to "CWS",
    "CHW" to "CWS",
    "CINCINNATI REDS" to "CIN",
    "CLEVELAND GUARDIANS" to "CLE",
    "CLEVELAND INDIANS" to "CLE",
    "COLORADO ROCKIES" to "COL",
    "DETROIT TIGERS" to "DET",
    "HOUSTON ASTROS" to "HOU",
    "KANSAS CITY ROYALS" to "KC",
    "KCR" to "KC",
    "LOS ANGELES ANGELS" to "LAA",
    "ANAHEIM ANGELS" to "LAA",
    "LOS ANGELES DODGERS" to "LAD",
    "MIAMI MARLINS" to "MIA",
    "MILWAUKEE BREWERS" to "MIL",
    "MINNESOTA TWINS" to "MIN",
    "NEW YORK METS" to "NYM",
    "NEW YORK YANKEES" to "NYY",
    "ATHLETICS" to "OAK",
    "OAKLAND ATHLETICS" to "OAK",
    "SACRAMENTO ATHLETICS" to "OAK",
    "ATH" to "OAK",
    "PHILADELPHIA PHILLIES" to "PHI",
    "PITTSBURGH PIRATES" to "PIT",
    "SAN DIEGO PADRES" to "SD",
    "SDP" to "SD",
    "SEATTLE MARINERS" to "SEA",
    "SAN FRANCISCO GIANTS" to "SF",
    "SFG" to "SF",
    "ST. LOUIS CARDINALS" to "STL",
    "ST LOUIS CARDINALS" to "STL",
    "TAMPA BAY RAYS" to "TB",
    "TBR" to "TB",
    "TEXAS RANGERS" to "TEX",
    "TORONTO BLUE JAYS" to "TOR",
    "WASHINGTON NATIONALS" to "WSH",
    "WSN" to "WSH"
)
val teamCities = mapOf(
    "ARI" to "Arizona",
    "ATL" to "Atlanta",
    "BAL" to "Baltimore",
    "BOS" to "Boston",
    "CHC" to "Chicago (NL)",
    "CWS" to "Chicago (AL)",
    "CIN" to "Cincinnati",
    "CLE" to "Cleveland",
    "COL" to "Colorado",
    "DET" to "Detroit",
    "HOU" to "Houston",
    "KC" to "Kansas City",
    "LAA" to "Los Angeles (AL)",
    "LAD" to "Los Angeles (NL)",
    "MIA" to "Miami",
    "MIL" to "Milwaukee",
    "MIN" to "Minnesota",
    "NYM" to "New York (NL)",
    "NYY" to "New York (AL)",
    "OAK" to "Athletics",
    "PHI" to "Philadelphia",
    "PIT" to "Pittsburgh",
    "SD" to "San Diego",
    "SEA" to "Seattle",
    "SF" to "San Francisco",
    "STL" to "St. Louis",
    "TB" to "Tampa Bay",
    "TEX" to "Texas",
    "TOR" to "Toronto",
    "WSH" to "Washington"
)
val teamNicknames = mapOf(
    "ARI" to "Diamondbacks",
    "ATL" to "Braves",
    "BAL" to "Orioles",
    "BOS" to "Red Sox",
    "CHC" to "Cubs",
    "CWS" to "White Sox",
    "CIN" to "Reds",
    "CLE" to "Guardians",
    "COL" to "Rockies",
    "DET" to "Tigers",
    "HOU" to "Astros",
    "KC" to "Royals",
    "LAA" to "Angels",
    "LAD" to "Dodgers",
    "MIA" to "Marlins",
    "MIL" to "Brewers",
    "MIN" to "Twins",
    "NYM" to "Mets",
    "NYY" to "Yankees",
    "OAK" to "Athletics",
    "PHI" to "Phillies",
    "PIT" to "Pirates",
    "SD" to "Padres",
    "SEA" to "Mariners",
    "SF" to "Giants",
    "STL" to "Cardinals",
    "TB" to "Rays",
    "TEX" to "Rangers",
    "TOR" to "Blue Jays",
    "WSH" to "Nationals"
)

fun normalizedTeamAbbreviation(team: String) = team.trim().uppercase().let { teamAliases[it] ?: it }
fun teamFullName(team: String) = teamCities[normalizedTeamAbbreviation(team)] ?: team
fun teamDisplayName(team: String): String {
    val abbr = normalizedTeamAbbreviation(team)
    val city = teamFullName(abbr).replace(" (AL)", "").replace(" (NL)", "")
    val nickname = teamNicknames[abbr] ?: return city
    return if (nickname == city) city else "$city $nickname"
}
fun teamMatchesQuery(team: String, query: String): Boolean {
    val abbr = normalizedTeamAbbreviation(team)
    return (listOf(abbr, teamFullName(abbr), teamDisplayName(abbr)) + teamAliases.filterValues { it == abbr }.keys).any { it.contains(query, true) }
}
fun gameLogTeamCodes(team: String): List<String> {
    val abbr = normalizedTeamAbbreviation(team)
    return (listOf(abbr) + teamAliases.filter { it.value == abbr && it.key.length <= 3 }.keys.sorted()).distinct()
}
