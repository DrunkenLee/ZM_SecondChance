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
    print("[ZM_SecondChance] Requesting server to save progress for user: " .. username)
    sendClientCommand("PlayerProgressServer", "saveProgress", { username = username, progress = progress })
end

-- Function to transfer progress data from one username to another
function PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
    print("[ZM_SecondChance] Requesting server to load progress for user: " .. oldUsername)
    -- Request the server to load the progress data for the old username
    sendClientCommand("PlayerProgressServer", "loadProgress", { username = oldUsername })

    -- Register a callback to handle the server response
    Events.OnServerCommand.Add(function(module, command, args)
        if module == "PlayerProgressServer" and command == "loadProgressResponse" then
            local progress = args.progress
            if not progress then
                print("[ZM_SecondChance] No progress data found for user: " .. oldUsername)
                return
            end

            print("[ZM_SecondChance] Transferring progress from " .. oldUsername .. " to new player.")

            -- Transfer traits
            newPlayer:getTraits():clear()
            for _, trait in ipairs(progress.Traits) do
                newPlayer:getTraits():add(trait)
            end

            -- Transfer XP and perks
            local playerXp = newPlayer:getXp()
            for perkName, xp in pairs(progress.Perks) do
                local perk = PerkFactory.getPerkFromName(perkName)
                newPlayer:level0(perk)
                if perk == Perks.Strength or perk == Perks.Fitness then
                    local b = true
                    local bXp = xp
                    while b do
                        local nextLevel = newPlayer:getPerkLevel(perk) + 1
                        local nextLevelXp = perk:getXpForLevel(nextLevel)
                        if bXp >= nextLevelXp then
                            bXp = bXp - nextLevelXp
                            newPlayer:LevelPerk(perk)
                            luautils.updatePerksXp(perk, newPlayer)
                        else
                            b = false
                            playerXp:AddXP(perk, bXp, false, false, true)
                        end
                    end
                else
                    playerXp:AddXP(perk, xp, false, false, true)
                    luautils.updatePerksXp(perk, newPlayer)
                end

                if progress.Boosts[perkName] then
                    local boost = progress.Boosts[perkName]
                    if boost > 0 then
                        newPlayer:getXp():setPerkBoost(perk, boost)
                    end
                end
            end

            -- Transfer known recipes
            local recipes = newPlayer:getKnownRecipes()
            for _, recipe in ipairs(progress.Recipes) do
                recipes:add(recipe)
            end

            -- Transfer mod data
            local modData = newPlayer:getModData()
            for key, val in pairs(progress.ModData) do
                modData[key] = val
            end

            -- Transfer weight
            newPlayer:getNutrition():setWeight(progress.Weight)

            -- Reassign player tier
            PlayerTierHandler.reassignRecordedTier(newPlayer)

            print("[ZM_SecondChance] Progress successfully transferred from " .. oldUsername .. " to new player.")
        end
    end)
end

return PlayerProgressHandler

