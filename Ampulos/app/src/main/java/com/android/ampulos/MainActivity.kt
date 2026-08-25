package com.android.ampulos

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.BackEventCompat
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.core.content.ContextCompat
import com.android.ampulos.data.Card
import com.android.ampulos.ui.components.FloatingBottomBar
import com.android.ampulos.ui.screens.DrawScreen
import com.android.ampulos.ui.screens.ProfileScreen
import com.android.ampulos.ui.theme.AmpulosTheme
import com.android.ampulos.ui.theme.LocalUseMiuix
import com.android.ampulos.ui.theme.MiuixAppTheme
import top.yukonga.miuix.kmp.basic.NavigationBarItem as MiuixNavigationBarItem
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val permLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { startCardService() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            permLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            startCardService()
        }

        setContent {
            var useModern by remember { mutableStateOf(PredictiveBackPreferences.isModernStyleEnabled(this@MainActivity)) }
            var useMiuix by remember { mutableStateOf(PredictiveBackPreferences.isMiuixModeEnabled(this@MainActivity)) }
            val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
            androidx.compose.runtime.DisposableEffect(lifecycleOwner) {
                val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                    if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                        useModern = PredictiveBackPreferences.isModernStyleEnabled(this@MainActivity)
                        useMiuix = PredictiveBackPreferences.isMiuixModeEnabled(this@MainActivity)
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
            }
            if (useMiuix) {
                MiuixAppTheme {
                    MainScreen()
                }
            } else {
                AmpulosTheme(useModernStyle = useModern) {
                    MainScreen()
                }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        startCardService()
    }

    private fun startCardService() {
        try {
            ContextCompat.startForegroundService(
                this,
                Intent(this, CardTableService::class.java)
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}

@Composable
fun MainScreen() {
    val currentDeck = remember { mutableStateListOf<Card>() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val pagerState = rememberPagerState(pageCount = { 2 })
    val currentPage = pagerState.currentPage

    // ========== 预见式返回动画 ==========
    var backProgress by remember { mutableFloatStateOf(0f) }
    var isBackGestureActive by remember { mutableStateOf(false) }
    var transparentEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isTransparentEnabled(context))
    }
    LaunchedEffect(Unit) {
        transparentEnabled = PredictiveBackPreferences.isTransparentEnabled(context)
    }

    val predictiveEasing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)

    val scale by animateFloatAsState(
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
    val cornerRadius by animateFloatAsState(
        targetValue = if (isBackGestureActive) backProgress * 24f else 0f,
        animationSpec = if (isBackGestureActive) tween(0) else tween(250, easing = predictiveEasing),
        label = "predictiveCornerRadius"
    )

    val useMiuix = LocalUseMiuix.current

    @Composable
    fun MainContent(padding: androidx.compose.foundation.layout.PaddingValues) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = 80.dp)
            ) {
                if (isBackGestureActive && currentPage == 1) {
                    DrawScreen(
                        currentDeck = currentDeck,
                        onDeckUpdate = { },
                        navController = androidx.navigation.compose.rememberNavController()
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                            translationX = backTranslationX
                            alpha = backAlpha
                            shape = androidx.compose.foundation.shape.RoundedCornerShape(cornerRadius.dp)
                            clip = true
                        }
                ) {
                    HorizontalPager(
                        state = pagerState,
                        modifier = Modifier.fillMaxSize()
                    ) { page ->
                        key(page) {
                            when (page) {
                                0 -> DrawScreen(
                                    currentDeck = currentDeck,
                                    onDeckUpdate = { newDeck ->
                                        currentDeck.clear()
                                        currentDeck.addAll(newDeck)
                                    },
                                    navController = androidx.navigation.compose.rememberNavController()
                                )
                                1 -> ProfileScreen()
                            }
                        }
                    }
                }
                PredictiveBackHandler { progress: Flow<BackEventCompat> ->
                    isBackGestureActive = true
                    try {
                        progress.collect { backEvent ->
                            backProgress = backEvent.progress
                        }
                        if (currentPage == 1) {
                            scope.launch { pagerState.animateScrollToPage(0) }
                        }
                    } catch (_: CancellationException) {
                    } finally {
                        isBackGestureActive = false
                        backProgress = 0f
                    }
                }
            }

            var floatingBarEnabled by remember { mutableStateOf(PredictiveBackPreferences.isFloatingBarEnabled(context)) }
            var barSize by remember { mutableStateOf(PredictiveBackPreferences.getBarSize(context)) }
            val lifecycleOwner2 = androidx.lifecycle.compose.LocalLifecycleOwner.current
            DisposableEffect(lifecycleOwner2) {
                val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                    if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                        floatingBarEnabled = PredictiveBackPreferences.isFloatingBarEnabled(context)
                        barSize = PredictiveBackPreferences.getBarSize(context)
                    }
                }
                lifecycleOwner2.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner2.lifecycle.removeObserver(observer) }
            }

            if (useMiuix) {
                // Miuix 底栏
                if (floatingBarEnabled) {
                    Box(modifier = Modifier.align(Alignment.BottomCenter).zIndex(10f)) {
                        top.yukonga.miuix.kmp.basic.FloatingNavigationBar(
                            color = top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme.surfaceContainer,
                            horizontalOutSidePadding = 12.dp
                        ) {
                            top.yukonga.miuix.kmp.basic.FloatingNavigationBarItem(
                                selected = currentPage == 0,
                                onClick = { scope.launch { pagerState.animateScrollToPage(0) } },
                                icon = Icons.Default.Home,
                                label = "Draw"
                            )
                            top.yukonga.miuix.kmp.basic.FloatingNavigationBarItem(
                                selected = currentPage == 1,
                                onClick = { scope.launch { pagerState.animateScrollToPage(1) } },
                                icon = Icons.Default.Person,
                                label = "Profile"
                            )
                        }
                    }
                } else {
                    top.yukonga.miuix.kmp.basic.NavigationBar(
                        modifier = Modifier.align(Alignment.BottomCenter)
                    ) {
                        MiuixNavigationBarItem(
                            selected = currentPage == 0,
                            onClick = { scope.launch { pagerState.animateScrollToPage(0) } },
                            icon = Icons.Default.Home,
                            label = "Draw"
                        )
                        MiuixNavigationBarItem(
                            selected = currentPage == 1,
                            onClick = { scope.launch { pagerState.animateScrollToPage(1) } },
                            icon = Icons.Default.Person,
                            label = "Profile"
                        )
                    }
                }
            } else {
                // Material3 底栏
                if (floatingBarEnabled) {
                    Box(modifier = Modifier.align(Alignment.BottomCenter).zIndex(10f)) {
                        FloatingBottomBar(
                            currentRoute = if (currentPage == 0) "draw" else "profile",
                            onNavigate = { route ->
                                val targetPage = if (route == "draw") 0 else 1
                                scope.launch { pagerState.animateScrollToPage(targetPage) }
                            },
                            barSize = barSize
                        )
                    }
                } else {
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface,
                        modifier = Modifier.align(Alignment.BottomCenter)
                    ) {
                        NavigationBarItem(
                            icon = { Icon(Icons.Default.Home, contentDescription = null) },
                            label = { Text("Draw") },
                            selected = currentPage == 0,
                            onClick = { scope.launch { pagerState.animateScrollToPage(0) } }
                        )
                        NavigationBarItem(
                            icon = { Icon(Icons.Default.Person, contentDescription = null) },
                            label = { Text("Profile") },
                            selected = currentPage == 1,
                            onClick = { scope.launch { pagerState.animateScrollToPage(1) } }
                        )
                    }
                }
            }

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
                                    lines.forEachIndexed { i, line ->
                                        drawText(line, x, y + i * lineHeightPx, wmPaint)
                                    }
                                    restore()
                                }
                            }
                        }
                    }
            )
        }
    }

    if (useMiuix) {
        top.yukonga.miuix.kmp.basic.Scaffold(
            containerColor = top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme.background,
            contentWindowInsets = WindowInsets(0, 0, 0, 0)
        ) { padding ->
            MainContent(padding)
        }
    } else {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            contentWindowInsets = WindowInsets(0, 0, 0, 0)
        ) { padding ->
            MainContent(padding)
        }
    }
}
