package com.android.ampulos.ui.screens

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.android.ampulos.data.Card
import com.android.ampulos.data.CardLibrary
import com.android.ampulos.ui.components.GameCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeckConfigScreen(
    currentDeck: List<Card>,
    onDeckUpdate: (List<Card>) -> Unit,
    onNavigateBack: () -> Unit
) {
    val library = remember { CardLibrary.getAllCards() }
    val selectedDeck = remember { mutableStateListOf<Card>() }
    var animatingCard by remember { mutableStateOf<Card?>(null) }
    var animatingToRight by remember { mutableStateOf(true) }

    selectedDeck.clear()
    selectedDeck.addAll(currentDeck)

    val maxDeckSize = 20

    fun addCardToDeck(card: Card) {
        if (selectedDeck.size < maxDeckSize && !selectedDeck.contains(card)) {
            animatingCard = card
            animatingToRight = true
            selectedDeck.add(card)
        }
    }

    fun removeCardFromDeck(card: Card) {
        animatingCard = card
        animatingToRight = false
        selectedDeck.remove(card)
    }

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
                            addCardToDeck(card)
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
                        removeCardFromDeck(card)
                    },
                    animatingCard = animatingCard,
                    animatingToRight = animatingToRight,
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
    animatingCard: Card?,
    animatingToRight: Boolean,
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