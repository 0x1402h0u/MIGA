package com.android.ampulos

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.BackEventCompat
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.navigation.compose.rememberNavController
import com.android.ampulos.data.Card
import com.android.ampulos.data.CardLibrary
import com.android.ampulos.ui.screens.DrawScreen
import com.android.ampulos.ui.theme.AmpulosTheme
import com.android.ampulos.ui.theme.MiuixAppTheme
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.CancellationException

class DeckConfigActivity : ComponentActivity() {

    companion object {
        const val EXTRA_UPDATED_DECK = "updated_deck"
        const val RESULT_DECK_UPDATED = 2001
    }

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }

        val currentDeckIds = intent.getStringArrayListExtra(EXTRA_UPDATED_DECK) ?: arrayListOf()
        val currentDeck = CardLibrary.getAllCards().filter { currentDeckIds.contains(it.id) }

        setContent {
            var useModern by remember { mutableStateOf(PredictiveBackPreferences.isModernStyleEnabled(this@DeckConfigActivity)) }
            var useMiuix by remember { mutableStateOf(PredictiveBackPreferences.isMiuixModeEnabled(this@DeckConfigActivity)) }
            val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
            androidx.compose.runtime.DisposableEffect(lifecycleOwner) {
                val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                    if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                        useModern = PredictiveBackPreferences.isModernStyleEnabled(this@DeckConfigActivity)
                        useMiuix = PredictiveBackPreferences.isMiuixModeEnabled(this@DeckConfigActivity)
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
            }
            if (useMiuix) {
                MiuixAppTheme {
                    DeckConfigContent(
                        currentDeck = currentDeck,
                        onDeckUpdate = { updatedDeck ->
                            val result = Intent().apply {
                                putStringArrayListExtra(EXTRA_UPDATED_DECK, ArrayList(updatedDeck.map { it.id }))
                            }
                            setResult(RESULT_DECK_UPDATED, result)
                            finish()
                        },
                        onBack = { finish() }
                    )
                }
            } else {
                AmpulosTheme(useModernStyle = useModern) {
                    DeckConfigContent(
                        currentDeck = currentDeck,
                        onDeckUpdate = { updatedDeck ->
                            val result = Intent().apply {
                                putStringArrayListExtra(EXTRA_UPDATED_DECK, ArrayList(updatedDeck.map { it.id }))
                            }
                            setResult(RESULT_DECK_UPDATED, result)
                            finish()
                        },
                        onBack = { finish() }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DeckConfigContent(
    currentDeck: List<Card>,
    onDeckUpdate: (List<Card>) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var backProgress by remember { mutableFloatStateOf(0f) }
    var isBackGestureActive by remember { mutableStateOf(false) }
    var transparentEnabled by remember {
        mutableStateOf(PredictiveBackPreferences.isTransparentEnabled(context))
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

    Box(modifier = Modifier.fillMaxSize()) {
        if (isBackGestureActive) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            )
        }

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
            DeckConfigScreen(
                currentDeck = currentDeck,
                onDeckUpdate = onDeckUpdate,
                onNavigateBack = onBack
            )

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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeckConfigScreen(
    currentDeck: List<Card>,
    onDeckUpdate: (List<Card>) -> Unit,
    onNavigateBack: () -> Unit
) {
    val library = remember { CardLibrary.getAllCards() }
    val selectedDeck = remember { mutableStateListOf<Card>().apply { addAll(currentDeck) } }

    val maxDeckSize = 20

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Configure Deck") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
            ) {
                LibraryPanel(
                    library = library,
                    selectedDeck = selectedDeck,
                    onCardClick = { card ->
                        if (!selectedDeck.contains(card) && selectedDeck.size < maxDeckSize) {
                            selectedDeck.add(card)
                        }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                )

                DeckPanel(
                    deck = selectedDeck.toList(),
                    maxDeckSize = maxDeckSize,
                    onCardClick = { card ->
                        selectedDeck.remove(card)
                    },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                )
            }

            Button(
                onClick = {
                    onDeckUpdate(selectedDeck.toList())
                    onNavigateBack()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text(
                    "Confirm Deck (${selectedDeck.size}/$maxDeckSize)",
                    color = MaterialTheme.colorScheme.onPrimary
                )
            }
        }
    }
}

@Composable
fun LibraryPanel(
    library: List<Card>,
    selectedDeck: List<Card>,
    onCardClick: (Card) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .padding(8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(8.dp)
    ) {
        Text(
            "Library",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(library.take(20)) { card ->
                val isSelected = selectedDeck.contains(card)
                CardListItem(
                    card = card,
                    isSelectable = !isSelected,
                    onClick = { if (!isSelected) onCardClick(card) }
                )
            }
        }
    }
}

@Composable
fun DeckPanel(
    deck: List<Card>,
    maxDeckSize: Int,
    onCardClick: (Card) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .padding(8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f))
            .padding(8.dp)
    ) {
        Text(
            "Current Deck (${deck.size}/$maxDeckSize)",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        if (deck.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "Tap cards from library to add",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(deck) { card ->
                    CardListItem(
                        card = card,
                        isSelectable = true,
                        onClick = { onCardClick(card) },
                        showRemoveIndicator = true
                    )
                }
            }
        }
    }
}

@Composable
fun CardListItem(
    card: Card,
    isSelectable: Boolean,
    onClick: () -> Unit,
    showRemoveIndicator: Boolean = false
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(
                if (isSelectable) Color.White else Color.LightGray.copy(alpha = 0.5f)
            )
            .clickable(enabled = isSelectable) { onClick() }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(width = 32.dp, height = 45.dp)
                .shadow(2.dp, RoundedCornerShape(4.dp))
                .clip(RoundedCornerShape(4.dp))
                .background(Color.White)
                .border(1.dp, Color.LightGray, RoundedCornerShape(4.dp))
        )

        Spacer(modifier = Modifier.width(12.dp))

        Text(
            text = card.name,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isSelectable) MaterialTheme.colorScheme.onSurface else Color.Gray
        )

        Spacer(modifier = Modifier.weight(1f))

        if (showRemoveIndicator) {
            Text(
                text = "Remove",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}
