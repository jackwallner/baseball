package com.jackwallner.baseball.model

import kotlinx.serialization.json.*

/** A cache serializer independent of Android and RevenueCat. */
fun encodePlayers(players: List<Player>): String = JsonArray(players.map { p -> buildJsonObject {
    put("id", p.playerId); put("name", p.name); put("team", p.team); put("position", p.position); put("handedness", p.handedness); put("updated_at", p.updatedAt.toString())
    p.season?.let { put("season", it) }; p.playerType?.let { put("player_type", it) }; p.source?.let { put("source", it) }; p.imageUrl?.let { put("image_url", it) }
    put("metrics", JsonArray(p.metrics.map { m -> buildJsonObject { put("id", m.id); put("label", m.label); put("value", m.value); put("percentile", m.percentile); put("category", m.category.raw) } }))
    p.standardStats?.let { stats -> put("standard_stats", JsonArray(stats.map { s -> buildJsonObject { put("id", s.id); put("label", s.label); put("value", s.value); s.category?.let { put("category", it.raw) } } })) }
    put("games", JsonArray(p.games.map { g -> buildJsonObject { put("date", g.date.toString()); put("opponent", g.opponent); put("summary", g.summary); put("percentile_delta", g.percentileDelta) } }))
} }).toString()
