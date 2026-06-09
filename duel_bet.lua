--[[
    Duel Bet Module for AzerothCore 3.3.5a (Eluna)
    Zyggy123 (https://github.com/zyggy123/mod-duel-bet)
    
    Optimized: DB Escrow, Mail Refund, Zero-Query Combat Hooks (RAM Stored)
]]

local MIN_BET_GOLD = 1
local MAX_BET_GOLD = 100000
local COOLDOWN_SECONDS = 10
local MENU_ID = 59321 -- Changed to avoid ID collisions

local function ToCopper(gold)
    return gold * 10000
end

local function SendMsg(player, msg)
    if player then
        player:SendBroadcastMessage("|cff00ccff[Duel Bet]|r " .. msg)
    end
end

-- Function to safely refund gold. If the player logs out or crashes, they are guaranteed to receive it via Mailbox.
local function SafeRefund(guidLow, copperAmount, reason, forceMail)
    local player = GetPlayerByGUID(guidLow)
    
    if player and player:IsInWorld() and not forceMail then
        player:ModifyMoney(copperAmount)
        SendMsg(player, "The bet was cancelled (" .. reason .. "). Your " .. (copperAmount/10000) .. " gold was refunded.")
        player:SetData("DuelBet_ID", nil)
        player:SetData("DuelBet_Amount", nil)
    else
        local body = "Your duel bet was cancelled: " .. reason .. ". Your " .. (copperAmount/10000) .. " gold has been safely refunded."
        SendMail("DuelBet System", body, guidLow, 0, 61, 0, copperAmount)
        if player then
            SendMsg(player, "The bet was cancelled. Since you are logging out, the gold was sent to your Mailbox.")
        end
    end
end

-- ==========================================
-- 1. COMMAND: .duelbet
-- ==========================================
local function OnDuelBetCommand(event, player, command)
    if not player then return end 
    local cmd, arg = command:match("^(%S+)%s*(.*)")
    if not cmd then cmd = command end
    cmd = cmd:lower()
    
    if cmd ~= "duelbet" then return end
    
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

        local betId, p1, p2, amt, status = q:GetUInt32(0), q:GetUInt32(1), q:GetUInt32(2), q:GetUInt32(3), q:GetUInt8(4)

        if status == 2 then
            SendMsg(player, "You cannot cancel a bet while a duel is in progress!")
            return false
        end

        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)

        if status == 0 then
            SafeRefund(p1, amt, "cancelled by challenger", false)
            local targetPlayer = GetPlayerByGUID(p2)
            if targetPlayer then targetPlayer:GossipComplete(); SendMsg(targetPlayer, "The pending duel bet was cancelled.") end
        elseif status == 1 then
            SafeRefund(p1, amt, "cancelled manually", false)
            SafeRefund(p2, amt, "cancelled manually", false)
        end
        return false
    end
    
    -- INITIATE BET
    local playerName = player:GetName()
    
    -- Use GetData for Cooldown to prevent memory leaks
    local playerCooldown = player:GetData("DuelBetCooldown")
    if playerCooldown and playerCooldown > os.time() then
        SendMsg(player, "Please wait " .. (playerCooldown - os.time()) .. " seconds.")
        return false
    end
    
    local amount = tonumber(arg)
    if not amount or amount < MIN_BET_GOLD or amount > MAX_BET_GOLD then
        SendMsg(player, "Usage: .duelbet <amount> (or .duelbet cancel / stats)")
        return false
    end
    
    local target = player:GetSelection()
    if not target or target:GetTypeId() ~= 4 or target == player then
        SendMsg(player, "You must select another player to bet with.")
        return false
    end
    
    local tGuid = target:GetGUIDLow()
    local qCheck = CharDBQuery("SELECT id FROM duel_bets WHERE player1_guid = " .. pGuid .. " OR player2_guid = " .. pGuid .. " OR player1_guid = " .. tGuid .. " OR player2_guid = " .. tGuid)
    if qCheck then
        SendMsg(player, "One of you already has an active or pending bet!")
        return false
    end
    
    local copperAmount = ToCopper(amount)
    if player:GetCoinage() < copperAmount then SendMsg(player, "You do not have enough gold!"); return false end
    if target:GetCoinage() < copperAmount then SendMsg(player, target:GetName() .. " does not have enough gold."); return false end
    
    -- Set a clean Cooldown directly on the player object in RAM
    player:SetData("DuelBetCooldown", os.time() + COOLDOWN_SECONDS)
    player:ModifyMoney(-copperAmount)
    CharDBExecute("INSERT INTO duel_bets (player1_guid, player2_guid, amount, status) VALUES (" .. pGuid .. ", " .. tGuid .. ", " .. copperAmount .. ", 0)")
    
    SendMsg(player, "Challenged " .. target:GetName() .. " for " .. amount .. " gold.")
    SendMsg(target, player:GetName() .. " challenged you for " .. amount .. " gold!")
    
    target:GossipClearMenu()
    target:GossipMenuAddItem(0, "Accept Duel Bet (" .. amount .. " gold)", 0, 1, false, "Accept and lock in " .. amount .. " gold?")
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
        SendMsg(player, "This bet has expired or is invalid."); player:GossipComplete(); return
    end

    local betId, pGuid, copperAmount = q:GetUInt32(0), q:GetUInt32(1), q:GetUInt32(2)

    -- DECLINE
    if intid == 2 then 
        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)
        SafeRefund(pGuid, copperAmount, "declined by opponent", false)
        SendMsg(player, "You declined the bet."); player:GossipComplete(); return
    end
    
    -- ACCEPT
    if intid == 1 then
        if player:GetCoinage() < copperAmount then
            CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)
            SafeRefund(pGuid, copperAmount, "opponent didn't have enough gold", false)
            SendMsg(player, "You don't have enough gold."); player:GossipComplete(); return
        end
        
        player:ModifyMoney(-copperAmount)
        CharDBExecute("UPDATE duel_bets SET status = 1 WHERE id = " .. betId)
        
        -- RAM OPTIMIZATION: Save details to memory to avoid SQL queries during combat!
        player:SetData("DuelBet_ID", betId)
        player:SetData("DuelBet_Amount", copperAmount)
        
        local challenger = GetPlayerByGUID(pGuid)
        if challenger then
            challenger:SetData("DuelBet_ID", betId)
            challenger:SetData("DuelBet_Amount", copperAmount)
            SendMsg(challenger, "Bet accepted! Both locked " .. (copperAmount/10000) .. " gold. Start the duel!")
        end
        
        SendMsg(player, "Bet accepted! Both locked " .. (copperAmount/10000) .. " gold. Start the duel!")
        player:GossipComplete()
    end
end

-- ==========================================
-- 3. DUEL START (0 SQL Queries)
-- ==========================================
local function OnDuelStart(event, player1, player2)
    local betId1 = player1:GetData("DuelBet_ID")
    local betId2 = player2:GetData("DuelBet_ID")

    -- Check strictly from RAM if both players share an active bet
    if betId1 and betId1 == betId2 then
        CharDBExecute("UPDATE duel_bets SET status = 2 WHERE id = " .. betId1)
        local amountGold = player1:GetData("DuelBet_Amount") / 10000
        SendMsg(player1, "Duel started! Your " .. amountGold .. " gold is locked in.")
        SendMsg(player2, "Duel started! Your " .. amountGold .. " gold is locked in.")
    end
end

-- ==========================================
-- 4. DUEL END (Zero Scans, 1 Delete Query)
-- ==========================================
local function OnDuelEnd(event, winner, loser, type)
    if not winner or not loser then return end
    
    local betId = winner:GetData("DuelBet_ID")
    if betId and betId == loser:GetData("DuelBet_ID") then
        local amountCopper = winner:GetData("DuelBet_Amount")
        local totalPrize = amountCopper * 2
        
        CharDBExecute("DELETE FROM duel_bets WHERE id = " .. betId)

        -- DUEL_WON
        if type == 1 then 
            local wGuid, lGuid = winner:GetGUIDLow(), loser:GetGUIDLow()
            winner:ModifyMoney(totalPrize)
            SendMsg(winner, "You won! You receive " .. (totalPrize/10000) .. " gold.")
            SendMsg(loser, "You lost " .. (amountCopper/10000) .. " gold.")

            CharDBExecute("INSERT INTO duel_bet_stats (guid, total_duels, total_won, total_profit) VALUES (" .. wGuid .. ", 1, 1, " .. amountCopper .. ") ON DUPLICATE KEY UPDATE total_duels = total_duels + 1, total_won = total_won + 1, total_profit = total_profit + " .. amountCopper)
            CharDBExecute("INSERT INTO duel_bet_stats (guid, total_duels, total_won, total_profit) VALUES (" .. lGuid .. ", 1, 0, -" .. amountCopper .. ") ON DUPLICATE KEY UPDATE total_duels = total_duels + 1, total_profit = total_profit - " .. amountCopper)
        else
            SafeRefund(winner:GetGUIDLow(), amountCopper, "duel interrupted", false)
            SafeRefund(loser:GetGUIDLow(), amountCopper, "duel interrupted", false)
        end
        
        -- Clear RAM data
        winner:SetData("DuelBet_ID", nil)
        winner:SetData("DuelBet_Amount", nil)
        loser:SetData("DuelBet_ID", nil)
        loser:SetData("DuelBet_Amount", nil)
    end
end

-- ==========================================
-- 5. LOGOUT/CRASH RECOVERY
-- ==========================================
local function OnPlayerLogout(event, player)
    local guid = player:GetGUIDLow()
    local q = CharDBQuery("SELECT id, player1_guid, player2_guid, amount, status FROM duel_bets WHERE player1_guid = " .. guid .. " OR player2_guid = " .. guid)
    
    if q then
        repeat
            local betId, p1, p2, amount, status = q:GetUInt32(0), q:GetUInt32(1), q:GetUInt32(2), q:GetUInt32(3), q:GetUInt8(4)
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

-- ==========================================
-- Event Registrations
-- ==========================================
RegisterPlayerEvent(42, OnDuelBetCommand)
RegisterPlayerEvent(10, OnDuelStart)
RegisterPlayerEvent(11, OnDuelEnd)
RegisterPlayerEvent(4, OnPlayerLogout)
RegisterPlayerGossipEvent(MENU_ID, 2, OnGossipSelect)
