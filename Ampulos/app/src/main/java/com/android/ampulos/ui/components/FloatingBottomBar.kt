package com.android.ampulos.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun FloatingBottomBar(
    currentRoute: String,
    onNavigate: (String) -> Unit,
    barSize: String = "中"
) {
    val haptic = LocalHapticFeedback.current

    // 根据尺寸调整参数
    val horizontalPadding = when (barSize) {
        "大" -> 16.dp
        "小" -> 32.dp
        else -> 24.dp
    }
    val barHeight = when (barSize) {
        "大" -> 52.dp
        "小" -> 36.dp
        else -> 44.dp
    }
    val iconSize = when (barSize) {
        "大" -> 26.dp
        "小" -> 18.dp
        else -> 22.dp
    }
    val itemWidthSelected = when (barSize) {
        "大" -> 110.dp
        "小" -> 80.dp
        else -> 100.dp
    }
    val itemWidthNormal = when (barSize) {
        "大" -> 56.dp
        "小" -> 40.dp
        else -> 48.dp
    }
    val fontSize = when (barSize) {
        "大" -> 15.sp
        "小" -> 11.sp
        else -> 13.sp
    }
    val cornerRadius = when (barSize) {
        "大" -> 26.dp
        "小" -> 14.dp
        else -> 20.dp
    }

    Box(
        modifier = Modifier
            .padding(start = horizontalPadding, end = horizontalPadding, bottom = 20.dp),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .shadow(
                    elevation = 12.dp,
                    shape = RoundedCornerShape(cornerRadius + 4.dp),
                    ambientColor = MaterialTheme.colorScheme.outlineVariant,
                    spotColor = MaterialTheme.colorScheme.outlineVariant
                )
                .clip(RoundedCornerShape(cornerRadius))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = 8.dp, vertical = 6.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FloatingNavItem(
                    icon = Icons.Default.Home,
                    label = "Draw",
                    selected = currentRoute == "draw",
                    itemHeight = barHeight,
                    iconSize = iconSize,
                    selectedWidth = itemWidthSelected,
                    normalWidth = itemWidthNormal,
                    fontSize = fontSize,
                    itemRadius = cornerRadius - 4.dp,
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onNavigate("draw")
                    }
                )
                FloatingNavItem(
                    icon = Icons.Default.Person,
                    label = "Profile",
                    selected = currentRoute == "profile",
                    itemHeight = barHeight,
                    iconSize = iconSize,
                    selectedWidth = itemWidthSelected,
                    normalWidth = itemWidthNormal,
                    fontSize = fontSize,
                    itemRadius = cornerRadius - 4.dp,
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onNavigate("profile")
                    }
                )
            }
        }
    }
}

@Composable
private fun FloatingNavItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    itemHeight: androidx.compose.ui.unit.Dp = 44.dp,
    iconSize: androidx.compose.ui.unit.Dp = 22.dp,
    selectedWidth: androidx.compose.ui.unit.Dp = 100.dp,
    normalWidth: androidx.compose.ui.unit.Dp = 48.dp,
    fontSize: androidx.compose.ui.unit.TextUnit = 13.sp,
    itemRadius: androidx.compose.ui.unit.Dp = 16.dp,
    onClick: () -> Unit
) {
    val iconColor by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "navIconColor"
    )
    val textColor by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "navTextColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "navBgColor"
    )
    val itemWidth by animateDpAsState(
        targetValue = if (selected) selectedWidth else normalWidth,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium
        ),
        label = "navItemWidth"
    )

    Box(
        modifier = Modifier
            .height(itemHeight)
            .width(itemWidth)
            .clip(RoundedCornerShape(itemRadius))
            .background(bgColor)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(iconSize),
                tint = iconColor
            )
            if (selected) {
                Text(
                    text = label,
                    color = textColor,
                    fontSize = fontSize,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}
