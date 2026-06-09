--[[
    Duel Bet Module for AzerothCore 3.3.5a (Eluna) Zyggy123 (https://github.com/zyggy123/mod-duel-bet)
    Optimized: DB Escrow, Mail Refund System, No Memory Leaks, Gossip Crash Fix.
]]

local MIN_BET_GOLD = 1
local MAX_BET_GOLD = 100000
local COOLDOWN_SECONDS = 10
local MENU_ID = 55555

local function ToCopper(gold)
    return gold * 10000
end

local function SendMsg(player, msg)
    if player then
        player:SendBroadcastMessage("|cff00ccff[Duel Bet]|r " .. msg)
    end
end

-- The function through which we return the money. If the player leaves the game, they are guaranteed to receive it via Mailbox.
local function SafeRefund(guidLow, copperAmount, reason, forceMail)
    local player = GetPlayerByGUID(guidLow)
    
    if player and player:IsInWorld() and not forceMail then
        player:ModifyMoney(copperAmount)
        SendMsg(player, "The bet was cancelled (" .. reason .. "). Your " .. (copperAmount/10000) .. " gold was refunded.")
    else
        local subject = "Duel Bet Refund"
        local body = "Your duel bet was cancelled: " .. reason .. ". Your " .. (copperAmount/10000) .. " gold has been safely refunded."
        SendMail("DuelBet System", body, guidLow, 0, 61, 0, copperAmount)
        
        if player then
            SendMsg(player, "The bet was cancelled. Since you are logging out, the gold was sent to your Mailbox.")
        end
    end
end

-- ==========================================
-- 1. COMAND .duelbet
-- ==========================================
local function OnDuelBetCommand(event, player, command)
    if not player then return end 
    
    local cmd, arg = command:match("^(%S+)%s*(.*)")
    if not cmd then cmd = command end
    cmd = cmd:lower()
    
    if cmd ~= "duelbet" then
        return
    end
    
    local pGuid = player:GetGUIDLow()
    
    -- STATS
    if arg == "stats" then
        local q = CharDBQuery("SELECT total_duels, total_won, total_profit FROM duel_bet_stats WHERE guid = " .. pGuid)
        if q then
            SendMsg(player, "Stats -> Matches: " .. q:GetUInt32(0) .. " | Wins: " .. q:GetUInt32(1) .. " | Net Profit: " .. (q:GetInt32(2) / 10000) .. " Gold")
        else
            SendMsg(player, "You haven't played any money duels yet.")
        end
        return false
    end

    -- CANCEL
    if arg == "cancel" then
        local q = CharDBQuery("SELECT id, player1_guid, player2_guid, amount, status FROM duel_bets WHERE player1_guid = " .. pGuid .. " OR player2_guid = " .. pGuid)
        if not q then
            SendMsg(player, "No active or pending bet to cancel.")
            return false
        end

        local betId = q:GetUInt32(0)
        local p1 = q:GetUInt32(1)
        local p2 = q:GetUInt32(2)
        local amt = q:GetUInt32(3)
        local status = q:GetUInt8(4)

        if status == 2 then
            SendMsg(player, "You cannot cancel a bet while a duel is in progress!")
            return false
        end

        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)

        if status == 0 then
            SafeRefund(p1, amt, "cancelled by challenger", false)
            local targetPlayer = GetPlayerByGUID(p2)
            if targetPlayer then 
                targetPlayer:GossipComplete() 
                SendMsg(targetPlayer, "The pending duel bet was cancelled.")
            end
        elseif status == 1 then
            SafeRefund(p1, amt, "cancelled manually", false)
            SafeRefund(p2, amt, "cancelled manually", false)
        end
        return false
    end
    
    -- INITIATE BET
    local playerName = player:GetName()
    
    -- We use GetData for Cooldown 
    local playerCooldown = player:GetData("DuelBetCooldown")
    if playerCooldown and playerCooldown > os.time() then
        SendMsg(player, "Please wait " .. (playerCooldown - os.time()) .. " seconds before sending another bet challenge.")
        return false
    end
    
    local amount = tonumber(arg)
    if not amount or amount < MIN_BET_GOLD or amount > MAX_BET_GOLD then
        SendMsg(player, "Usage: .duelbet <amount> (or .duelbet cancel / stats)")
        SendMsg(player, "Amount must be between " .. MIN_BET_GOLD .. " and " .. MAX_BET_GOLD .. " gold.")
        return false
    end
    
    local target = player:GetSelection()
    if not target or target:GetTypeId() ~= 4 or target == player then
        SendMsg(player, "You must select another player to bet with.")
        return false
    end
    
    local targetName = target:GetName()
    local tGuid = target:GetGUIDLow()
    
    local qCheck = CharDBQuery("SELECT id FROM duel_bets WHERE player1_guid = " .. pGuid .. " OR player2_guid = " .. pGuid .. " OR player1_guid = " .. tGuid .. " OR player2_guid = " .. tGuid)
    if qCheck then
        SendMsg(player, "One of you already has an active or pending bet! Type .duelbet cancel to remove it.")
        return false
    end
    
    local copperAmount = ToCopper(amount)
    if player:GetCoinage() < copperAmount then
        SendMsg(player, "You do not have enough gold!")
        return false
    end
    
    if target:GetCoinage() < copperAmount then
        SendMsg(player, targetName .. " does not have enough gold for this bet.")
        return false
    end
    
    --We set the clean Cooldown on the C++ player
    player:SetData("DuelBetCooldown", os.time() + COOLDOWN_SECONDS)
    
    player:ModifyMoney(-copperAmount)
    CharDBExecute("INSERT INTO duel_bets (player1_guid, player2_guid, amount, status) VALUES (" .. pGuid .. ", " .. tGuid .. ", " .. copperAmount .. ", 0)")
    
    SendMsg(player, "You have challenged " .. targetName .. " to a duel bet for " .. amount .. " gold.")
    SendMsg(target, playerName .. " has challenged you to a duel bet for " .. amount .. " gold!")
    
    target:GossipClearMenu()
    target:GossipMenuAddItem(0, "Accept Duel Bet (" .. amount .. " gold)", 0, 1, false, "Are you sure you want to accept the bet and lock in " .. amount .. " gold?")
    target:GossipMenuAddItem(0, "Decline", 0, 2)
    target:GossipSendMenu(1, target, MENU_ID)
    
    return false
end

-- ==========================================
-- 2. GOSSIP SELECT
-- ==========================================
local function OnGossipSelect(event, player, object, sender, intid, code)
    local tGuid = player:GetGUIDLow()

    local q = CharDBQuery("SELECT id, player1_guid, amount FROM duel_bets WHERE player2_guid = " .. tGuid .. " AND status = 0")
    
    if not q then
        SendMsg(player, "This bet challenge has expired or is invalid.")
        player:GossipComplete()
        return
    end

    local betId = q:GetUInt32(0)
    local pGuid = q:GetUInt32(1)
    local copperAmount = q:GetUInt32(2)

    if intid == 2 then -- DECLINE
        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)
        SafeRefund(pGuid, copperAmount, "declined by opponent", false)
        SendMsg(player, "You declined the duel bet.")
        player:GossipComplete()
        return
    end
    
    if intid == 1 then -- ACCEPT
        if player:GetCoinage() < copperAmount then
            SendMsg(player, "You don't have enough gold to accept.")
            CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)
            SafeRefund(pGuid, copperAmount, "opponent didn't have enough gold", false)
            player:GossipComplete()
            return
        end
        
        player:ModifyMoney(-copperAmount)
        CharDBExecute("UPDATE duel_bets SET status = 1 WHERE id = " .. betId)
        
        SendMsg(player, "Duel bet accepted! Both players locked in " .. (copperAmount/10000) .. " gold. Start the duel!")
        
        local challenger = GetPlayerByGUID(pGuid)
        if challenger then
            SendMsg(challenger, "Duel bet accepted! Both players locked in " .. (copperAmount/10000) .. " gold. Start the duel!")
        end
        player:GossipComplete()
    end
end

-- ==========================================
-- 3. BEGINNING OF THE DUEL
-- ==========================================
local function OnDuelStart(event, player1, player2)
    local guid1 = player1:GetGUIDLow()
    local guid2 = player2:GetGUIDLow()

    local q = CharDBQuery("SELECT id, amount FROM duel_bets WHERE status = 1 AND ((player1_guid = " .. guid1 .. " AND player2_guid = " .. guid2 .. ") OR (player1_guid = " .. guid2 .. " AND player2_guid = " .. guid1 .. "))")
    
    if q then
        local betId = q:GetUInt32(0)
        CharDBExecute("UPDATE duel_bets SET status = 2 WHERE id = " .. betId)
        
        local amountGold = q:GetUInt32(1) / 10000
        SendMsg(player1, "The duel has started! Your bet of " .. amountGold .. " gold is locked in.")
        SendMsg(player2, "The duel has started! Your bet of " .. amountGold .. " gold is locked in.")
    end
end

-- ==========================================
-- 4. DUEL COMPLETION
-- ==========================================
local function OnDuelEnd(event, winner, loser, type)
    if not winner or not loser then return end
    
    local wGuid = winner:GetGUIDLow()
    local lGuid = loser:GetGUIDLow()

    local q = CharDBQuery("SELECT id, amount FROM duel_bets WHERE status = 2 AND ((player1_guid = " .. wGuid .. " AND player2_guid = " .. lGuid .. ") OR (player1_guid = " .. lGuid .. " AND player2_guid = " .. wGuid .. "))")
    
    if q then
        local betId = q:GetUInt32(0)
        local amountCopper = q:GetUInt32(1)
        local totalPrize = amountCopper * 2
        
        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)

        if type == 1 then -- DUEL_WON
            winner:ModifyMoney(totalPrize)
            SendMsg(winner, "You won the duel! You receive " .. (totalPrize/10000) .. " gold.")
            SendMsg(loser, "You lost the duel bet and " .. (amountCopper/10000) .. " gold.")

            CharDBExecute("INSERT INTO duel_bet_stats (guid, total_duels, total_won, total_profit) VALUES (" .. wGuid .. ", 1, 1, " .. amountCopper .. ") ON DUPLICATE KEY UPDATE total_duels = total_duels + 1, total_won = total_won + 1, total_profit = total_profit + " .. amountCopper)
            CharDBExecute("INSERT INTO duel_bet_stats (guid, total_duels, total_won, total_profit) VALUES (" .. lGuid .. ", 1, 0, -" .. amountCopper .. ") ON DUPLICATE KEY UPDATE total_duels = total_duels + 1, total_profit = total_profit - " .. amountCopper)
        else
            SafeRefund(wGuid, amountCopper, "duel interrupted", false)
            SafeRefund(lGuid, amountCopper, "duel interrupted", false)
        end
    end
end

-- ==========================================
-- 5. LOGOUT/CRASH RECOVERY (Forced Mail)
-- ==========================================
local function OnPlayerLogout(event, player)
    local guid = player:GetGUIDLow()
    
    local q = CharDBQuery("SELECT id, player1_guid, player2_guid, amount, status FROM duel_bets WHERE player1_guid = " .. guid .. " OR player2_guid = " .. guid)
    if q then
        repeat
            local betId = q:GetUInt32(0)
            local p1 = q:GetUInt32(1)
            local p2 = q:GetUInt32(2)
            local amount = q:GetUInt32(3)
            local status = q:GetUInt8(4)

            CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)

            if status == 0 then
                SafeRefund(p1, amount, "player logged out", (p1 == guid))
            elseif status >= 1 then
                SafeRefund(p1, amount, "player logged out (abandoned)", (p1 == guid))
                SafeRefund(p2, amount, "player logged out (abandoned)", (p2 == guid))
            end
        until not q:NextRow()
    end
end

-- Event Registrations
RegisterPlayerEvent(42, OnDuelBetCommand)
RegisterPlayerEvent(10, OnDuelStart)
RegisterPlayerEvent(11, OnDuelEnd)
RegisterPlayerEvent(4, OnPlayerLogout)
RegisterPlayerGossipEvent(MENU_ID, 2, OnGossipSelect)
