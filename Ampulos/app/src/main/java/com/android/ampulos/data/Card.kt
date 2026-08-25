package com.android.ampulos.data

import java.io.Serializable

data class Card(
    val id: String,
    val name: String,
    val type: String = "Normal",
    val attack: Int = 0,
    val defense: Int = 0,
    val description: String = "",
    val imageRes: Int = 0
) : Serializable