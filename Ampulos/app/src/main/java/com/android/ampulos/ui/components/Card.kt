package com.android.ampulos.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun GameCard(
    modifier: Modifier = Modifier,
    cardColor: Color = Color.White,
    elevation: Float = 4f,
    width: Dp = 120.dp,
    height: Dp = 168.dp
) {
    Box(
        modifier = modifier
            .size(width = width, height = height)
            .shadow(elevation.dp, RoundedCornerShape(12.dp))
            .clip(RoundedCornerShape(12.dp))
            .background(cardColor)
            .border(1.dp, Color.LightGray, RoundedCornerShape(12.dp))
    )
}
