<p align="center">
  <img src="https://github.com/zyggy123/mod-duel-bet/blob/main/icon.png" width="200" />
</p>

# mod-duel-bet ⚔️💰

A lightweight and highly secure Lua module for **AzerothCore 3.3.5a** that allows players to wager gold on the outcome of their duels. 

## 📖 Description
This module enhances the PvP experience by allowing players to challenge others with a financial stake. Built using the Eluna/ALE Lua Engine, this modernized version features a **Database Escrow System** and an **In-Game Mail Recovery System** to guarantee that players will *never* lose their gold due to server crashes, "ALT+F4" rage-quits, or unexpected disconnections.

## 🌟 Features
- **100% Safe DB Escrow:** Wagered gold is safely tracked in the database to survive server restarts or crashes.
- **Mailbox Refunds:** If a player logs out or disconnects during a bet, their gold is safely returned to their in-game Mailbox.
- **Player Statistics:** Tracks total money duels, wins, and net profit for each player.
- **Anti-Exploit System:** Protects against fleeing or interrupting the duel to save bets.
- **Configurable Limits:** Easy-to-edit minimum and maximum bet amounts (`MIN_BET_GOLD`, `MAX_BET_GOLD`).
- **Gossip UI:** Targets receive a clean, native gossip menu to Accept or Decline the bet.
- **Anti-Spam:** Integrated cooldown system (`COOLDOWN_SECONDS`) for the command.

## 🛠️ Requirements
- **AzerothCore 3.3.5a**
- [mod-eluna](https://github.com/azerothcore/mod-eluna) or [mod-ale](https://github.com/azerothcore/mod-ale)

## 🚀 Installation
1. Execute the provided SQL code (table creation) into your **`acore_characters`** database.
2. Place the `duel_bet.lua` file inside your server's `lua_scripts` directory.
3. Restart your `worldserver` or use the `.reload eluna` command in-game.

## ⌨️ Commands
| Command | Argument | Description |
| :--- | :--- | :--- |
| `.duelbet` | `<amount>` | Challenge your target with a specific gold amount. |
| `.duelbet` | `cancel` | Cancel your current pending bet request and get refunded. |
| `.duelbet` | `stats` | View your personal duel betting statistics (matches, wins, net profit). |

*(Note: Accepting or Declining bets is handled interactively via the in-game Gossip Window).*

## ⚙️ Configuration
Open `duel_bet.lua` to modify these values:
```lua
local MIN_BET_GOLD = 1        -- Minimum allowed bet
local MAX_BET_GOLD = 100000   -- Maximum allowed bet
local COOLDOWN_SECONDS = 10   -- Cooldown between commands
