package com.android.ampulos.navigation

sealed class Screen(val route: String) {
    object Splash : Screen("splash")
    object Draw : Screen("draw")
    object Profile : Screen("profile")
    object DeckConfig : Screen("deck_config")
}