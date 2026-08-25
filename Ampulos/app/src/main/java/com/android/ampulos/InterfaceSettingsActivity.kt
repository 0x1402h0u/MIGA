package com.android.ampulos

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.BackEventCompat
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.android.ampulos.ui.theme.AmpulosTheme
import com.android.ampulos.ui.theme.LocalUseMiuix
import com.android.ampulos.ui.theme.MiuixAppTheme
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.CancellationException
import top.yukonga.miuix.kmp.basic.DropdownItem
import top.yukonga.miuix.kmp.basic.Scaffold as MiuixScaffold
import top.yukonga.miuix.kmp.basic.SmallTopAppBar
import top.yukonga.miuix.kmp.preference.OverlaySpinnerPreference
import top.yukonga.miuix.kmp.preference.SwitchPreference
import top.yukonga.miuix.kmp.theme.MiuixTheme

class InterfaceSettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        setContent {
            var modernStyleEnabled by remember {
                mutableStateOf(PredictiveBackPreferences.isModernStyleEnabled(this@InterfaceSettingsActivity))
            }
            var miuixModeEnabled by remember {
                mutableStateOf(PredictiveBackPreferences.isMiuixModeEnabled(this@InterfaceSettingsActivity))
            }
            val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
            DisposableEffect(lifecycleOwner) {
                val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                    if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                        modernStyleEnabled = PredictiveBackPreferences.isModernStyleEnabled(this@InterfaceSettingsActivity)
                        miuixModeEnabled = PredictiveBackPreferences.isMiuixModeEnabled(this@InterfaceSettingsActivity)
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
            }
            if (miuixModeEnabled) {
                MiuixAppTheme {
                    InterfaceSettingsContent(
                        onBack = { finish() },
                        onModernStyleChange = {
                            modernStyleEnabled = it
                            PredictiveBackPreferences.setModernStyleEnabled(this@InterfaceSettingsActivity, it)
                        },
                        onMiuixModeChange = {
                            miuixModeEnabled = it
                            PredictiveBackPreferences.setMiuixModeEnabled(this@InterfaceSettingsActivity, it)
                        },
                        useMiuix = true
                    )
                }
            } else {
                AmpulosTheme(useModernStyle = modernStyleEnabled) {
                    InterfaceSettingsContent(
                        onBack = { finish() },
                        onModernStyleChange = {
                            modernStyleEnabled = it
                            PredictiveBackPreferences.setModernStyleEnabled(this@InterfaceSettingsActivity, it)
                        },
                        onMiuixModeChange = {
                            miuixModeEnabled = it
                            PredictiveBackPreferences.setMiuixModeEnabled(this@InterfaceSettingsActivity, it)
                        },
                        useMiuix = false
                    )
                }
            }
        }
    }
}

@Composable
private fun InterfaceSettingsContent(
    onBack: () -> Unit,
    onModernStyleChange: (Boolean) -> Unit = {},
    onMiuixModeChange: (Boolean) -> Unit = {},
    useMiuix: Boolean = false
) {
    val context = LocalContext.current
    var backProgress by remember { mutableFloatStateOf(0f) }
    var isBackGestureActive by remember { mutableStateOf(false) }
    var transparentEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isTransparentEnabled(context))
    }
    var floatingBarEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isFloatingBarEnabled(context))
    }
    var modernStyleEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isModernStyleEnabled(context))
    }
    var miuixModeEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isMiuixModeEnabled(context))
    }

    val predictiveEasing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)
    val backScale by animateFloatAsState(
        targetValue = if (isBackGestureActive) (1f - backProgress * 0.1f) else 1f,
        animationSpec = if (isBackGestureActive) tween(0) else tween(250, easing = predictiveEasing),
        label = "predictiveScale"
    )
    val backTranslationX by animateFloatAsState(
        targetValue = if (isBackGestureActive) backProgress * 120f else 0f,
        animationSpec = if (isBackGestureActive) tween(0) else tween(250, easing = predictiveEasing),
        label = "predictiveTranslationX"
    )
    val backAlpha by animateFloatAsState(
        targetValue = if (isBackGestureActive && transparentEnabled) (1f - backProgress * 0.15f) else 1f,
        animationSpec = if (isBackGestureActive) tween(0) else tween(250, easing = predictiveEasing),
        label = "predictiveAlpha"
    )
    val backCornerRadius by animateFloatAsState(
        targetValue = if (isBackGestureActive) backProgress * 24f else 0f,
        animationSpec = if (isBackGestureActive) tween(0) else tween(250, easing = predictiveEasing),
        label = "predictiveCornerRadius"
    )

    val barSizeOptions = listOf("大", "中", "小")
    val currentBarSizeIndex = barSizeOptions.indexOf(PredictiveBackPreferences.getBarSize(context)).coerceAtLeast(1)

    Box(modifier = Modifier.fillMaxSize()) {
        // 底层：纯色背景
        if (isBackGestureActive) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        if (useMiuix) MiuixTheme.colorScheme.surfaceVariant
                        else MaterialTheme.colorScheme.surfaceVariant
                    )
            )
        }

        // 顶层：当前页面（带缩放动画）
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = backScale
                    scaleY = backScale
                    translationX = backTranslationX
                    alpha = backAlpha
                    shape = RoundedCornerShape(backCornerRadius.dp)
                    clip = true
                }
        ) {
            if (useMiuix) {
                InterfaceSettingsMiuixContent(
                    onBack = onBack,
                    floatingBarEnabled = floatingBarEnabled,
                    onFloatingBarChange = {
                        floatingBarEnabled = it
                        PredictiveBackPreferences.setFloatingBarEnabled(context, it)
                    },
                    modernStyleEnabled = modernStyleEnabled,
                    onModernStyleChange = {
                        modernStyleEnabled = it
                        onModernStyleChange(it)
                    },
                    miuixModeEnabled = miuixModeEnabled,
                    onMiuixModeChange = {
                        miuixModeEnabled = it
                        onMiuixModeChange(it)
                    },
                    barSizeOptions = barSizeOptions,
                    currentBarSizeIndex = currentBarSizeIndex,
                    onBarSizeChange = { index ->
                        PredictiveBackPreferences.setBarSize(context, barSizeOptions[index])
                    }
                )
            } else {
                InterfaceSettingsM3Content(
                    onBack = onBack,
                    floatingBarEnabled = floatingBarEnabled,
                    onFloatingBarChange = {
                        floatingBarEnabled = it
                        PredictiveBackPreferences.setFloatingBarEnabled(context, it)
                    },
                    modernStyleEnabled = modernStyleEnabled,
                    onModernStyleChange = {
                        modernStyleEnabled = it
                        onModernStyleChange(it)
                    },
                    miuixModeEnabled = miuixModeEnabled,
                    onMiuixModeChange = {
                        miuixModeEnabled = it
                        onMiuixModeChange(it)
                    },
                    barSizeOptions = barSizeOptions,
                    currentBarSizeIndex = currentBarSizeIndex,
                    onBarSizeChange = { index ->
                        PredictiveBackPreferences.setBarSize(context, barSizeOptions[index])
                    }
                )
            }

            PredictiveBackHandler { progress: Flow<BackEventCompat> ->
                isBackGestureActive = true
                try {
                    progress.collect { backProgress = it.progress }
                    onBack()
                } catch (_: CancellationException) {
                    isBackGestureActive = false
                    backProgress = 0f
                }
            }
        }

        // 水印
        WatermarkOverlay()
    }
}

// ======================== Miuix 模式 ========================

@Composable
private fun InterfaceSettingsMiuixContent(
    onBack: () -> Unit,
    floatingBarEnabled: Boolean,
    onFloatingBarChange: (Boolean) -> Unit,
    modernStyleEnabled: Boolean,
    onModernStyleChange: (Boolean) -> Unit,
    miuixModeEnabled: Boolean,
    onMiuixModeChange: (Boolean) -> Unit,
    barSizeOptions: List<String>,
    currentBarSizeIndex: Int,
    onBarSizeChange: (Int) -> Unit
) {
    MiuixScaffold(
        topBar = {
            SmallTopAppBar(
                title = "界面调整",
                navigationIcon = {
                    top.yukonga.miuix.kmp.basic.IconButton(onClick = onBack) {
                        top.yukonga.miuix.kmp.basic.Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                }
            )
        },
        containerColor = MiuixTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0)
    ) { innerPadding ->
        LazyColumn(modifier = Modifier.padding(innerPadding)) {
            item {
                top.yukonga.miuix.kmp.basic.Card(modifier = Modifier.padding(horizontal = 12.dp)) {
                    SwitchPreference(
                        checked = miuixModeEnabled,
                        onCheckedChange = onMiuixModeChange,
                        title = "Miuix UI",
                        summary = "使用 Miuix 组件库渲染界面"
                    )
                }
            }
            item { Spacer(modifier = Modifier.height(12.dp)) }
            item {
                top.yukonga.miuix.kmp.basic.Card(modifier = Modifier.padding(horizontal = 12.dp)) {
                    SwitchPreference(
                        checked = floatingBarEnabled,
                        onCheckedChange = onFloatingBarChange,
                        title = "悬浮底栏",
                        summary = "启用浮动导航栏样式"
                    )
                    androidx.compose.animation.AnimatedVisibility(visible = floatingBarEnabled) {
                        Column {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp)
                                    .height(0.5.dp)
                                    .background(MiuixTheme.colorScheme.outline.copy(alpha = 0.6f))
                            )
                            OverlaySpinnerPreference(
                                items = barSizeOptions.map { DropdownItem(text = it) },
                                selectedIndex = currentBarSizeIndex,
                                title = "底栏大小",
                                summary = "调整悬浮底栏的显示尺寸"
                            ) { onBarSizeChange(it) }
                        }
                    }
                }
            }
            item { Spacer(modifier = Modifier.height(12.dp)) }
            item {
                top.yukonga.miuix.kmp.basic.Card(modifier = Modifier.padding(horizontal = 12.dp)) {
                    SwitchPreference(
                        checked = true,
                        onCheckedChange = {},
                        title = "预见式返回",
                        summary = "返回手势时显示缩放动画效果"
                    )
                }
            }
            item { Spacer(modifier = Modifier.height(12.dp)) }
            item {
                top.yukonga.miuix.kmp.basic.Card(modifier = Modifier.padding(horizontal = 12.dp)) {
                    SwitchPreference(
                        checked = modernStyleEnabled,
                        onCheckedChange = onModernStyleChange,
                        title = "现代样式",
                        summary = "纯黑白配色，简洁现代"
                    )
                }
            }
            item { Spacer(modifier = Modifier.height(12.dp)) }
        }
    }
}

// ======================== Material3 模式 ========================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InterfaceSettingsM3Content(
    onBack: () -> Unit,
    floatingBarEnabled: Boolean,
    onFloatingBarChange: (Boolean) -> Unit,
    modernStyleEnabled: Boolean,
    onModernStyleChange: (Boolean) -> Unit,
    miuixModeEnabled: Boolean,
    onMiuixModeChange: (Boolean) -> Unit,
    barSizeOptions: List<String>,
    currentBarSizeIndex: Int,
    onBarSizeChange: (Int) -> Unit
) {
    val m3SurfaceVariant = MaterialTheme.colorScheme.surfaceVariant

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("界面调整") },
                navigationIcon = {
                    androidx.compose.material3.IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0)
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            // Miuix UI 开关
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = m3SurfaceVariant),
                elevation = CardDefaults.cardElevation(defaultElevation = 8.dp, pressedElevation = 12.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Miuix UI", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                        Text("使用 Miuix 组件库渲染界面", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = miuixModeEnabled, onCheckedChange = onMiuixModeChange)
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 悬浮底栏 + 底栏大小
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomStart = 5.dp, bottomEnd = 5.dp),
                colors = CardDefaults.cardColors(containerColor = m3SurfaceVariant),
                elevation = CardDefaults.cardElevation(defaultElevation = 8.dp, pressedElevation = 12.dp)
            ) {
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("悬浮底栏", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                            Text("启用浮动导航栏样式", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = floatingBarEnabled, onCheckedChange = onFloatingBarChange)
                    }

                    androidx.compose.animation.AnimatedVisibility(
                        visible = floatingBarEnabled,
                        enter = androidx.compose.animation.expandVertically(
                            animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMedium)
                        ) + androidx.compose.animation.fadeIn(tween(200)),
                        exit = androidx.compose.animation.shrinkVertically(
                            animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMedium)
                        ) + androidx.compose.animation.fadeOut(tween(150))
                    ) {
                        Column {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 20.dp)
                                    .height(1.dp)
                                    .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.6f))
                            )
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 36.dp, vertical = 16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("底栏大小", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                                    Text("调整悬浮底栏的显示尺寸", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text(barSizeOptions[currentBarSizeIndex], color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // 预见式返回
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(topStart = 5.dp, topEnd = 5.dp, bottomStart = 16.dp, bottomEnd = 16.dp),
                colors = CardDefaults.cardColors(containerColor = m3SurfaceVariant),
                elevation = CardDefaults.cardElevation(defaultElevation = 8.dp, pressedElevation = 12.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("预见式返回", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                        Text("返回手势时显示缩放动画效果", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = true, onCheckedChange = {})
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 现代样式
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = m3SurfaceVariant),
                elevation = CardDefaults.cardElevation(defaultElevation = 8.dp, pressedElevation = 12.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("现代样式", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                        Text("纯黑白配色，简洁现代", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = modernStyleEnabled, onCheckedChange = onModernStyleChange)
                }
            }
        }
    }
}

// ======================== 水印（共用） ========================

@Composable
private fun WatermarkOverlay() {
    val deviceModel = android.os.Build.MODEL ?: "Unknown"
    val osVer = "MIUI ${android.os.Build.VERSION.SDK_INT}"
    val androidVer = "Android ${android.os.Build.VERSION.RELEASE}"
    val wmText = "$deviceModel | $osVer | $androidVer\n该项目仍处于Debug阶段，不代表最终品质"
    val isDark = isSystemInDarkTheme()
    val wmColor = if (isDark) android.graphics.Color.argb(20, 255, 255, 255) else android.graphics.Color.argb(20, 0, 0, 0)
    val wmPaint = remember(wmColor) {
        android.graphics.Paint().apply { color = wmColor; textSize = 50f; isAntiAlias = true }
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(50f)
            .drawBehind {
                val lineHeightPx = 44.dp.toPx()
                val lines = wmText.split("\n")
                val totalHeight = lines.size * lineHeightPx
                val spacingX = 280.dp.toPx()
                val spacingY = 200.dp.toPx()
                for (row in -2..(size.height / spacingY + 2).toInt()) {
                    for (col in -2..(size.width / spacingX + 2).toInt()) {
                        val x = col * spacingX
                        val y = row * spacingY
                        drawContext.canvas.nativeCanvas.apply {
                            save()
                            rotate(-45f, x, y + totalHeight / 2)
                            lines.forEachIndexed { i, line -> drawText(line, x, y + i * lineHeightPx, wmPaint) }
                            restore()
                        }
                    }
                }
            }
    )
}
