package com.android.ampulos.data

object CardLibrary {
    private val cards = mutableListOf<Card>()

    init {
        // 初始化示例卡片数据
        cards.addAll(
            listOf(
                Card(id = "001", name = "Warrior", type = "Attack", attack = 5, defense = 3, description = "A brave warrior"),
                Card(id = "002", name = "Mage", type = "Magic", attack = 4, defense = 2, description = "A powerful mage"),
                Card(id = "003", name = "Guardian", type = "Defense", attack = 2, defense = 6, description = "A sturdy guardian"),
                Card(id = "004", name = "Archer", type = "Attack", attack = 4, defense = 2, description = "A skilled archer"),
                Card(id = "005", name = "Healer", type = "Support", attack = 1, defense = 3, description = "A healing support"),
                Card(id = "006", name = "Assassin", type = "Attack", attack = 6, defense = 1, description = "A stealthy assassin"),
                Card(id = "007", name = "Knight", type = "Defense", attack = 3, defense = 5, description = "A noble knight"),
                Card(id = "008", name = "Wizard", type = "Magic", attack = 5, defense = 2, description = "A wise wizard"),
                Card(id = "009", name = "Rogue", type = "Attack", attack = 4, defense = 2, description = "A cunning rogue"),
                Card(id = "010", name = "Paladin", type = "Defense", attack = 3, defense = 5, description = "A holy paladin"),
                Card(id = "011", name = "Necromancer", type = "Magic", attack = 4, defense = 2, description = "A dark necromancer"),
                Card(id = "012", name = "Ranger", type = "Attack", attack = 4, defense = 3, description = "A forest ranger"),
                Card(id = "013", name = "Priest", type = "Support", attack = 2, defense = 3, description = "A devout priest"),
                Card(id = "014", name = "Berserker", type = "Attack", attack = 7, defense = 1, description = "A fierce berserker"),
                Card(id = "015", name = "Monk", type = "Defense", attack = 2, defense = 4, description = "A peaceful monk"),
                Card(id = "016", name = "Druid", type = "Magic", attack = 3, defense = 3, description = "A nature druid"),
                Card(id = "017", name = "Warlock", type = "Magic", attack = 5, defense = 2, description = "A dark warlock"),
                Card(id = "018", name = "Samurai", type = "Attack", attack = 5, defense = 3, description = "A honorable samurai"),
                Card(id = "019", name = "Valkyrie", type = "Defense", attack = 3, defense = 5, description = "A divine valkyrie"),
                Card(id = "020", name = "Summoner", type = "Magic", attack = 4, defense = 2, description = "A mystical summoner")
            )
        )
    }

    fun getAllCards(): List<Card> = cards.toList()

    fun getCardById(id: String): Card? = cards.find { it.id == id }

    fun addCard(card: Card) {
        if (!cards.contains(card)) {
            cards.add(card)
        }
    }

    fun removeCard(card: Card) {
        cards.remove(card)
    }
}