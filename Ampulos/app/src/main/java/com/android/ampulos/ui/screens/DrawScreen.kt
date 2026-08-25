package com.android.ampulos.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.exponentialDecay
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FrontHand
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.android.ampulos.DeckConfigActivity
import com.android.ampulos.R
import com.android.ampulos.data.Card
import com.android.ampulos.data.CardLibrary
import com.android.ampulos.ui.components.GameCard
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

data class FlyingCard(
    val card: Card,
    val targetHandIndex: Int,
    val cardColor: Color
)

data class ReturningCard(
    val card: Card,
    val handIndex: Int,
    val delayMs: Long,
    val cardColor: Color
)

@Composable
fun DrawScreen(
    currentDeck: List<Card>,
    onDeckUpdate: (List<Card>) -> Unit,
    navController: NavHostController
) {
    // 预见式返回动画已在 MainActivity 的 NavHost 层级统一处理
    // 此处仅保留 BackHandler 兼容旧版本 Android
    BackHandler {
        navController.popBackStack()
    }

    DrawScreenContent(
        currentDeck = currentDeck,
        onDeckUpdate = onDeckUpdate,
        navController = navController
    )
}

@Composable
private fun DrawScreenContent(
    currentDeck: List<Card>,
    onDeckUpdate: (List<Card>) -> Unit,
    navController: NavHostController
) {
    // 红蓝两个独立牌堆，各20张
    val redDeck = remember { mutableStateListOf<Card>() }
    val blueDeck = remember { mutableStateListOf<Card>() }
    val handCards = remember { mutableStateListOf<Card>() }
    val handCardColors = remember { mutableStateListOf<Color>() }
    val context = LocalContext.current
    var showEmptyHint by remember { mutableStateOf(true) }
    val returningCards = remember { mutableStateListOf<ReturningCard>() }
    var flyingCard by remember { mutableStateOf<FlyingCard?>(null) }
    var isFirstDraw by remember { mutableStateOf(true) }
    var isDrawing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    // redDeck=前堆，blueDeck=后堆，交换时直接互换内容
    var isRedFront by remember { mutableStateOf(true) }
    val redColor = Color(0xFFFFCDD2)
    val blueColor = Color(0xFFBBDEFB)

    // 牌堆用大卡，手牌用小卡
    val deckCardWidth = 160.dp
    val deckCardHeight = 224.dp
    val handCardWidth = 120.dp
    val handCardHeight = 168.dp

    val deckCenterY = with(density) { (-160).dp.toPx() }
    val handCenterY = with(density) { 120.dp.toPx() }
    val cardSpacingPx = with(density) { 90.dp.toPx() }

    // 牌堆滑动露出配置按钮
    val deckSwipeOffset = remember { Animatable(0f) }
    val deckSwipeMax = with(density) { 80.dp.toPx() }
    val deckSwipeLeftLimit = with(density) { (-20).dp.toPx() }
    val deckSnapThreshold = with(density) { 15.dp.toPx() }

    var wheelScroll by remember { mutableStateOf(0f) }
    val handScrollAnim = remember { Animatable(0f) }

    // 牌堆交换动画：0=静止，1=交换完成
    val deckSwapProgress = remember { Animatable(0f) }

    // 发牌按钮缩放动画
    val drawButtonScale = remember { Animatable(1f) }

    // 重置按钮滑出动画（默认0藏在发牌按钮下，发牌后滑到左侧露出）
    val resetSlideOffset = remember { Animatable(0f) }
    val resetSlideDistance = with(density) { 96.dp.toPx() }

    // 交换按钮滑出动画（默认0藏在发牌按钮下，发牌后滑到右侧露出）
    val swapSlideOffset = remember { Animatable(0f) }
    val swapSlideDistance = with(density) { 96.dp.toPx() }

    // 发牌按钮拖拽状态
    val dragOffset = remember { Animatable(0f) }
    val dragThresholdPx = with(density) { 50.dp.toPx() }
    val dragMaxPx = with(density) { 104.dp.toPx() }
    val isDragging = remember { mutableStateOf(false) }
    val dragTarget = remember { mutableStateOf<String?>(null) }
    val hasSnapped = remember { mutableStateOf(false) }
    val hapticFeedback = LocalHapticFeedback.current
    val mainButtonShakeOffset = remember { Animatable(0f) }

    // 重置二次确认：红色对勾按钮位置（从重置按钮处滑出）
    val confirmResetVisible = remember { mutableStateOf(false) }
    val confirmResetAnimX = remember { Animatable(0f) }

    // 圆环进度条淡入动画
    val ringAlpha by animateFloatAsState(
        targetValue = if (isFirstDraw) 0f else 1f,
        animationSpec = tween(durationMillis = 400, easing = FastOutSlowInEasing),
        label = "ringAlpha"
    )

    // 圆环收放动画：拖拽时收进圆心，归位后展开
    val ringScale by animateFloatAsState(
        targetValue = if (isDragging.value) 0f else 1f,
        animationSpec = tween(durationMillis = 250, easing = FastOutSlowInEasing),
        label = "ringScale"
    )

    LaunchedEffect(Unit) {
        if (redDeck.isEmpty() && blueDeck.isEmpty()) {
            // 等首帧渲染完再加载卡片，避免冷启动卡顿
            delay(16)
            val baseCards = CardLibrary.getAllCards()
            redDeck.addAll(baseCards.shuffled().take(20))
            blueDeck.addAll(baseCards.shuffled().take(20))
        }
    }

    fun resetGame() {
        if (isDrawing || handCards.isEmpty()) return
        scope.launch {
            isDrawing = true
            // 按钮收回
            launch {
                resetSlideOffset.animateTo(
                    0f,
                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                )
            }
            launch {
                swapSlideOffset.animateTo(
                    0f,
                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                )
            }
            // 平滑滑动焦点到第一张牌
            handScrollAnim.animateTo(
                0f,
                spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessVeryLow
                )
            )
            wheelScroll = 0f
            delay(80)
            val cards = handCards.toList()
            val newReturning = cards.mapIndexed { index, card ->
                ReturningCard(card, index, index * 60L, handCardColors.getOrElse(index) { Color.White })
            }
            handCards.clear()
            handCardColors.clear()
            returningCards.clear()
            returningCards.addAll(newReturning)
            val maxDelay = cards.size * 60L + 500L
            delay(maxDelay)
            returningCards.clear()
            flyingCard = null
            // 重新生成两个牌堆
            val baseCards = CardLibrary.getAllCards()
            redDeck.clear()
            blueDeck.clear()
            redDeck.addAll(baseCards.shuffled().take(20))
            blueDeck.addAll(baseCards.shuffled().take(20))
            isFirstDraw = true
            isRedFront = true
            isDrawing = false
            showEmptyHint = true
        }
    }

    fun shakeMainButton() {
        scope.launch {
            mainButtonShakeOffset.animateTo(8f, tween(60))
            mainButtonShakeOffset.animateTo(-8f, tween(60))
            mainButtonShakeOffset.animateTo(6f, tween(60))
            mainButtonShakeOffset.animateTo(-6f, tween(60))
            mainButtonShakeOffset.animateTo(4f, tween(50))
            mainButtonShakeOffset.animateTo(-4f, tween(50))
            mainButtonShakeOffset.animateTo(0f, tween(40))
        }
    }

    fun drawCards(count: Int) {
        if (isDrawing || redDeck.isEmpty()) return
        showEmptyHint = false
        scope.launch {
            isDrawing = true
            launch {
                deckSwipeOffset.animateTo(
                    0f,
                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                )
            }
            launch {
                resetSlideOffset.animateTo(
                    resetSlideDistance,
                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                )
            }
            launch {
                swapSlideOffset.animateTo(
                    swapSlideDistance,
                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                )
            }
            drawButtonScale.animateTo(0.85f, tween(150, easing = FastOutSlowInEasing))

            val isFirstFour = handCards.isEmpty() && count >= 4
            repeat(count) {
                // 开局第1张从蓝牌堆抽，其余从前堆抽
                val fromBlue = isFirstFour && handCards.size == 0
                val deck = if (fromBlue && blueDeck.isNotEmpty()) blueDeck else redDeck
                if (deck.isNotEmpty()) {
                    val card = deck[deck.lastIndex]
                    deck.removeAt(deck.lastIndex)
                    val cardColor = if (fromBlue) blueColor else if (isRedFront) redColor else blueColor
                    val targetIndex = handCards.size
                    flyingCard = FlyingCard(card, targetIndex, cardColor)
                    // 让位动画和飞行动画并行，等飞行动画完成再移除飞牌
                    handScrollAnim.animateTo(targetIndex.toFloat(), tween(400, easing = FastOutSlowInEasing))
                    delay(500)
                    flyingCard = null
                    handCards.add(card)
                    handCardColors.add(cardColor)
                    delay(80)
                }
            }
            drawButtonScale.animateTo(1f, tween(200, easing = FastOutSlowInEasing))
            isDrawing = false
        }
    }

    // 圆环进度参数
    val ringStrokeWidth = with(density) { 4.dp.toPx() }
    val ringRadius = with(density) { 42.dp.toPx() }
    val ringColor = MaterialTheme.colorScheme.primary
    val ringBgColor = MaterialTheme.colorScheme.surfaceVariant
    // 活跃牌堆进度（发牌按钮环形进度条）
    val activeProgressTarget = if (redDeck.isNotEmpty()) redDeck.size.toFloat() / 20f else 0f
    // 非活跃牌堆进度（交换按钮环形进度条）
    val inactiveProgressTarget = if (blueDeck.isNotEmpty()) blueDeck.size.toFloat() / 20f else 0f
    val activeProgress by animateFloatAsState(
        targetValue = activeProgressTarget,
        animationSpec = tween(300),
        label = "activeProgress"
    )
    val inactiveProgress by animateFloatAsState(
        targetValue = inactiveProgressTarget,
        animationSpec = tween(300),
        label = "inactiveProgress"
    )

    // 顶部光效颜色：常态蓝色，战斗中红色（isFirstDraw=false时为战斗状态）
    val isBattle = !isFirstDraw
    val lightColor by animateColorAsState(
        targetValue = if (isBattle) Color(0xFFCC2200) else Color(0xFF2266BB),
        animationSpec = tween(durationMillis = 800),
        label = "lightColor"
    )
    // 光效呼吸脉动
    val lightPulse = remember { Animatable(0.5f) }
    LaunchedEffect(isBattle) {
        if (isBattle) {
            // 战斗状态：缓慢深沉的脉动
            while (true) {
                lightPulse.animateTo(1f, tween(1200, easing = FastOutSlowInEasing))
                lightPulse.animateTo(0.6f, tween(1200, easing = FastOutSlowInEasing))
            }
        } else {
            // 常态：柔和的呼吸
            while (true) {
                lightPulse.animateTo(0.55f, tween(2000, easing = FastOutSlowInEasing))
                lightPulse.animateTo(0.35f, tween(2000, easing = FastOutSlowInEasing))
            }
        }
    }
    val animatedProgress by animateFloatAsState(
        targetValue = activeProgressTarget,
        animationSpec = tween(durationMillis = 300, easing = FastOutSlowInEasing),
        label = "progress"
    )

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0, 0, 0, 0)
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.background)
                    .padding(WindowInsets(0, 0, 0, 0).asPaddingValues())
            ) {
                // 顶部光效
                Canvas(
                    modifier = Modifier.fillMaxSize()
                ) {
                    val cx = size.width / 2f
                    val p = lightPulse.value

                    // 外层散射
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                lightColor.copy(alpha = p * 0.15f),
                                Color.Transparent
                            ),
                            center = Offset(cx, 0f),
                            radius = size.width * 0.9f
                        ),
                        radius = size.width * 0.9f,
                        center = Offset(cx, 0f)
                    )
                    // 内层辉光
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                lightColor.copy(alpha = p * 0.25f),
                                Color.Transparent
                            ),
                            center = Offset(cx, 0f),
                            radius = size.width * 0.35f
                        ),
                        radius = size.width * 0.35f,
                        center = Offset(cx, 0f)
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = 100.dp),
                    contentAlignment = Alignment.Center
                ) {
                    // 1. 牌堆区域（牌堆滑动 + 固定配置按钮）
                    Box(
                        modifier = Modifier
                            .offset { IntOffset(0, deckCenterY.roundToInt()) }
                            .size(width = deckCardWidth + 80.dp, height = deckCardHeight),
                        contentAlignment = Alignment.Center
                    ) {
                        // 配置按钮（固定在牌堆左侧位置）
                        Box(
                            modifier = Modifier
                                .offset {
                                    IntOffset(
                                        (-deckCardWidth / 2 - 4.dp).roundToPx(),
                                        0
                                    )
                                }
                                .size(48.dp)
                                .graphicsLayer {
                                    alpha = (deckSwipeOffset.value / deckSwipeMax).coerceIn(0f, 1f)
                                }
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primaryContainer)
                                .clickable {
                                    if (isFirstDraw) {
                                        val intent = android.content.Intent(context, DeckConfigActivity::class.java)
                                        context.startActivity(intent)
                                    }
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                painter = painterResource(id = R.drawable.baseline_settings_24),
                                contentDescription = "Config",
                                modifier = Modifier.size(24.dp),
                                tint = if (isFirstDraw) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                            )
                        }

                        // 牌堆卡片（向右无限拉伸 + 向左限位 + 弹簧回弹）
                        Box(
                            modifier = Modifier
                                .offset {
                                    IntOffset(deckSwipeOffset.value.roundToInt(), 0)
                                }
                                .pointerInput(Unit) {
                                    detectDragGestures(
                                        onDrag = { change, dragAmount ->
                                            change.consume()
                                            scope.launch {
                                                val newOffset = deckSwipeOffset.value + dragAmount.x
                                                deckSwipeOffset.snapTo(newOffset.coerceAtLeast(deckSwipeLeftLimit))
                                            }
                                        },
                                        onDragEnd = {
                                            scope.launch {
                                                val current = deckSwipeOffset.value
                                                when {
                                                    current in -deckSnapThreshold..deckSnapThreshold -> {
                                                        deckSwipeOffset.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
                                                    }
                                                    current < 0 -> {
                                                        deckSwipeOffset.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
                                                    }
                                                    else -> {
                                                        deckSwipeOffset.animateTo(deckSwipeMax, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
                                                    }
                                                }
                                            }
                                        },
                                        onDragCancel = {
                                            scope.launch {
                                                deckSwipeOffset.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
                                            }
                                        }
                                    )
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            if (redDeck.size >= 2) {
                                val p = deckSwapProgress.value
                                val behindDp = with(density) { 4.dp.toPx() }
                                val slidePx = with(density) { deckCardWidth.toPx() }

                                // 卡片A：前→后
                                val aX = p * slidePx
                                val aY = p * behindDp
                                val aAlpha = 1f - p
                                val aElevation = 6f - p * 2f

                                // 卡片B：后→前
                                val bX = (1f - p) * (-behindDp)
                                val bY = (1f - p) * (-behindDp)
                                val bAlpha = p
                                val bElevation = 4f + p * 2f

                                val frontCard = if (isRedFront) redColor else blueColor
                                val backCard = if (isRedFront) blueColor else redColor

                                // 后层牌（卡片B，正在滑入前面）
                                GameCard(
                                    modifier = Modifier
                                        .offset { IntOffset(bX.roundToInt(), bY.roundToInt()) }
                                        .graphicsLayer { alpha = bAlpha },
                                    cardColor = backCard,
                                    elevation = bElevation,
                                    width = deckCardWidth,
                                    height = deckCardHeight
                                )
                                // 前层牌（卡片A，正在滑到后面）
                                GameCard(
                                    modifier = Modifier
                                        .offset { IntOffset(aX.roundToInt(), aY.roundToInt()) }
                                        .graphicsLayer { alpha = aAlpha },
                                    cardColor = frontCard,
                                    elevation = aElevation,
                                    width = deckCardWidth,
                                    height = deckCardHeight
                                )
                            } else if (redDeck.size == 1) {
                                GameCard(
                                    cardColor = if (isRedFront) redColor else blueColor,
                                    elevation = 6f,
                                    width = deckCardWidth,
                                    height = deckCardHeight
                                )
                            } else if (flyingCard == null && returningCards.isEmpty()) {
                                Box(
                                    modifier = Modifier
                                        .size(width = deckCardWidth, height = deckCardHeight)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(Color.LightGray.copy(alpha = 0.2f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text("Empty", color = Color.Gray.copy(alpha = 0.5f))
                                }
                            }
                        }

                        if (redDeck.size > 2) {
                            Text(
                                text = "${redDeck.size}",
                                modifier = Modifier.offset {
                                    IntOffset(
                                        deckSwipeOffset.value.roundToInt(),
                                        deckCardHeight.roundToPx() / 2 + 20.dp.roundToPx()
                                    )
                                },
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }

                    }

                    // 2. 飞行卡牌（发牌）
                    flyingCard?.let { fc ->
                        key(fc.card.id) {
                            FlyingCardAnimation(
                                flyingCard = fc,
                                deckCenterY = deckCenterY,
                                handCenterY = handCenterY,
                                deckCardWidth = deckCardWidth,
                                deckCardHeight = deckCardHeight,
                                handCardWidth = handCardWidth,
                                handCardHeight = handCardHeight
                            )
                        }
                    }

                    // 3. 归位卡牌
                    returningCards.forEach { rc ->
                        key(rc.card.id) {
                            ReturningCardAnimation(
                                returningCard = rc,
                                deckCenterY = deckCenterY,
                                handCenterY = handCenterY,
                                cardSpacingPx = cardSpacingPx,
                                currentScroll = wheelScroll,
                                deckCardWidth = deckCardWidth,
                                deckCardHeight = deckCardHeight,
                                handCardWidth = handCardWidth,
                                handCardHeight = handCardHeight
                            )
                        }
                    }

                    // 4. 轮盘手牌
                    WheelHandCards(
                        handCards = handCards,
                        handCardColors = handCardColors,
                        handCenterY = handCenterY,
                        cardSpacingPx = cardSpacingPx,
                        wheelScroll = wheelScroll,
                        handScrollAnim = handScrollAnim,
                        isDrawing = isDrawing,
                        onWheelScrollChange = { wheelScroll = it },
                        cardWidth = handCardWidth,
                        cardHeight = handCardHeight,
                        showEmptyHint = showEmptyHint
                    )
                }

                // 底部按钮区域
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 80.dp),
                    contentAlignment = Alignment.Center
                ) {
                    // 重置按钮（默认藏在发牌按钮底下，发牌后左移出现）
                    val resetEnabled = !isDrawing
                    Box(
                        modifier = Modifier
                            .size(64.dp)
                            .offset { IntOffset((-resetSlideOffset.value).roundToInt(), 0) }
                            .graphicsLayer {
                                val alpha = if (isFirstDraw) 0f else if (resetEnabled) 1f else 0.4f
                                this.alpha = alpha
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        // 重置按钮环形进度
                        Box(
                            modifier = Modifier
                                .size(64.dp)
                                .drawBehind {
                                    val sr = 28.dp.toPx()
                                    val ss = 3.dp.toPx()
                                    val c = size.width / 2f
                                    drawArc(
                                        color = ringBgColor,
                                        startAngle = -90f,
                                        sweepAngle = 360f,
                                        useCenter = false,
                                        style = Stroke(width = ss, cap = StrokeCap.Round),
                                        topLeft = Offset(c - sr, c - sr),
                                        size = Size(sr * 2, sr * 2)
                                    )
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(48.dp)
                                    .clip(CircleShape)
                                    .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.baseline_refresh_24),
                                    contentDescription = "Reset",
                                    modifier = Modifier.size(24.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    // 交换按钮（默认藏在发牌按钮底下，发牌后右移出现，和重置对称）
                    val swapEnabled = !isDrawing && redDeck.size >= 2
                    val inactiveRingColor = if (isRedFront) blueColor else redColor
                    Box(
                        modifier = Modifier
                            .size(64.dp)
                            .offset { IntOffset(swapSlideOffset.value.roundToInt(), 0) }
                            .graphicsLayer {
                                val isActive = dragTarget.value == "swap" && swapEnabled
                                val alpha = if (isFirstDraw) 0f else if (swapEnabled) 1f else 0.4f
                                scaleX = if (isActive) 1.15f else 1f
                                scaleY = if (isActive) 1.15f else 1f
                                this.alpha = alpha
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        // 交换按钮环形进度
                        Box(
                            modifier = Modifier
                                .size(64.dp)
                                .drawBehind {
                                    val sr = 28.dp.toPx()
                                    val ss = 3.dp.toPx()
                                    val c = size.width / 2f
                                    drawArc(
                                        color = ringBgColor,
                                        startAngle = -90f,
                                        sweepAngle = 360f,
                                        useCenter = false,
                                        style = Stroke(width = ss, cap = StrokeCap.Round),
                                        topLeft = Offset(c - sr, c - sr),
                                        size = Size(sr * 2, sr * 2)
                                    )
                                    drawArc(
                                        color = inactiveRingColor,
                                        startAngle = -90f,
                                        sweepAngle = 360f * inactiveProgress,
                                        useCenter = false,
                                        style = Stroke(width = ss, cap = StrokeCap.Round),
                                        topLeft = Offset(c - sr, c - sr),
                                        size = Size(sr * 2, sr * 2)
                                    )
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(48.dp)
                                    .clip(CircleShape)
                                    .background(
                                        if (dragTarget.value == "swap" && swapEnabled)
                                            MaterialTheme.colorScheme.primaryContainer
                                        else
                                            MaterialTheme.colorScheme.surfaceVariant
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    painter = painterResource(id = R.drawable.baseline_swap_horiz_24),
                                    contentDescription = "Swap",
                                    modifier = Modifier.size(24.dp),
                                    tint = if (dragTarget.value == "swap" && swapEnabled)
                                        MaterialTheme.colorScheme.primary
                                    else
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    // 红色确认重置按钮（在发牌按钮后面，被遮住）
                    if (confirmResetVisible.value) {
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .offset { IntOffset(confirmResetAnimX.value.roundToInt(), 0) }
                                .graphicsLayer {
                                    scaleX = if (dragTarget.value == "confirm_reset") 1.15f else 1f
                                    scaleY = if (dragTarget.value == "confirm_reset") 1.15f else 1f
                                }
                                .clip(CircleShape)
                                .background(Color(0xFFE53935))
                                .clickable(enabled = false) {},
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Check,
                                contentDescription = "Confirm Reset",
                                modifier = Modifier.size(24.dp),
                                tint = Color.White
                            )
                        }
                    }

                    // 发牌按钮（居中 + 最高层级 + 可拖拽）
                    Box(
                        modifier = Modifier.zIndex(2f),
                        contentAlignment = Alignment.Center
                    ) {
                        // 圆环进度（活跃牌堆颜色）
                        val activeRingColor = if (isRedFront) redColor else blueColor
                        Box(
                            modifier = Modifier
                                .size(92.dp)
                                .graphicsLayer {
                                    alpha = ringAlpha
                                    scaleX = ringScale
                                    scaleY = ringScale
                                }
                                .drawBehind {
                                    val sr = ringRadius * ringScale
                                    val ss = ringStrokeWidth * ringScale
                                    val c = size.width / 2f
                                    drawArc(
                                        color = ringBgColor,
                                        startAngle = -90f,
                                        sweepAngle = 360f,
                                        useCenter = false,
                                        style = Stroke(width = ss, cap = StrokeCap.Round),
                                        topLeft = Offset(c - sr, c - sr),
                                        size = Size(sr * 2, sr * 2)
                                    )
                                    drawArc(
                                        color = activeRingColor,
                                        startAngle = -90f,
                                        sweepAngle = 360f * activeProgress,
                                        useCenter = false,
                                        style = Stroke(width = ss, cap = StrokeCap.Round),
                                        topLeft = Offset(c - sr, c - sr),
                                        size = Size(sr * 2, sr * 2)
                                    )
                                }
                        )

                        // 发牌按钮
                        FilledIconButton(
                            onClick = {
                                if (dragOffset.value == 0f) {
                                    if (isFirstDraw) {
                                        drawCards(4)
                                        isFirstDraw = false
                                    } else {
                                        drawCards(1)
                                    }
                                }
                            },
                            enabled = !isDrawing && redDeck.isNotEmpty() && dragOffset.value == 0f,
                            modifier = Modifier
                                .size(72.dp)
                                .offset { IntOffset((dragOffset.value + mainButtonShakeOffset.value).roundToInt(), 0) }
                                .graphicsLayer {
                                    scaleX = drawButtonScale.value
                                    scaleY = drawButtonScale.value
                                }
                                .pointerInput(handCards.size, isFirstDraw) {
                                    detectDragGestures(
                                        onDragStart = {
                                            if ((handCards.isEmpty() && isFirstDraw) || isDrawing) {
                                                isDragging.value = false
                                                return@detectDragGestures
                                            }
                                            isDragging.value = true
                                            hasSnapped.value = false
                                            confirmResetVisible.value = false
                                            scope.launch { confirmResetAnimX.snapTo(0f) }
                                        },
                                        onDrag = { change, dragAmount ->
                                            change.consume()
                                            // 手里没牌且还没发过牌，不响应拖拽
                                            if ((handCards.isEmpty() && isFirstDraw) || isDrawing) return@detectDragGestures
                                            scope.launch {
                                                val newOffset = (dragOffset.value + dragAmount.x)
                                                    .coerceIn(-dragMaxPx, dragMaxPx)
                                                dragOffset.snapTo(newOffset)

                                                if (confirmResetVisible.value) {
                                                    // 确认按钮已显示，检测是否拖到确认按钮上
                                                    val distToConfirm = kotlin.math.abs(newOffset - confirmResetAnimX.value)
                                                    val reachedConfirm = distToConfirm < with(density) { 30.dp.toPx() }
                                                    dragTarget.value = if (reachedConfirm) "confirm_reset" else null
                                                    if (reachedConfirm && !hasSnapped.value) {
                                                        hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        hasSnapped.value = true
                                                    }
                                                    if (!reachedConfirm) hasSnapped.value = false
                                                } else {
                                                    // 第一阶段：检测是否到达重置或交换按钮
                                                    val rawTarget = when {
                                                        newOffset < -dragThresholdPx -> "reset"
                                                        newOffset > dragThresholdPx -> "swap"
                                                        else -> null
                                                    }
                                                    val isTargetEnabled = when (rawTarget) {
                                                        "reset" -> !isDrawing
                                                        "swap" -> !isDrawing && redDeck.size >= 2
                                                        else -> true
                                                    }
                                                    val newTarget = if (isTargetEnabled) rawTarget else null
                                                    if (newTarget != null && !hasSnapped.value) {
                                                        hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        hasSnapped.value = true
                                                        if (newTarget == "reset") {
                                                            // 显示确认按钮在主按钮右侧
                                                            confirmResetVisible.value = true
                                                            launch {
                                                                confirmResetAnimX.animateTo(
                                                                    dragThresholdPx * 2f,
                                                                    spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
                                                                )
                                                            }
                                                        }
                                                    }
                                                    if (rawTarget != null && !isTargetEnabled && !hasSnapped.value) {
                                                        hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                                        shakeMainButton()
                                                        hasSnapped.value = true
                                                    }
                                                    if (rawTarget == null) hasSnapped.value = false
                                                    dragTarget.value = newTarget
                                                }
                                            }
                                        },
                                        onDragEnd = {
                                            // 手里没牌时松手不触发任何操作
                                            if ((handCards.isEmpty() && isFirstDraw) || isDrawing) {
                                                isDragging.value = false
                                                dragTarget.value = null
                                                scope.launch {
                                                    dragOffset.animateTo(0f, tween(200, easing = FastOutSlowInEasing))
                                                }
                                                return@detectDragGestures
                                            }
                                            isDragging.value = false
                                            val target = dragTarget.value
                                            val wasConfirmVisible = confirmResetVisible.value
                                            scope.launch {
                                                dragOffset.animateTo(0f, tween(200, easing = FastOutSlowInEasing))
                                                dragTarget.value = null
                                                hasSnapped.value = false
                                                confirmResetVisible.value = false
                                                confirmResetAnimX.snapTo(0f)
                                            }
                                            // 拖到确认按钮触发重置，拖到交换按钮触发交换
                                            if (target == "confirm_reset" && !isDrawing) resetGame()
                                            if (target == "swap" && !isDrawing && redDeck.size >= 2) {
                                                scope.launch {
                                                    deckSwapProgress.animateTo(1f, tween(300, easing = FastOutSlowInEasing))
                                                    // 交换两个牌堆的内容
                                                    val temp = redDeck.toList()
                                                    redDeck.clear()
                                                    redDeck.addAll(blueDeck)
                                                    blueDeck.clear()
                                                    blueDeck.addAll(temp)
                                                    isRedFront = !isRedFront
                                                    deckSwapProgress.snapTo(0f)
                                                }
                                            }
                                        },
                                        onDragCancel = {
                                            isDragging.value = false
                                            dragTarget.value = null
                                            confirmResetVisible.value = false
                                            scope.launch { confirmResetAnimX.snapTo(0f) }
                                            scope.launch {
                                                dragOffset.animateTo(0f, tween(200, easing = FastOutSlowInEasing))
                                            }
                                        }
                                    )
                                },
                            shape = CircleShape,
                            colors = IconButtonDefaults.filledIconButtonColors(
                                containerColor = MaterialTheme.colorScheme.primary,
                                contentColor = MaterialTheme.colorScheme.onPrimary,
                                disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                                disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        ) {
                            Icon(
                                imageVector = when (dragTarget.value) {
                                    "reset" -> Icons.Default.Refresh
                                    "swap" -> Icons.Default.SwapHoriz
                                    else -> Icons.Default.FrontHand
                                },
                                contentDescription = "Draw",
                                modifier = Modifier.size(32.dp)
                            )
                        }
                    }
                }
            }
        }

        // 满屏水印（不阻挡触摸）- 已移至 MainActivity 全屏覆盖
    }
}

@Composable
fun ReturningCardAnimation(
    returningCard: ReturningCard,
    deckCenterY: Float,
    handCenterY: Float,
    cardSpacingPx: Float,
    currentScroll: Float,
    deckCardWidth: androidx.compose.ui.unit.Dp,
    deckCardHeight: androidx.compose.ui.unit.Dp,
    handCardWidth: androidx.compose.ui.unit.Dp,
    handCardHeight: androidx.compose.ui.unit.Dp
) {
    val scaleDown = (handCardWidth.value / deckCardWidth.value + handCardHeight.value / deckCardHeight.value) / 2f

    val distance = returningCard.handIndex - currentScroll
    val absDist = abs(distance)
    val startX = distance * cardSpacingPx
    val startRotation = distance * 5f
    val startScale = (1f - absDist * 0.1f).coerceIn(0.6f, 1f) * scaleDown

    val animY = remember { Animatable(handCenterY) }
    val animX = remember { Animatable(startX) }
    val animRotation = remember { Animatable(startRotation) }
    val animScale = remember { Animatable(startScale) }

    val accelerateEasing = CubicBezierEasing(0.4f, 0f, 0.9f, 0.4f)

    LaunchedEffect(returningCard.card.id) {
        delay(returningCard.delayMs)
        launch { animY.animateTo(deckCenterY, tween(450, easing = accelerateEasing)) }
        launch { animX.animateTo(0f, tween(450, easing = accelerateEasing)) }
        launch { animRotation.animateTo(0f, tween(450, easing = accelerateEasing)) }
        launch { animScale.animateTo(1f, tween(450, easing = accelerateEasing)) }
    }

    GameCard(
        modifier = Modifier
            .offset { IntOffset(animX.value.roundToInt(), animY.value.roundToInt()) }
            .graphicsLayer {
                rotationZ = animRotation.value
                scaleX = animScale.value
                scaleY = animScale.value
            },
        cardColor = returningCard.cardColor,
        elevation = 12f,
        width = deckCardWidth,
        height = deckCardHeight
    )
}

@Composable
fun WheelHandCards(
    handCards: List<Card>,
    handCardColors: List<Color>,
    handCenterY: Float,
    cardSpacingPx: Float,
    wheelScroll: Float,
    handScrollAnim: Animatable<Float, *>,
    isDrawing: Boolean,
    onWheelScrollChange: (Float) -> Unit,
    cardWidth: androidx.compose.ui.unit.Dp,
    cardHeight: androidx.compose.ui.unit.Dp,
    showEmptyHint: Boolean
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val hapticFeedback = LocalHapticFeedback.current
    var focusedIndex by remember { mutableStateOf(0) }
    var lastHapticCard = remember { mutableStateOf(-1) }

    val decaySpec = remember { exponentialDecay<Float>(frictionMultiplier = 1.5f) }

    // 齿轮震动：监听滚动值整数变化，拖拽和惯性滑动都触发
    LaunchedEffect(Unit) {
        snapshotFlow { handScrollAnim.value }
            .collect { value ->
                val currentCard = value.roundToInt().coerceIn(0, maxOf(0, handCards.size - 1))
                if (currentCard != lastHapticCard.value && handCards.isNotEmpty()) {
                    hapticFeedback.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    lastHapticCard.value = currentCard
                }
            }
    }

    LaunchedEffect(wheelScroll) {
        focusedIndex = wheelScroll.roundToInt().coerceIn(0, maxOf(0, handCards.size - 1))
    }

    val centerElevPx = with(density) { 10.dp.toPx() }
    val sideElevPx = with(density) { 4.dp.toPx() }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(with(density) { 200.dp })
            .offset { IntOffset(0, handCenterY.roundToInt()) }
            .then(
                if (handCards.isNotEmpty() && !isDrawing) {
                    Modifier.pointerInput(Unit) {
                        val posHistory = mutableListOf<Pair<Long, Float>>()
                        detectDragGestures(
                            onDragStart = {
                                scope.launch { handScrollAnim.stop() }
                                posHistory.clear()
                            },
                            onDrag = { change, dragAmount ->
                                change.consume()
                                posHistory.add(change.uptimeMillis to change.position.x)
                                val cutoff = change.uptimeMillis - 100
                                while (posHistory.size > 1 && posHistory.first().first < cutoff) {
                                    posHistory.removeAt(0)
                                }
                                val deltaInCards = -dragAmount.x / cardSpacingPx * 1.8f
                                val currentMax = maxOf(0f, (handCards.size - 1).toFloat())
                                val raw = handScrollAnim.value + deltaInCards
                                // 边缘允许微拉，正常区域直接跟手
                                val target = if (raw < 0f) raw * 0.5f
                                    else if (raw > currentMax) currentMax + (raw - currentMax) * 0.5f
                                    else raw.coerceIn(0f, currentMax)
                                scope.launch { handScrollAnim.snapTo(target) }
                            },
                            onDragEnd = {
                                val currentMax = maxOf(0f, (handCards.size - 1).toFloat())
                                val pos = handScrollAnim.value

                                // 计算速度和幅度
                                val velocityPxPerSec = if (posHistory.size >= 2) {
                                    val (t1, x1) = posHistory.first()
                                    val (t2, x2) = posHistory.last()
                                    val dt = t2 - t1
                                    if (dt > 0) (x2 - x1) / dt * 1000f else 0f
                                } else 0f
                                val velocityInCards = -velocityPxPerSec / cardSpacingPx

                                // 计算实际拖动幅度（转成卡牌数）
                                val amplitudeCards = if (posHistory.size >= 2) {
                                    val (_, x1) = posHistory.first()
                                    val (_, x2) = posHistory.last()
                                    kotlin.math.abs(x2 - x1) / cardSpacingPx
                                } else 0f

                                // 松手一律吸附最近卡牌，根据幅度决定推几张
                                val nearestCard = pos.roundToInt().toFloat().coerceIn(0f, currentMax)
                                val targetPos = if (amplitudeCards < 1f) {
                                    // 小幅度：直接吸附当前位置最近的卡牌
                                    nearestCard
                                } else {
                                    // 大幅度：根据速度方向推多张
                                    val fling = velocityInCards * 0.3f + (amplitudeCards * 0.5f)
                                    (pos + fling).coerceIn(0f, currentMax).roundToInt().toFloat()
                                }

                                scope.launch {
                                    handScrollAnim.animateTo(targetPos, tween(250, easing = FastOutSlowInEasing))
                                    onWheelScrollChange(targetPos)
                                    focusedIndex = targetPos.roundToInt().coerceIn(0, maxOf(0, handCards.size - 1))
                                }
                                posHistory.clear()
                            }
                        )
                    }
                } else Modifier
            ),
        contentAlignment = Alignment.Center
    ) {
        AnimatedVisibility(
            visible = showEmptyHint && handCards.isEmpty(),
            enter = fadeIn(tween(300)) + slideInVertically(tween(300)) { it / 4 },
            exit = fadeOut(tween(200)) + slideOutVertically(tween(200)) { it / 4 }
        ) {
            Text(
                "Your hand is empty",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }
        // 手牌渲染
        if (handCards.isNotEmpty()) {
            val safeFocused = focusedIndex.coerceIn(0, handCards.lastIndex)

            handCards.forEachIndexed { index, card ->
                if (index != safeFocused) {
                    key(card.id) {
                        val cardColor = handCardColors.getOrElse(index) { Color.White }
                        GameCard(
                            modifier = Modifier
                                .offset {
                                    val distance = index - handScrollAnim.value
                                    IntOffset((distance * cardSpacingPx).roundToInt(), 0)
                                }
                                .graphicsLayer {
                                    val distance = index - handScrollAnim.value
                                    val absDist = abs(distance)
                                    val scale = (1f - absDist * 0.1f).coerceIn(0.6f, 1f)
                                    scaleX = scale
                                    scaleY = scale
                                    rotationZ = distance * 5f
                                    alpha = (1f - absDist * 0.18f).coerceIn(0.4f, 1f)
                                    shadowElevation = sideElevPx
                                    shape = RoundedCornerShape(12.dp)
                                    clip = true
                                },
                            cardColor = cardColor,
                            elevation = 0f,
                            width = cardWidth,
                            height = cardHeight
                        )
                    }
                }
            }

            key(handCards[safeFocused].id) {
                val focusedColor = handCardColors.getOrElse(safeFocused) { Color.White }
                GameCard(
                    modifier = Modifier
                        .offset {
                            val distance = safeFocused - handScrollAnim.value
                            IntOffset((distance * cardSpacingPx).roundToInt(), 0)
                        }
                        .graphicsLayer {
                            val distance = safeFocused - handScrollAnim.value
                            val absDist = abs(distance)
                            val scale = (1f - absDist * 0.1f).coerceIn(0.6f, 1f)
                            scaleX = scale
                            scaleY = scale
                            rotationZ = distance * 5f
                            alpha = (1f - absDist * 0.18f).coerceIn(0.4f, 1f)
                            shadowElevation = centerElevPx
                            shape = RoundedCornerShape(12.dp)
                            clip = true
                        },
                    cardColor = focusedColor,
                    elevation = 0f,
                    width = cardWidth,
                    height = cardHeight
                )
            }
        }

    }
}

@Composable
fun FlyingCardAnimation(
    flyingCard: FlyingCard,
    deckCenterY: Float,
    handCenterY: Float,
    deckCardWidth: androidx.compose.ui.unit.Dp,
    deckCardHeight: androidx.compose.ui.unit.Dp,
    handCardWidth: androidx.compose.ui.unit.Dp,
    handCardHeight: androidx.compose.ui.unit.Dp
) {
    val animY = remember { Animatable(deckCenterY) }
    val animX = remember { Animatable(0f) }
    val animRotation = remember { Animatable(0f) }
    val animScale = remember { Animatable(1f) }

    val scaleDown = (handCardWidth.value / deckCardWidth.value + handCardHeight.value / deckCardHeight.value) / 2f

    LaunchedEffect(flyingCard.card.id) {
        animScale.animateTo(1.2f, tween(durationMillis = 150, easing = FastOutSlowInEasing))
        launch { animY.animateTo(handCenterY, tween(durationMillis = 500, easing = FastOutSlowInEasing)) }
        launch { animX.animateTo(0f, tween(durationMillis = 500, easing = FastOutSlowInEasing)) }
        launch { animRotation.animateTo(0f, tween(durationMillis = 500, easing = FastOutSlowInEasing)) }
        launch { animScale.animateTo(scaleDown, tween(durationMillis = 500, easing = FastOutSlowInEasing)) }
    }

    GameCard(
        modifier = Modifier
            .offset { IntOffset(animX.value.roundToInt(), animY.value.roundToInt()) }
            .zIndex(10f)
            .graphicsLayer {
                rotationZ = animRotation.value
                scaleX = animScale.value
                scaleY = animScale.value
            },
        cardColor = flyingCard.cardColor,
        elevation = 12f,
        width = deckCardWidth,
        height = deckCardHeight
    )
}