--[[
    Duel Bet Module for AzerothCore 3.3.5a (Eluna)
    Allows players to bet gold on the outcome of a duel.
]]

local MIN_BET_GOLD = 1
local MAX_BET_GOLD = 100000
local COOLDOWN_SECONDS = 10
local MENU_ID = 55555

local pendingBets = {}
local activeBets = {}
local cooldowns = {}

local function ToCopper(gold)
    return gold * 10000
end

local function SendMsg(player, msg)
    player:SendBroadcastMessage("|cff00ccff[Duel Bet]|r " .. msg)
end

-- Command Hook
local function OnDuelBetCommand(event, player, command)
    if not player then return end -- ignore console
    
    local cmd, arg = command:match("^(%S+)%s*(.*)")
    if not cmd then cmd = command end
    cmd = cmd:lower()
    
    if cmd ~= "duelbet" then
        return
    end
    
    local playerName = player:GetName()
    
    if arg == "cancel" then
        if pendingBets[playerName] then
            local pTarget = GetPlayerByName(pendingBets[playerName].target)
            if pTarget then
                SendMsg(pTarget, playerName .. " has cancelled their pending duel bet.")
                pTarget:GossipComplete() -- Close gossip if it's open
            end
            SendMsg(player, "You cancelled your pending duel bet.")
            pendingBets[playerName] = nil
        end
        
        if activeBets[playerName] and not activeBets[playerName].inDuel then
            local betInfo = activeBets[playerName]
            local opponentName = betInfo.opponent
            local amount = betInfo.amount
            
            local opponent = GetPlayerByName(opponentName)
            player:ModifyMoney(ToCopper(amount))
            if opponent then
                opponent:ModifyMoney(ToCopper(amount))
                SendMsg(opponent, playerName .. " has cancelled the active duel bet. Your " .. amount .. " gold has been refunded.")
            else
                -- If offline, use DB
                local accountId = GetAccountIdByName(opponentName)
                if accountId then
                    CharDBExecute("UPDATE characters SET money = money + " .. ToCopper(amount) .. " WHERE name = '" .. opponentName .. "'")
                end
            end
            SendMsg(player, "You cancelled the active duel bet. Your " .. amount .. " gold has been refunded.")
            
            activeBets[playerName] = nil
            activeBets[opponentName] = nil
        elseif activeBets[playerName] and activeBets[playerName].inDuel then
            SendMsg(player, "You cannot cancel a bet while a duel is in progress!")
        elseif not pendingBets[playerName] and not activeBets[playerName] then
            SendMsg(player, "No active or pending bet to cancel.")
        end
        return false -- block normal command execution
    end
    
    -- Check cooldown for sending challenges
    if cooldowns[playerName] and cooldowns[playerName] > os.time() then
        SendMsg(player, "Please wait " .. (cooldowns[playerName] - os.time()) .. " seconds before sending another bet challenge.")
        return false
    end
    
    local amount = tonumber(arg)
    if not amount or amount < MIN_BET_GOLD or amount > MAX_BET_GOLD then
        SendMsg(player, "Usage: .duelbet <amount> (or .duelbet cancel)")
        SendMsg(player, "Amount must be between " .. MIN_BET_GOLD .. " and " .. MAX_BET_GOLD .. " gold.")
        return false
    end
    
    local target = player:GetSelection()
    if not target or target:GetTypeId() ~= 4 or target == player then
        SendMsg(player, "You must select another player to bet with.")
        return false
    end
    
    local targetName = target:GetName()
    
    if activeBets[playerName] then
        SendMsg(player, "You already have an active bet! Type .duelbet cancel to remove it.")
        return false
    end
    if activeBets[targetName] then
        SendMsg(player, "That player already has an active bet.")
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
    
    -- Update cooldown
    cooldowns[playerName] = os.time() + COOLDOWN_SECONDS
    
    -- Set pending bet
    pendingBets[playerName] = { target = targetName, amount = amount }
    
    SendMsg(player, "You have challenged " .. targetName .. " to a duel bet for " .. amount .. " gold.")
    SendMsg(target, playerName .. " has challenged you to a duel bet for " .. amount .. " gold!")
    
    -- Open Gossip Menu on the target
    -- We pass 'target' as the object to GossipSendMenu so the client allows the interaction
    target:GossipClearMenu()
    target:GossipMenuAddItem(0, "Accept Duel Bet (" .. amount .. " gold)", 0, 1, false, "Are you sure you want to accept the bet and lock in " .. amount .. " gold?")
    target:GossipMenuAddItem(0, "Decline", 0, 2)
    target:GossipSendMenu(1, target, MENU_ID)
    
    return false
end

-- Gossip Select Hook
local function OnGossipSelect(event, player, object, sender, intid, code, menu_id)
    local targetName = player:GetName()
    local challengerName = nil
    
    -- Find who challenged this player
    for cName, bet in pairs(pendingBets) do
        if bet.target == targetName then
            challengerName = cName
            break
        end
    end
    
    if not challengerName then
        SendMsg(player, "This bet challenge has expired or is invalid.")
        player:GossipComplete()
        return
    end
    
    local challenger = GetPlayerByName(challengerName)
    if not challenger then
        SendMsg(player, "The challenger is no longer online.")
        pendingBets[challengerName] = nil
        player:GossipComplete()
        return
    end
    
    if intid == 2 then -- Decline
        SendMsg(player, "You declined the duel bet.")
        SendMsg(challenger, targetName .. " has declined your duel bet.")
        pendingBets[challengerName] = nil
        player:GossipComplete()
        return
    end
    
    if intid == 1 then -- Accept
        local amount = pendingBets[challengerName].amount
        local copperAmount = ToCopper(amount)
        
        if player:GetCoinage() < copperAmount then
            SendMsg(player, "You don't have enough gold to accept.")
            SendMsg(challenger, targetName .. " doesn't have enough gold to accept.")
            pendingBets[challengerName] = nil
            player:GossipComplete()
            return
        end
        
        if challenger:GetCoinage() < copperAmount then
            SendMsg(player, challengerName .. " no longer has enough gold.")
            SendMsg(challenger, "You no longer have enough gold for the bet.")
            pendingBets[challengerName] = nil
            player:GossipComplete()
            return
        end
        
        if activeBets[targetName] or activeBets[challengerName] then
            SendMsg(player, "One of you already has an active bet.")
            SendMsg(challenger, "One of you already has an active bet.")
            player:GossipComplete()
            return
        end
        
        -- Deduct money
        player:ModifyMoney(-copperAmount)
        challenger:ModifyMoney(-copperAmount)
        
        activeBets[challengerName] = { opponent = targetName, amount = amount, inDuel = false }
        activeBets[targetName] = { opponent = challengerName, amount = amount, inDuel = false }
        
        pendingBets[challengerName] = nil
        
        SendMsg(player, "Duel bet accepted! You and " .. challengerName .. " have both put in " .. amount .. " gold. The winner takes it all!")
        SendMsg(challenger, "Duel bet accepted! You and " .. targetName .. " have both put in " .. amount .. " gold. The winner takes it all!")
        player:GossipComplete()
    end
end

local function OnDuelStart(event, player1, player2)
    local name1 = player1:GetName()
    local name2 = player2:GetName()
    
    if activeBets[name1] and activeBets[name1].opponent == name2 then
        activeBets[name1].inDuel = true
        activeBets[name2].inDuel = true
        SendMsg(player1, "The duel has started! Your bet of " .. activeBets[name1].amount .. " gold is locked in.")
        SendMsg(player2, "The duel has started! Your bet of " .. activeBets[name2].amount .. " gold is locked in.")
    end
end

local function OnDuelEnd(event, winner, loser, type)
    if not winner or not loser then return end
    
    local winnerName = winner:GetName()
    local loserName = loser:GetName()
    
    if activeBets[winnerName] and activeBets[winnerName].opponent == loserName then
        local amount = activeBets[winnerName].amount
        local totalPrize = ToCopper(amount * 2)
        
        if type == 1 then -- 1 is DUEL_WON, 0 is DUEL_INTERRUPTED, 2 is DUEL_FLED
            winner:ModifyMoney(totalPrize)
            SendMsg(winner, "You won the duel! You receive " .. (amount * 2) .. " gold.")
            SendMsg(loser, "You lost the duel bet and " .. amount .. " gold.")
        else
            winner:ModifyMoney(ToCopper(amount))
            loser:ModifyMoney(ToCopper(amount))
            SendMsg(winner, "The duel was interrupted! Your bet of " .. amount .. " gold has been refunded.")
            SendMsg(loser, "The duel was interrupted! Your bet of " .. amount .. " gold has been refunded.")
        end
        
        activeBets[winnerName] = nil
        activeBets[loserName] = nil
    end
end

local function OnPlayerLogout(event, player)
    local playerName = player:GetName()
    
    if pendingBets[playerName] then
        pendingBets[playerName] = nil
    end
    
    if activeBets[playerName] then
        local opponentName = activeBets[playerName].opponent
        local amount = activeBets[playerName].amount
        
        player:ModifyMoney(ToCopper(amount))
        
        local opponent = GetPlayerByName(opponentName)
        if opponent then
            opponent:ModifyMoney(ToCopper(amount))
            SendMsg(opponent, playerName .. " has logged out. Your duel bet has been cancelled and refunded.")
        else
            CharDBExecute("UPDATE characters SET money = money + " .. ToCopper(amount) .. " WHERE name = '" .. opponentName .. "'")
        end
        
        activeBets[playerName] = nil
        activeBets[opponentName] = nil
    end
end

RegisterPlayerEvent(42, OnDuelBetCommand)
RegisterPlayerEvent(10, OnDuelStart)
RegisterPlayerEvent(11, OnDuelEnd)
RegisterPlayerEvent(4, OnPlayerLogout)
RegisterPlayerGossipEvent(MENU_ID, 2, OnGossipSelect)
