require "PlayerProgressServer"
require "PlayerTierHandler"
require "ServerPointsShared"

PlayerProgressHandler = {}

-- Function to get the progress data from the client
function PlayerProgressHandler.getProgress(player)
    local progress = {
        Traits = {},
        Perks = {},
        Boosts = {},
        Recipes = {},
        ModData = {},
        Weight = player:getNutrition():getWeight()
    }

    -- Get traits
    local traits = player:getTraits()
    for i = 0, traits:size() - 1 do
        table.insert(progress.Traits, traits:get(i))
    end

    -- Get XP and perks
    local playerXp = player:getXp()
    for i = 0, PerkFactory.PerkList:size() - 1 do
        local perk = PerkFactory.PerkList:get(i)
        local perkName = perk:getName()
        local xp = playerXp:getXP(perk)
        progress.Perks[perkName] = xp
        local boost = playerXp:getPerkBoost(perk)
        if boost > 0 then
            progress.Boosts[perkName] = boost
        end
    end

    -- Get known recipes
    local recipes = player:getKnownRecipes()
    for i = 0, recipes:size() - 1 do
        table.insert(progress.Recipes, recipes:get(i))
    end

    -- Get mod data
    local modData = player:getModData()
    for key, val in pairs(modData) do
        progress.ModData[key] = val
    end

    print("[ZM_SecondChance] Progress data collected for player: " .. player:getUsername())
    return progress
end

-- Function to request the server to save progress
function PlayerProgressHandler.requestSaveProgress(username, progress)
    local player = getPlayer()
    if not player then
        print("[ZM_SecondChance] Player not found.")
        return
    end
    print("[ZM_SecondChance] Requesting server to save progress for user: " .. username)
    sendClientCommand(player, "PlayerProgressServer", "saveProgress", { username = username, progress = progress })
    print("[ZM_SecondChance] Requesting directly using server function ...")
    PlayerProgressServer.handleClientSaveProgress(username, progress)
end

-- Function to transfer progress data from one username to another
function PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
    print("[ZM_SecondChance] Requesting server to load progress for user: " .. oldUsername)
    -- Request the server to load the progress data for the old username
    sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

    -- Register a callback to handle the server response
    Events.OnServerCommand.Add(function(module, command, args)
        print("[ZM_SecondChance] Received server command: " .. command .. " from module: " .. module)
        if module == "PlayerProgressServer" and command == "loadProgressResponse" then
            local progress = args.progress
            if not progress then
                print("[ZM_SecondChance] No progress data found for user: " .. oldUsername)
                return
            end

            print("[ZM_SecondChance] Transferring progress from " .. oldUsername .. " to new player.")

            -- Transfer traits
            -- sendClientCommand(newPlayer, "PlayerProgressServer", "applyTraits", { traits = progress.Traits })
            PlayerProgressServer.handleClientLoadProgress(newPlayer, progress.Traits)

            -- Transfer XP and perks
            local playerXp = newPlayer:getXp()
            for perkName, xp in pairs(progress.Perks) do
                local perk = PerkFactory.getPerkFromName(perkName)
                if perk then
                    newPlayer:level0(perk)
                    if perk == Perks.Strength or perk == Perks.Fitness then
                        local b = true
                        local bXp = tonumber(xp) -- Convert xp to number
                        while b do
                            local nextLevel = newPlayer:getPerkLevel(perk) + 1
                            local nextLevelXp = perk:getXpForLevel(nextLevel)
                            if bXp >= nextLevelXp then
                                bXp = bXp - nextLevelXp
                                newPlayer:LevelPerk(perk)
                                luautils.updatePerksXp(perk, newPlayer)
                            else
                                b = false
                                local success, err = pcall(function()
                                    playerXp:AddXP(perk, bXp, false, false, true)
                                end)
                                if not success then
                                    print("[ZM_SecondChance] Error adding XP to perk: " .. tostring(err))
                                end
                            end
                        end
                    else
                        local success, err = pcall(function()
                            playerXp:AddXP(perk, tonumber(xp), false, false, true) -- Convert xp to number
                        end)
                        if not success then
                            print("[ZM_SecondChance] Error adding XP to perk: " .. tostring(err))
                        end
                        luautils.updatePerksXp(perk, newPlayer)
                    end

                    if progress.Boosts[perkName] then
                        local boost = tonumber(progress.Boosts[perkName]) -- Convert boost to number
                        if boost > 0 then
                            local success, err = pcall(function()
                                newPlayer:getXp():setPerkBoost(perk, boost)
                            end)
                            if not success then
                                print("[ZM_SecondChance] Error setting perk boost: " .. tostring(err))
                            end
                        end
                    end
                else
                    print("[ZM_SecondChance] Invalid perk: " .. perkName)
                end
            end

            -- Transfer known recipes
            local success, err = pcall(function()
                local recipes = newPlayer:getKnownRecipes()
                for _, recipe in ipairs(progress.Recipes) do
                    recipes:add(recipe)
                end
            end)
            if not success then
                print("[ZM_SecondChance] Error transferring known recipes: " .. tostring(err))
            end

            -- DO NOT Transfer mod data
            -- local success, err = pcall(function()
            --     local modData = newPlayer:getModData()
            --     for key, val in pairs(progress.ModData) do
            --         modData[key] = val
            --     end
            -- end)
            -- if not success then
            --     print("[ZM_SecondChance] Error transferring mod data: " .. tostring(err))
            -- end

            -- Transfer weight
            local success, err = pcall(function()
                newPlayer:getNutrition():setWeight(tonumber(progress.Weight))
            end)
            if not success then
                print("[ZM_SecondChance] Error transferring weight: " .. tostring(err))
            end

            -- Reassign player tier
            local success, err = pcall(function()
                PlayerTierHandler.reassignRecordedTier(newPlayer)
            end)
            if not success then
                print("[ZM_SecondChance] Error reassigning player tier: " .. tostring(err))
            end

            newPlayer:Say("My Soul has returned to this body.")
            print("[ZM_SecondChance] Progress successfully transferred from " .. oldUsername .. " to new player.")
        end
    end)
end

return PlayerProgressHandler