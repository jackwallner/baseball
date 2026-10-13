package com.jackwallner.baseball.model

import java.io.InputStream
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.DecodeSequenceMode
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeToSequence

/** Decode one season row at a time, keeping the JSON tree off the phone's heap. */
@OptIn(ExperimentalSerializationApi::class)
fun decodeHistoricalPlayers(input: InputStream): List<Player> =
    Json.decodeToSequence<JsonObject>(input, DecodeSequenceMode.ARRAY_WRAPPED)
        .mapNotNull { row -> runCatching { Player.fromJson(row) }.getOrNull() }
        .toList()
