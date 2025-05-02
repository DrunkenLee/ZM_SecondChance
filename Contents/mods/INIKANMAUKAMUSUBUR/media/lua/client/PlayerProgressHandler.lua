require "PlayerProgressServer"
require "PlayerTierHandler"

PlayerProgressHandler = PlayerProgressHandler or {}

local function sanitizeUsername(username)
  return string.gsub(username, "[^%w_-]", "_")
end
-- Function to get the progress data from the client
function PlayerProgressHandler.getProgressLah(player)
    local progress = {
        Traits = {},
        Perks = {},
        Boosts = {},
        Recipes = {},
        ModData = {},
        KillCount = 0,
        SurvivedHour = 0,
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

    playerKillCount = player:getZombieKills() or 0
    playerSurvivedHour = player:getHoursSurvived() or 0
    progress.KillCount = playerKillCount
    progress.SurvivedHour = playerSurvivedHour

    return progress
end

-- Function to request the server to save progress
function PlayerProgressHandler.requestSaveProgress(username, progress)
    local player = getPlayer()
    if not player then
        print("[ZM_SecondChance] Player not found.")
        return
    end

    -- Sanitize username to match server-side sanitization
    local sanitizedUsername = sanitizeUsername(username)
    if sanitizedUsername ~= username then
        print("[ZM_SecondChance] Username was sanitized: " .. username .. " -> " .. sanitizedUsername)
        username = sanitizedUsername
    end

    -- Define a temporary listener for the server response
    local function onServerCommand(module, command, args)
        if module == "PlayerProgressServer" and command == "saveProgressResponse" then
            if args.username == username then
                print("[ZM_SecondChance] Received save confirmation for user: " .. args.username)
                player:Say("Progress saved successfully!")
                -- Remove the listener after handling the response
                Events.OnServerCommand.Remove(onServerCommand)
            end
        end
    end
    Events.OnServerCommand.Add(onServerCommand)

    -- Send the save progress request to the server
    sendClientCommand(player, "PlayerProgressServer", "saveProgress", { username = username, progress = progress })
    print("[ZM_SecondChance] Save progress request sent for user: " .. username)
end

function PlayerProgressHandler.ultraSafeTransferProgress(oldUsername, newPlayer)
  -- Initialize tracking variables
  activeHandlers = activeHandlers or {}
  handlerCounter = handlerCounter or 0
  handlerCounter = handlerCounter + 1
  local handlerId = "ZM_transferHandler_" .. handlerCounter

  -- Generate a unique request ID
  local requestId = "req_" .. tostring(os.time()) .. "_" .. tostring(handlerCounter)

  print("[ZM_SecondChance] Starting ultra-safe transfer for: " .. oldUsername .. " (RequestID: " .. requestId .. ")")

  -- Sanitize username
  local sanitizedUsername = sanitizeUsername(oldUsername)
  oldUsername = sanitizedUsername

  local traitHandler = function(module, command, args)
    -- Debug print for incoming server command
    print(string.format(
      "[ZM_SecondChance] ServerCommand: module=%s, command=%s, args.requestId=%s, expectedRequestId=%s, args.username=%s, expectedUsername=%s",
      tostring(module), tostring(command), tostring(args and args.requestId), tostring(requestId), tostring(args and args.username), tostring(oldUsername)
    ))

    -- Check if the command matches our request ID and username
    if module == "PlayerProgressServer" and command == "loadProgressResponse" and args.requestId == requestId and args.username == oldUsername then
          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found for: " .. oldUsername)
              Events.OnServerCommand.Remove(traitHandler)
              activeHandlers[handlerId] = nil
              return
          end

          print("[ZM_SecondChance] Progress data received, analyzing...")

          -- Reset ALL perks (level and XP) before applying saved data
          local playerXp = newPlayer:getXp()
          for i = 0, PerkFactory.PerkList:size() - 1 do
              local perk = PerkFactory.PerkList:get(i)
              -- Reset level
              pcall(function() newPlayer:level0(perk) end)
              -- Reset XP
              pcall(function() playerXp:setXPToLevel(perk, 0) end)
          end

          -- Create a complete list of all valid perks in the game for verification
          local allGamePerks = {}
          for i = 0, PerkFactory.PerkList:size() - 1 do
              local perk = PerkFactory.PerkList:get(i)
              local perkName = perk:getName()
              allGamePerks[perkName] = true
              print("[ZM_SecondChance] Detected game perk: " .. perkName)
          end

          -- Display what we found for debugging
          if progress.Perks then
              local perkCount = 0
              print("[ZM_SecondChance] === PERKS IN SAVE DATA ===")
              for perkName, xpValue in pairs(progress.Perks) do
                  perkCount = perkCount + 1
                  local numXp = tonumber(xpValue) or 0
                  print("[ZM_SecondChance] Found perk: " .. perkName .. " with XP: " .. tostring(numXp)
                      .. (allGamePerks[perkName] and "" or " (NOT A VALID GAME PERK)"))
              end
              print("[ZM_SecondChance] Found " .. perkCount .. " perks in save data")
          end

          -- Setup queues to process data with proper delays
          local perkQueue = {}
          local strengthFitnessQueue = {} -- Special queue for these perks
          local recipeQueue = {}
          local boostQueue = {}

          -- Known category perks to skip (not actual perks)
          local categoryPerks = {
              ["Combat"] = true,
              ["Firearm"] = true,
              ["Crafting"] = true,
              ["Survivalist"] = true,
              ["Passive"] = true,
              ["Agility"] = true
          }

          -- Fill the processing queues from save data - more robust approach
          if progress.Perks then
              for perkName, xpValue in pairs(progress.Perks) do
                  if not categoryPerks[perkName] then
                      local numXp = tonumber(xpValue) or 0
                      if numXp > 0 then
                          local perk = PerkFactory.getPerkFromName(perkName)
                          if perk then
                              -- Special handling for Strength and Fitness
                              if perk == Perks.Strength or perk == Perks.Fitness then
                                  print("[ZM_SecondChance] Queueing special perk: " .. perkName ..
                                      " with XP: " .. tostring(numXp))
                                  table.insert(strengthFitnessQueue, {name = perkName, perk = perk, xp = numXp})
                              else
                                  print("[ZM_SecondChance] Queueing regular perk: " .. perkName ..
                                      " with XP: " .. tostring(numXp))
                                  table.insert(perkQueue, {name = perkName, perk = perk, xp = numXp})
                              end
                          else
                              print("[ZM_SecondChance] WARNING! Skipping invalid perk: " .. perkName)
                          end
                      else
                          print("[ZM_SecondChance] Skipping zero XP perk: " .. perkName)
                      end
                  else
                      print("[ZM_SecondChance] Skipping category perk: " .. perkName)
                  end
              end
          end

          if progress.Recipes then
              for _, recipe in ipairs(progress.Recipes) do
                  table.insert(recipeQueue, recipe)
              end
              print("[ZM_SecondChance] Found " .. #recipeQueue .. " recipes to restore")
          end

          if progress.Boosts then
              for perkName, boostValue in pairs(progress.Boosts) do
                  local perk = PerkFactory.getPerkFromName(perkName)
                  local numBoost = tonumber(boostValue) or 0
                  if perk and numBoost > 0 then
                      table.insert(boostQueue, {name = perkName, perk = perk, value = numBoost})
                      print("[ZM_SecondChance] Found boost for " .. perkName .. ": " .. tostring(numBoost))
                  end
              end
          end

          print("[ZM_SecondChance] Processing " .. #perkQueue .. " regular perks, " ..
              #strengthFitnessQueue .. " strength/fitness perks, " ..
              #recipeQueue .. " recipes, " .. #boostQueue .. " boosts")

          -- Process weight first
          if progress.Weight then
              local weight = tonumber(progress.Weight) or 80
              pcall(function() newPlayer:getNutrition():setWeight(weight) end)
              print("[ZM_SecondChance] Set weight to " .. weight)
          end

          if progress.KillCount then
              local kills = tonumber(progress.KillCount) or 0
              pcall(function() newPlayer:setZombieKills(kills) end)
              print("[ZM_SecondChance] Set zombie kills to " .. kills)
          end

          if progress.SurvivedHour then
              local hours = tonumber(progress.SurvivedHour) or 0
              pcall(function() newPlayer:setHoursSurvived(hours) end)
              print("[ZM_SecondChance] Set survived hours to " .. hours)
          end

          -- SLOW DOWN PROCESSING WITH TICK COUNTERS
          local ticksPerAction = 10
          local tickCounter = 0

          local currentStage = "strength"
          local currentStrFitIndex = 1
          local currentPerkIndex = 1
          local currentRecipeIndex = 1
          local currentBoostIndex = 1
          local currentLevelPerk = nil
          local remainingXp = 0

          local slowProcessTick = function()
              tickCounter = tickCounter + 1
              if tickCounter < ticksPerAction then return end
              tickCounter = 0

              -- STAGE 1: Process Strength/Fitness perks
              if currentStage == "strength" then
                  if currentStrFitIndex <= #strengthFitnessQueue then
                      local perkData = strengthFitnessQueue[currentStrFitIndex]
                      pcall(function()
                          newPlayer:level0(perkData.perk)
                          newPlayer:getXp():AddXP(perkData.perk, perkData.xp, false, false, false)
                          luautils.updatePerksXp(perkData.perk, newPlayer)
                          print("[ZM_SecondChance] Restored " .. perkData.name .. " XP: " .. perkData.xp)
                      end)
                      currentStrFitIndex = currentStrFitIndex + 1
                      return
                  else
                      print("[ZM_SecondChance] All Strength/Fitness perks processed, starting regular perks...")
                      currentStage = "perks"
                      return
                  end
              end

              -- STAGE 2: Process regular perks
              if currentStage == "perks" then
                  if currentPerkIndex <= #perkQueue then
                      local perkData = perkQueue[currentPerkIndex]
                      pcall(function()
                          newPlayer:level0(perkData.perk)
                          newPlayer:getXp():AddXP(perkData.perk, perkData.xp, false, false, false)
                          luautils.updatePerksXp(perkData.perk, newPlayer)
                          print("[ZM_SecondChance] Restored " .. perkData.name .. " XP: " .. perkData.xp)
                      end)
                      currentPerkIndex = currentPerkIndex + 1
                      return
                  else
                      print("[ZM_SecondChance] All regular perks processed, starting recipes...")
                      currentStage = "recipes"
                      return
                  end
              end

              -- STAGE 3: Process recipes
              if currentStage == "recipes" then
                  if currentRecipeIndex <= #recipeQueue then
                      local recipeCount = 0
                      local batchSize = 5
                      while currentRecipeIndex <= #recipeQueue and recipeCount < batchSize do
                          local recipe = recipeQueue[currentRecipeIndex]
                          pcall(function()
                              newPlayer:getKnownRecipes():add(recipe)
                          end)
                          currentRecipeIndex = currentRecipeIndex + 1
                          recipeCount = recipeCount + 1
                      end
                      print("[ZM_SecondChance] Processed recipes: " .. (currentRecipeIndex-1) .. "/" .. #recipeQueue)
                      return
                  else
                      print("[ZM_SecondChance] All recipes processed, starting boosts...")
                      currentStage = "boosts"
                      return
                  end
              end

              -- STAGE 4: Process boosts
              if currentStage == "boosts" then
                  if currentBoostIndex <= #boostQueue then
                      local boostData = boostQueue[currentBoostIndex]
                      pcall(function()
                          newPlayer:getXp():setPerkBoost(boostData.perk, boostData.value)
                          print("[ZM_SecondChance] Set boost " .. boostData.value .. " for " .. boostData.name)
                      end)
                      currentBoostIndex = currentBoostIndex + 1
                      return
                  else
                      currentStage = "finished"
                      print("[ZM_SecondChance] All data processed successfully!")
                      pcall(function()
                          PlayerTierHandler.reassignRecordedTier(newPlayer)
                      end)
                      local playerXp = newPlayer:getXp()
                      print("[ZM_SecondChance] VERIFICATION REPORT:")
                      for i = 0, PerkFactory.PerkList:size() - 1 do
                          local perk = PerkFactory.PerkList:get(i)
                          local perkName = perk:getName()
                          local xp = playerXp:getXP(perk)
                          local level = newPlayer:getPerkLevel(perk)
                          print("[ZM_SecondChance] " .. perkName .. " Level: " .. level .. " XP: " .. xp)
                      end
                      Events.OnTick.Remove(slowProcessTick)
                      newPlayer:Say("My soul has returned to this body. All knowledge restored.")
                      return
                  end
              end
          end

          print("[ZM_SecondChance] Starting slow sequential processing...")
          Events.OnTick.Add(slowProcessTick)

          Events.OnServerCommand.Remove(traitHandler)
          activeHandlers[handlerId] = nil
      end
  end
  Events.OnServerCommand.Add(traitHandler)
  activeHandlers[handlerId] = traitHandler
  sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgressXP", {
    username = oldUsername,
    requestId = requestId
  })
end

function PlayerProgressHandler.completeTraitTransfer(username, player)
  -- Initialize variables
  activeHandlers = activeHandlers or {}
  handlerCounter = handlerCounter or 0
  handlerCounter = handlerCounter + 1
  local handlerId = "ZM_traitHandler_" .. handlerCounter
  -- Generate a unique request ID
  local requestId = "reqTrait_" .. tostring(os.time()) .. "_" .. tostring(handlerCounter)

  print("[ZM_SecondChance] Starting trait recovery for: " .. username)
  -- Sanitize username
  local sanitizedUsername = sanitizeUsername(username)
  username = sanitizedUsername

  local traitHandler = function(module, command, args)
      print(string.format(
        "[ZM_SecondChance] TraitTransfer ServerCommand: module=%s, command=%s, args.requestId=%s, expectedRequestId=%s, args.username=%s, expectedUsername=%s",
        tostring(module), tostring(command), tostring(args and args.requestId), tostring(requestId), tostring(args and args.username), tostring(username)
      ))

      if module == "PlayerProgressServer" and command == "loadProgressResponse" and args.requestId == requestId and args.username == username then

          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found")
              Events.OnServerCommand.Remove(traitHandler)
              activeHandlers[handlerId] = nil
              return
          end

          -- IMPORTANT: Clear all existing traits locally first
          local currentTraits = player:getTraits()
          local traitsToRemove = {}

          -- Collect all traits first (can't modify while iterating)
          for i = 0, currentTraits:size() - 1 do
              table.insert(traitsToRemove, currentTraits:get(i))
          end

          -- Now remove all traits
          print("[ZM_SecondChance] Removing " .. #traitsToRemove .. " existing traits...")
          for _, traitName in ipairs(traitsToRemove) do
              player:getTraits():remove(traitName)
              print("[ZM_SecondChance] Removed trait: " .. traitName)
          end

          -- Also tell server to clear traits for sync
          sendClientCommand(player, "PlayerProgressServer", "clearTraits", {})

          -- Get traits from the progress table
          local validTraits = {}
          if progress.Traits then
              print("[ZM_SecondChance] Processing traits...")

              -- Handle either array or key-value format
              for k, v in pairs(progress.Traits) do
                  local traitName = v
                  if TraitFactory.getTrait(traitName) then
                      table.insert(validTraits, traitName)
                  end
              end

              print("[ZM_SecondChance] Found " .. #validTraits .. " valid traits")

              -- DIRECT APPLICATION: Apply traits one by one
              for _, trait in ipairs(validTraits) do
                  -- Add trait directly to player
                  player:getTraits():add(trait)
                  print("[ZM_SecondChance] Applied trait: " .. trait)
              end

              -- Also send to server for synchronization
              sendClientCommand(player, "PlayerProgressServer", "applyTraits", { traits = validTraits })

              player:Say("Restored " .. #validTraits .. " traits!")
          else
              print("[ZM_SecondChance] No traits found in save file")
          end

          -- Clean up handler
          Events.OnServerCommand.Remove(traitHandler)
          activeHandlers[handlerId] = nil
      end
  end

  -- Register handler
  Events.OnServerCommand.Add(traitHandler)
  activeHandlers[handlerId] = traitHandler

  -- Request progress data
  sendClientCommand(player, "PlayerProgressServer", "loadProgressTRAIT", {
    username = username,
    requestId = requestId
  })
end

return PlayerProgressHandler