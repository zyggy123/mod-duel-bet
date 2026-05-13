# mod-duel-bet ⚔️💰

A lightweight Lua module for **AzerothCore 3.3.5a** that allows players to wager gold on the outcome of their duels. 

## 📖 Description
This module enhances the PvP experience by allowing players to challenge others with a financial stake. It is built using the Eluna/ALE Lua Engine and features a robust refund system to prevent gold loss due to technicalities.

## 🌟 Features
- **Configurable Limits:** Easy-to-edit minimum and maximum bet amounts (`MIN_BET_GOLD`, `MAX_BET_GOLD`).
- **Gossip UI:** Targets receive a professional gossip menu to Accept or Decline the bet.
- **Anti-Spam:** Integrated cooldown system (`COOLDOWN_SECONDS`) for the command.
- **Fail-Safe Refunds:** - Automatic refund if the duel is interrupted (e.g., player flees).
  - Automatic refund if a player logs out while a bet is active.
  - Manual cancellation of pending bets.
- **Broadcast Notifications:** Real-time feedback for all betting actions.

## 🛠️ Requirements
- **AzerothCore 3.3.5a**
- [mod-eluna](https://github.com/azerothcore/mod-eluna) or [mod-ale](https://github.com/azerothcore/mod-ale)

## 🚀 Installation
1. Ensure your core is compiled with a Lua Engine module.
2. Place the `duel_bet.lua` file inside your server's `lua_scripts` directory.
3. Restart your `worldserver` or use `.eluna reload` in-game.

## ⌨️ Commands
| Command | Argument | Description |
| :--- | :--- | :--- |
| `.duelbet` | `<amount>` | Challenge your target with a gold amount. |
| `.duelbet` | `cancel` | Cancel your current pending bet request. |

## ⚙️ Configuration
Open `duel_bet.lua` to modify these values:
```lua
local MIN_BET_GOLD = 1        -- Minimum allowed bet
local MAX_BET_GOLD = 100000   -- Maximum allowed bet
local COOLDOWN_SECONDS = 10   -- Cooldown between commands
