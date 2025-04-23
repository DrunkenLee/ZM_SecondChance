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

-- Function to transfer progress data from one username to another

function PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
    -- Sanitize username to match server-side sanitization
    local sanitizedUsername = sanitizeUsername(oldUsername)
    if sanitizedUsername ~= oldUsername then
        print("[ZM_SecondChance] Username was sanitized: " .. oldUsername .. " -> " .. sanitizedUsername)
        oldUsername = sanitizedUsername
    end

    print("[ZM_SecondChance] Requesting progress transfer from: " .. oldUsername)
    -- Request the server to load the progress data for the old username
    sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

    -- Define the listener function
    local function onServerCommand(module, command, args)
        if module == "PlayerProgressServer" and command == "loadProgressResponse" then
            local progress = args.progress
            if not progress then
                print("[ZM_SecondChance] No progress data found for user: " .. oldUsername)
                newPlayer:Say("No saved progress found for " .. oldUsername)
                Events.OnServerCommand.Remove(onServerCommand)
                return
            end

            print("[ZM_SecondChance] Transferring progress from " .. oldUsername .. " to new player.")

            -- Transfer traits with validation
            if progress.Traits and #progress.Traits > 0 then
                pcall(function()
                    PlayerProgressServer.handleTrait(newPlayer, progress.Traits)
                end)
            else
                print("[ZM_SecondChance] No traits to transfer")
            end

            -- Transfer XP and perks
            local playerXp = newPlayer:getXp()
            for perkName, xp in pairs(progress.Perks) do
                local perk = PerkFactory.getPerkFromName(perkName)
                if perk then
                    pcall(function() newPlayer:level0(perk) end)

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

                    if progress.Boosts and progress.Boosts[perkName] then
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

            -- Transfer weight safely
            if progress.Weight then
                local numWeight = tonumber(progress.Weight) or 80
                pcall(function() newPlayer:getNutrition():setWeight(numWeight) end)
            end

            -- Transfer recipes
            if progress.Recipes then
                local knownRecipes = newPlayer:getKnownRecipes()
                for _, recipe in ipairs(progress.Recipes) do
                    pcall(function() knownRecipes:add(recipe) end)
                end
            end

            -- Reassign player tier
            pcall(function()
                PlayerTierHandler.reassignRecordedTier(newPlayer)
            end)

            newPlayer:Say("My Soul has returned to this body.")
            print("[ZM_SecondChance] Progress successfully transferred from " .. oldUsername .. " to new player.")

            -- Remove the listener after handling the response
            Events.OnServerCommand.Remove(onServerCommand)
        end
    end

    -- Add the listener for OnServerCommand
    Events.OnServerCommand.Add(onServerCommand)
end

-- Add a safer version for testing large transfers
function PlayerProgressHandler.safeTransferProgress(oldUsername, newPlayer)
    -- Just wraps the regular function with better error handling
    pcall(function()
        PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
    end)
end

-- Enhanced safe transfer for complex admin data
function PlayerProgressHandler.enhancedTransferProgress(oldUsername, newPlayer)
    -- Sanitize username
    local sanitizedUsername = sanitizeUsername(username)
    oldUsername = sanitizedUsername

    print("[ZM_SecondChance] Starting enhanced transfer for: " .. oldUsername)
    sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

    local function onServerCommand(module, command, args)
        if module == "PlayerProgressServer" and command == "loadProgressResponse" then
            local progress = args.progress
            if not progress then
                print("[ZM_SecondChance] No progress data found")
                Events.OnServerCommand.Remove(onServerCommand)
                return
            end

            print("[ZM_SecondChance] Received data, processing in chunks...")

            -- Use a timer to prevent UI freezing
            local processTraits = function()
                if progress.Traits then
                    print("[ZM_SecondChance] Processing " .. #progress.Traits .. " traits")
                    -- Process traits in smaller batches to avoid crash
                    local validTraits = {}
                    for i, trait in pairs(progress.Traits) do
                        if TraitFactory.getTrait(trait) then
                            table.insert(validTraits, trait)
                        end
                    end

                    -- Process 5 traits at a time
                    local processTraitBatch = function(startIdx)
                        local endIdx = math.min(startIdx + 4, #validTraits)
                        local batchTraits = {}

                        for i = startIdx, endIdx do
                            table.insert(batchTraits, validTraits[i])
                        end

                        if #batchTraits > 0 then
                            pcall(function()
                                sendClientCommand(newPlayer, "PlayerProgressServer", "applyTraits",
                                { traits = batchTraits })
                            end)
                        end

                        -- Continue with next batch if needed
                        if endIdx < #validTraits then
                            Events.OnTick.Add(function()
                                Events.OnTick.Remove(processTraitBatch)
                                processTraitBatch(endIdx + 1)
                            end)
                        else
                            -- Move to next step - process perks
                            Events.OnTick.Add(function()
                                Events.OnTick.Remove(processPerks)
                                processPerks()
                            end)
                        end
                    end

                    if #validTraits > 0 then
                        processTraitBatch(1)
                    else
                        -- Move to perks if no traits
                        processPerks()
                    end
                else
                    -- No traits, move to perks
                    processPerks()
                end
            end

            -- Process perks in chunks to prevent crashes
            local processPerks = function()
                print("[ZM_SecondChance] Processing perks")

                -- Get list of perks to process
                local perkList = {}
                for perkName, _ in pairs(progress.Perks) do
                    table.insert(perkList, perkName)
                end

                -- Process perks one at a time
                local currentPerkIndex = 1
                local processPerk = function()
                    if currentPerkIndex <= #perkList then
                        local perkName = perkList[currentPerkIndex]
                        local perk = PerkFactory.getPerkFromName(perkName)

                        if perk then
                            local xp = progress.Perks[perkName]
                            print("[ZM_SecondChance] Processing perk: " .. perkName .. " XP: " .. xp)

                            -- Add XP safely
                            local playerXp = newPlayer:getXp()
                            pcall(function() newPlayer:level0(perk) end)

                            -- Special handling for high XP perks
                            if (perk == Perks.Strength or perk == Perks.Fitness) and tonumber(xp) > 100000 then
                                -- Process high values in small increments
                                local remainingXp = tonumber(xp)
                                local chunk = math.min(remainingXp, 50000)

                                pcall(function()
                                    playerXp:AddXP(perk, chunk)
                                    luautils.updatePerksXp(perk, newPlayer)
                                end)
                            else
                                -- Normal XP handling
                                pcall(function()
                                    playerXp:AddXP(perk, tonumber(xp))
                                    luautils.updatePerksXp(perk, newPlayer)
                                end)
                            end

                            -- Apply boost if any
                            if progress.Boosts and progress.Boosts[perkName] then
                                pcall(function()
                                    newPlayer:getXp():setPerkBoost(perk, tonumber(progress.Boosts[perkName]))
                                end)
                            end
                        end

                        currentPerkIndex = currentPerkIndex + 1

                        -- Continue with next perk in the next tick
                        Events.OnTick.Add(function()
                            Events.OnTick.Remove(processPerk)
                            processPerk()
                        end)
                    else
                        -- Move to recipes
                        Events.OnTick.Add(function()
                            Events.OnTick.Remove(processRecipes)
                            processRecipes()
                        end)
                    end
                end

                processPerk()
            end

            -- Process recipes
            local processRecipes = function()
                print("[ZM_SecondChance] Processing recipes")
                if progress.Recipes then
                    local knownRecipes = newPlayer:getKnownRecipes()
                    for _, recipe in ipairs(progress.Recipes) do
                        pcall(function() knownRecipes:add(recipe) end)
                    end
                end

                -- Process weight last
                pcall(function()
                    if progress.Weight then
                        newPlayer:getNutrition():setWeight(tonumber(progress.Weight) or 80)
                    end
                end)

                -- Final steps
                pcall(function() PlayerTierHandler.reassignRecordedTier(newPlayer) end)
                newPlayer:Say("My Soul has returned to this body.")
                print("[ZM_SecondChance] Enhanced transfer completed successfully")
                Events.OnServerCommand.Remove(onServerCommand)
            end

            -- Start the processing chain
            processTraits()
        end
    end

    Events.OnServerCommand.Add(onServerCommand)
end

function PlayerProgressHandler.ultraSafeTransferProgress(oldUsername, newPlayer)
  -- Initialize tracking variables
  activeHandlers = activeHandlers or {}
  handlerCounter = handlerCounter or 0
  handlerCounter = handlerCounter + 1
  local handlerId = "ZM_transferHandler_" .. handlerCounter

  -- Sanitize username
  local sanitizedUsername = sanitizeUsername(oldUsername)
  oldUsername = sanitizedUsername

  print("[ZM_SecondChance] Starting ultra-safe transfer for: " .. oldUsername)

  local traitHandler = function(module, command, args)
      if module == "PlayerProgressServer" and command == "loadProgressResponse" then
          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found for: " .. oldUsername)
              Events.OnServerCommand.Remove(traitHandler)
              activeHandlers[handlerId] = nil
              return
          end

          print("[ZM_SecondChance] Progress data received, analyzing...")

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
                  -- FIXED: Replaced goto/label with nested if statements
                  -- Only process if it's not a category perk
                  if not categoryPerks[perkName] then
                      local numXp = tonumber(xpValue) or 0

                      -- Only process if XP > 0
                      if numXp > 0 then
                          -- Try to get the perk object
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

          -- SLOW DOWN PROCESSING WITH TICK COUNTERS
          local ticksPerAction = 10  -- Wait this many ticks between actions (reduced for faster processing)
          local tickCounter = 0

          -- Current processing state
          local currentStage = "strength" -- Start with strength/fitness
          local currentStrFitIndex = 1
          local currentPerkIndex = 1
          local currentRecipeIndex = 1
          local currentBoostIndex = 1
          local currentLevelPerk = nil
          local remainingXp = 0

          -- Main slow processing tick function
          local slowProcessTick = function()
              -- Only process every X ticks for server synchronization
              tickCounter = tickCounter + 1
              if tickCounter < ticksPerAction then return end
              tickCounter = 0

              -- STAGE 1: Process Strength/Fitness perks
              if currentStage == "strength" then
                  -- If we're in the middle of leveling a perk
                  if currentLevelPerk then
                      local perkData = currentLevelPerk
                      local perk = perkData.perk
                      local nextLevel = newPlayer:getPerkLevel(perk) + 1

                      -- Only process up to level 10 (game max)
                      if nextLevel > 10 then
                          print("[ZM_SecondChance] " .. perkData.name .. " reached max level")
                          currentLevelPerk = nil
                          return
                      end

                      local nextLevelXp = perk:getXpForLevel(nextLevel)

                      if remainingXp >= nextLevelXp then
                          -- Apply level and continue
                          remainingXp = remainingXp - nextLevelXp
                          pcall(function()
                              newPlayer:LevelPerk(perk)
                              luautils.updatePerksXp(perk, newPlayer)
                          end)

                          print("[ZM_SecondChance] Leveled " .. perkData.name .. " to " .. nextLevel ..
                                ", remaining XP: " .. remainingXp)
                      else
                          -- Add remaining XP and move to next perk
                          pcall(function()
                              newPlayer:getXp():AddXP(perk, remainingXp, false, false, true)
                              luautils.updatePerksXp(perk, newPlayer)
                          end)

                          print("[ZM_SecondChance] Added final " .. remainingXp .. " XP to " .. perkData.name)
                          currentLevelPerk = nil
                      end

                      -- Continue in the next tick cycle
                      return
                  end

                  -- Move to the next strength/fitness perk
                  if currentStrFitIndex <= #strengthFitnessQueue then
                      local perkData = strengthFitnessQueue[currentStrFitIndex]

                      -- Reset perk level first
                      pcall(function() newPlayer:level0(perkData.perk) end)

                      print("[ZM_SecondChance] Processing " .. perkData.name .. " with special handling, XP: " .. perkData.xp)

                      -- Setup for level-by-level processing
                      currentLevelPerk = perkData
                      remainingXp = tonumber(perkData.xp) or 0
                      currentStrFitIndex = currentStrFitIndex + 1

                      -- Return to continue in next tick
                      return
                  else
                      -- All Strength/Fitness perks processed, move to regular perks
                      print("[ZM_SecondChance] All Strength/Fitness perks processed, starting regular perks...")
                      currentStage = "perks"
                      return
                  end
              end

              -- STAGE 2: Process regular perks
              if currentStage == "perks" then
                  if currentPerkIndex <= #perkQueue then
                      local perkData = perkQueue[currentPerkIndex]

                      print("[ZM_SecondChance] Processing perk " .. currentPerkIndex .. "/" .. #perkQueue .. ": " .. perkData.name)

                      pcall(function()
                          local perk = perkData.perk
                          if perk then
                              -- Reset perk level first
                              newPlayer:level0(perk)

                              local xp = tonumber(perkData.xp) or 0
                              if xp > 0 then
                                  -- First apply levels directly based on XP thresholds
                                  local level = 0
                                  for l = 1, 10 do -- Check up to level 10
                                      if xp >= perk:getXpForLevel(l) then
                                          level = l
                                      else
                                          break
                                      end
                                  end

                                  -- Apply levels directly - this is the critical part
                                  for i = 1, level do
                                      newPlayer:LevelPerk(perk)
                                  end

                                  -- Calculate how much XP has been used for full levels
                                  local levelXp = level > 0 and perk:getXpForLevel(level) or 0

                                  -- Add remaining XP beyond the last full level
                                  local remainingXp = math.max(0, xp - levelXp)
                                  if remainingXp > 0 then
                                      -- Modified: Apply remaining XP with noMultiplier=false to properly respect game settings
                                      newPlayer:getXp():AddXP(perk, remainingXp, false, false, false)
                                  end

                                  -- Force UI update
                                  luautils.updatePerksXp(perk, newPlayer)

                                  -- Report the result
                                  local actualLevel = newPlayer:getPerkLevel(perk)
                                  local actualXp = newPlayer:getXp():getXP(perk)
                                  print("[ZM_SecondChance] " .. perkData.name .. " set to level " .. actualLevel ..
                                        " with " .. actualXp .. " XP (target: level " .. level .. " with " .. xp .. " XP)")
                              end
                          end
                      end)

                      currentPerkIndex = currentPerkIndex + 1
                      return
                  else
                      -- All perks processed, move to recipes
                      print("[ZM_SecondChance] All regular perks processed, starting recipes...")
                      currentStage = "recipes"
                      return
                  end
              end

              -- STAGE 3: Process recipes
              if currentStage == "recipes" then
                  if currentRecipeIndex <= #recipeQueue then
                      -- Process 5 recipes at a time for efficiency but not too fast
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

                      -- Progress report
                      print("[ZM_SecondChance] Processed recipes: " .. (currentRecipeIndex-1) .. "/" .. #recipeQueue)
                      return
                  else
                      -- All recipes processed, move to boosts
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
                          local perk = boostData.perk
                          local boost = tonumber(boostData.value) or 0
                          if boost > 0 then
                              -- Apply boost with careful error handling
                              newPlayer:getXp():setPerkBoost(perk, boost)
                              print("[ZM_SecondChance] Set boost " .. boost .. " for " .. boostData.name)
                          end
                      end)

                      currentBoostIndex = currentBoostIndex + 1
                      return
                  else
                      -- All boosts processed, we're done
                      currentStage = "finished"

                      -- Final steps
                      print("[ZM_SecondChance] All data processed successfully!")
                      pcall(function()
                          PlayerTierHandler.reassignRecordedTier(newPlayer)
                      end)

                      -- Verify all perks were applied
                      local playerXp = newPlayer:getXp()
                      print("[ZM_SecondChance] VERIFICATION REPORT:")
                      for i = 0, PerkFactory.PerkList:size() - 1 do
                          local perk = PerkFactory.PerkList:get(i)
                          local perkName = perk:getName()
                          local xp = playerXp:getXP(perk)
                          local level = newPlayer:getPerkLevel(perk)
                          print("[ZM_SecondChance] " .. perkName .. " Level: " .. level .. " XP: " .. xp)
                      end

                      -- Stop the processing timer
                      Events.OnTick.Remove(slowProcessTick)
                      newPlayer:Say("My soul has returned to this body. All knowledge restored.")
                      return
                  end
              end
          end

          -- Start the slow processing timer
          print("[ZM_SecondChance] Starting slow sequential processing...")
          Events.OnTick.Add(slowProcessTick)

          -- Remove server command listener since we're processing now
          Events.OnServerCommand.Remove(traitHandler)
          activeHandlers[handlerId] = nil
      end
  end
  -- Send the command after everything is set up
  Events.OnServerCommand.Add(traitHandler)
  activeHandlers[handlerId] = traitHandler
  sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })
end

function PlayerProgressHandler.completeTraitTransfer(username, player)
  -- Initialize variables
  activeHandlers = activeHandlers or {}
  handlerCounter = handlerCounter or 0
  handlerCounter = handlerCounter + 1
  local handlerId = "ZM_traitHandler_" .. handlerCounter

  print("[ZM_SecondChance] Starting trait recovery for: " .. username)

  local traitHandler = function(module, command, args)
      if module == "PlayerProgressServer" and command == "loadProgressResponse" then
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
  activeHandlers[handlerId] = traitHandler
  Events.OnServerCommand.Add(traitHandler)

  -- Request progress data
  sendClientCommand(player, "PlayerProgressServer", "loadProgress", { username = username })
end

return PlayerProgressHandler