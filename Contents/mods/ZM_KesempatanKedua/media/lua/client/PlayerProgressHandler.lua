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

-- Split table into chunks of specified size
local function splitIntoChunks(tbl, chunkSize)
    local chunks = {}
    local currentChunk = {}
    local count = 0

    for k, v in pairs(tbl) do
        currentChunk[k] = v
        count = count + 1

        if count >= chunkSize then
            table.insert(chunks, currentChunk)
            currentChunk = {}
            count = 0
        end
    end

    if count > 0 then
        table.insert(chunks, currentChunk)
    end

    return chunks
end

-- Function to request the server to save progress using chunks
function PlayerProgressHandler.requestSaveProgress(username, progress)
    local player = getPlayer()
    if not player then
        print("[ZM_SecondChance] Player not found.")
        return
    end

    -- Generate a unique transfer ID for this save operation
    local transferId = username .. "_" .. tostring(os.time())

    -- Prepare basic data that should be small enough to send in one piece
    local metaData = {
        transferId = transferId,
        username = username,
        weight = progress.Weight,
        traitCount = #progress.Traits,
        recipeCount = #progress.Recipes
    }

    -- Store the chunk info
    local chunks = {
        traits = { type = "traits", data = progress.Traits },
        recipes = { type = "recipes", data = progress.Recipes },
        perks = splitIntoChunks(progress.Perks, 15),  -- Split perks into smaller chunks
        boosts = { type = "boosts", data = progress.Boosts },
        modData = splitIntoChunks(progress.ModData, 10)  -- Split modData into smaller chunks
    }

    -- Calculate total chunks
    local totalChunks = 2 + #chunks.perks + 1 + #chunks.modData  -- traits + recipes + perks chunks + boosts + modData chunks

    -- Set up tracking for server responses
    PlayerProgressHandler.chunkResponses = PlayerProgressHandler.chunkResponses or {}
    PlayerProgressHandler.chunkResponses[transferId] = {
        received = 0,
        total = totalChunks
    }

    -- Define a temporary listener for the server responses
    local function onServerCommand(module, command, args)
        if module == "PlayerProgressServer" and command == "saveProgressChunkResponse" then
            if args.transferId == transferId then
                print("[ZM_SecondChance] Received chunk response " .. args.chunkNum .. "/" .. totalChunks)

                local tracking = PlayerProgressHandler.chunkResponses[transferId]
                if tracking then
                    tracking.received = tracking.received + 1

                    if tracking.received >= tracking.total then
                        player:Say("Progress saved successfully!")
                        PlayerProgressHandler.chunkResponses[transferId] = nil
                        Events.OnServerCommand.Remove(onServerCommand)
                    end
                end
            end
        end
    end
    Events.OnServerCommand.Add(onServerCommand)

    -- Send metadata first
    print("[ZM_SecondChance] Sending metadata for transfer: " .. transferId)
    sendClientCommand(player, "PlayerProgressServer", "saveProgressMetadata", {
        transferId = transferId,
        username = username,
        metadata = metaData,
        totalChunks = totalChunks
    })

    -- Send traits
    sendClientCommand(player, "PlayerProgressServer", "saveProgressChunk", {
        transferId = transferId,
        username = username,
        chunkType = "traits",
        data = chunks.traits.data,
        chunkNum = 1
    })
    print("[ZM_SecondChance] Sent traits chunk to server")

    -- Send recipes
    sendClientCommand(player, "PlayerProgressServer", "saveProgressChunk", {
        transferId = transferId,
        username = username,
        chunkType = "recipes",
        data = chunks.recipes.data,
        chunkNum = 2
    })
    print("[ZM_SecondChance] Sent recipes chunk to server")

    -- Send perks in chunks
    local chunkNum = 3
    for i, perkChunk in ipairs(chunks.perks) do
        sendClientCommand(player, "PlayerProgressServer", "saveProgressChunk", {
            transferId = transferId,
            username = username,
            chunkType = "perks",
            chunkIndex = i,
            totalTypeChunks = #chunks.perks,
            data = perkChunk,
            chunkNum = chunkNum
        })
        print("[ZM_SecondChance] Sent perks chunk " .. i .. "/" .. #chunks.perks)
        chunkNum = chunkNum + 1
    end

    -- Send boosts
    sendClientCommand(player, "PlayerProgressServer", "saveProgressChunk", {
        transferId = transferId,
        username = username,
        chunkType = "boosts",
        data = chunks.boosts.data,
        chunkNum = chunkNum
    })
    print("[ZM_SecondChance] Sent boosts chunk to server")
    chunkNum = chunkNum + 1

    -- Send modData in chunks
    for i, modChunk in ipairs(chunks.modData) do
        sendClientCommand(player, "PlayerProgressServer", "saveProgressChunk", {
            transferId = transferId,
            username = username,
            chunkType = "modData",
            chunkIndex = i,
            totalTypeChunks = #chunks.modData,
            data = modChunk,
            chunkNum = chunkNum
        })
        print("[ZM_SecondChance] Sent modData chunk " .. i .. "/" .. #chunks.modData)
        chunkNum = chunkNum + 1
    end
}

-- Function to transfer progress data from one username to another
function PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
  -- Rest of the function remains unchanged
  print("[ZM_SecondChance] Requesting server to load progress for user: " .. oldUsername)
  sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

  local function onServerCommand(module, command, args)
      if module == "PlayerProgressServer" and command == "loadProgressResponse" then
          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found for user: " .. oldUsername)
              Events.OnServerCommand.Remove(onServerCommand)
              return
          end

          print("[ZM_SecondChance] Transferring progress from " .. oldUsername .. " to new player.")
          -- Transfer traits
          PlayerProgressServer.handleTrait(newPlayer, progress.Traits)

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
                      local boost = progress.Boosts[perkName]
                      print("[ZM_SecondChance] Boosting perk: " .. perkName .. " by " .. boost)
                      local numBoost = tonumber(boost)
                      if numBoost > 0 then
                          newPlayer:getXp():setPerkBoost(perk, numBoost)
                      end
                  end
              else
                  print("[ZM_SecondChance] Invalid perk: " .. perkName)
              end
          end

          -- Transfer known recipes
          local recipes = newPlayer:getKnownRecipes()
          for _, recipe in ipairs(progress.Recipes) do
              recipes:add(recipe)
          end

          -- Transfer weight
          local numWeight = tonumber(progress.Weight)
          newPlayer:getNutrition():setWeight(numWeight)

          -- Reassign player tier
          PlayerTierHandler.reassignRecordedTier(newPlayer)
          newPlayer:Say("My Soul has returned to this body.")
          print("[ZM_SecondChance] Progress successfully transferred from " .. oldUsername .. " to new player.")

          Events.OnServerCommand.Remove(onServerCommand)
      end
  end

  Events.OnServerCommand.Add(onServerCommand)
end

return PlayerProgressHandler