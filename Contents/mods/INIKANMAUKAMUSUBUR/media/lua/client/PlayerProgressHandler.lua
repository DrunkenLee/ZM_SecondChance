require "PlayerProgressServer"
require "PlayerTierHandler"

PlayerProgressHandler = PlayerProgressHandler or {}

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
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
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
    local sanitizedUsername = string.gsub(oldUsername, "[^%w_-]", "_")
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
    local sanitizedUsername = string.gsub(oldUsername, "[^%w_-]", "_")
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
  -- Sanitize username
  local sanitizedUsername = string.gsub(oldUsername, "[^%w_-]", "_")
  oldUsername = sanitizedUsername

  print("[ZM_SecondChance] Starting ultra-safe transfer for: " .. oldUsername)
  sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

  local function onServerCommand(module, command, args)
      if module == "PlayerProgressServer" and command == "loadProgressResponse" then
          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found for: " .. oldUsername)
              Events.OnServerCommand.Remove(onServerCommand)
              return
          end

          print("[ZM_SecondChance] Got progress data, starting sequential processing...")

          -- Setup queues to process data safely
          local perkQueue = {}
          local strengthFitnessQueue = {} -- Special queue for these perks
          local recipeQueue = {}
          local boostQueue = {}

          -- Fill the queues from progress data
          if progress.Perks then
              for perkName, xpValue in pairs(progress.Perks) do
                  local perk = PerkFactory.getPerkFromName(perkName)
                  if perk then
                      -- Special handling for Strength and Fitness
                      if perk == Perks.Strength or perk == Perks.Fitness then
                          table.insert(strengthFitnessQueue, {name = perkName, perk = perk, xp = xpValue})
                      else
                          table.insert(perkQueue, {name = perkName, perk = perk, xp = xpValue})
                      end
                  else
                      print("[ZM_SecondChance] Skipping invalid perk: " .. perkName)
                  end
              end
          end

          if progress.Recipes then
              for _, recipe in ipairs(progress.Recipes) do
                  table.insert(recipeQueue, recipe)
              end
          end

          if progress.Boosts then
              for perkName, boostValue in pairs(progress.Boosts) do
                  local perk = PerkFactory.getPerkFromName(perkName)
                  if perk then
                      table.insert(boostQueue, {name = perkName, perk = perk, value = boostValue})
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

          -- Process traits next if any
          if progress.Traits and #progress.Traits > 0 then
              pcall(function()
                  -- Send in small batches if there are many traits
                  local batchSize = 5
                  for i = 1, #progress.Traits, batchSize do
                      local batch = {}
                      for j = i, math.min(i + batchSize - 1, #progress.Traits) do
                          if TraitFactory.getTrait(progress.Traits[j]) then
                              table.insert(batch, progress.Traits[j])
                          end
                      end

                      if #batch > 0 then
                          sendClientCommand(newPlayer, "PlayerProgressServer", "applyTraits", {traits = batch})
                      end
                  end
                  print("[ZM_SecondChance] Applied traits")
              end)
          end

          -- Process regular perks (one per tick)
          local processPerk = nil
          local currentPerkIndex = 1

          -- Process Strength/Fitness perks (level by level)
          local currentStrFitIndex = 1
          local processStrengthFitness = nil
          local processStrFitLevel = nil

          -- Current perk being processed level-by-level
          local currentLevelPerk = nil
          local remainingXp = 0

          -- Process recipes
          local processRecipe = nil
          local currentRecipeIndex = 1

          -- Process boosts
          local processBoost = nil
          local currentBoostIndex = 1

          -- Special Strength/Fitness level-by-level handling
          processStrFitLevel = function()
              if not currentLevelPerk then return false end

              local perkData = currentLevelPerk
              local perk = perkData.perk
              local nextLevel = newPlayer:getPerkLevel(perk) + 1

              -- Only process up to level 10 (game max)
              if nextLevel > 10 then
                  print("[ZM_SecondChance] " .. perkData.name .. " reached max level")
                  -- Move to next strength/fitness perk
                  currentLevelPerk = nil
                  Events.OnTick.Remove(processStrFitLevel)
                  Events.OnTick.Add(processStrengthFitness)
                  return false
              end

              local nextLevelXp = perk:getXpForLevel(nextLevel)

              if remainingXp >= nextLevelXp then
                  -- Apply level and continue
                  remainingXp = remainingXp - nextLevelXp
                  local success = pcall(function()
                      newPlayer:LevelPerk(perk)
                      luautils.updatePerksXp(perk, newPlayer)
                  end)

                  if success then
                      print("[ZM_SecondChance] Leveled " .. perkData.name .. " to " .. nextLevel ..
                            ", remaining XP: " .. remainingXp)
                      return true  -- Continue processing levels
                  else
                      -- If error, try to add remaining XP directly
                      pcall(function()
                          newPlayer:getXp():AddXP(perk, remainingXp, false, false, true)
                          luautils.updatePerksXp(perk, newPlayer)
                      end)
                      print("[ZM_SecondChance] Error leveling perk, added remaining XP: " .. remainingXp)

                      -- Move to next strength/fitness perk
                      currentLevelPerk = nil
                      Events.OnTick.Remove(processStrFitLevel)
                      Events.OnTick.Add(processStrengthFitness)
                      return false
                  end
              else
                  -- Add remaining XP and move to next perk
                  pcall(function()
                      newPlayer:getXp():AddXP(perk, remainingXp, false, false, true)
                      luautils.updatePerksXp(perk, newPlayer)
                  end)

                  print("[ZM_SecondChance] Added final " .. remainingXp .. " XP to " .. perkData.name)

                  -- Move to next strength/fitness perk
                  currentLevelPerk = nil
                  Events.OnTick.Remove(processStrFitLevel)
                  Events.OnTick.Add(processStrengthFitness)
                  return false
              end
          end

          -- Process Strength and Fitness perks
          processStrengthFitness = function()
              if currentStrFitIndex <= #strengthFitnessQueue then
                  local perkData = strengthFitnessQueue[currentStrFitIndex]

                  -- Reset perk level and set up for level-by-level processing
                  pcall(function() newPlayer:level0(perkData.perk) end)

                  print("[ZM_SecondChance] Processing " .. perkData.name .. " with special handling, XP: " .. perkData.xp)

                  -- Set up for level-by-level processing
                  currentLevelPerk = perkData
                  remainingXp = tonumber(perkData.xp) or 0
                  currentStrFitIndex = currentStrFitIndex + 1

                  -- Start level-by-level processing
                  Events.OnTick.Remove(processStrengthFitness)
                  Events.OnTick.Add(processStrFitLevel)
                  return false
              else
                  -- All Strength/Fitness perks processed, move to regular perks
                  print("[ZM_SecondChance] All Strength/Fitness perks processed, starting regular perks...")
                  Events.OnTick.Remove(processStrengthFitness)
                  Events.OnTick.Add(processPerk)
                  return false
              end
          end

          -- Process regular perks
          processPerk = function()
              if currentPerkIndex <= #perkQueue then
                  local perkData = perkQueue[currentPerkIndex]
                  pcall(function()
                      local perk = perkData.perk
                      if perk then
                          -- Reset perk level first
                          newPlayer:level0(perk)

                          local xp = tonumber(perkData.xp) or 0
                          if xp > 0 then
                              -- Process in smaller chunks if very large
                              local MAX_CHUNK = 100000
                              local remainingXp = xp

                              while remainingXp > 0 do
                                  local chunk = math.min(remainingXp, MAX_CHUNK)
                                  pcall(function()
                                      newPlayer:getXp():AddXP(perk, chunk, false, false, true)
                                  end)
                                  remainingXp = remainingXp - chunk

                                  if remainingXp <= 0 then
                                      break
                                  end
                              end

                              pcall(function() luautils.updatePerksXp(perk, newPlayer) end)
                              print("[ZM_SecondChance] Added " .. xp .. " XP to " .. perkData.name)
                          end
                      end
                  end)
                  currentPerkIndex = currentPerkIndex + 1
                  return true
              else
                  -- All perks processed, move to recipes
                  print("[ZM_SecondChance] All regular perks processed, starting recipes...")
                  Events.OnTick.Remove(processPerk)
                  Events.OnTick.Add(processRecipe)
                  return false
              end
          end

          -- Process recipes
          processRecipe = function()
              if currentRecipeIndex <= #recipeQueue then
                  local recipe = recipeQueue[currentRecipeIndex]
                  pcall(function()
                      newPlayer:getKnownRecipes():add(recipe)
                  end)
                  currentRecipeIndex = currentRecipeIndex + 1

                  -- Process recipes in batches to speed up
                  if currentRecipeIndex % 10 == 0 then
                      print("[ZM_SecondChance] Processed " .. currentRecipeIndex .. "/" .. #recipeQueue .. " recipes")
                  end

                  return true
              else
                  -- All recipes processed, move to boosts
                  print("[ZM_SecondChance] All recipes processed, starting boosts...")
                  Events.OnTick.Remove(processRecipe)
                  Events.OnTick.Add(processBoost)
                  return false
              end
          end

          -- Process boosts
          processBoost = function()
              if currentBoostIndex <= #boostQueue then
                  local boostData = boostQueue[currentBoostIndex]
                  pcall(function()
                      local perk = boostData.perk
                      local boost = tonumber(boostData.value) or 0
                      if boost > 0 then
                          -- This was causing crashes before - extra careful handling
                          local success = pcall(function()
                              newPlayer:getXp():setPerkBoost(perk, boost)
                          end)

                          if success then
                              print("[ZM_SecondChance] Set boost " .. boost .. " for " .. boostData.name)
                          else
                              print("[ZM_SecondChance] Failed to set boost for " .. boostData.name)
                          end
                      end
                  end)
                  currentBoostIndex = currentBoostIndex + 1
                  return true
              else
                  -- All boosts processed, we're done
                  print("[ZM_SecondChance] All data processed successfully!")
                  Events.OnTick.Remove(processBoost)

                  -- Finish up
                  pcall(function()
                      PlayerTierHandler.reassignRecordedTier(newPlayer)
                  end)
                  newPlayer:Say("My soul has returned to this body. All knowledge restored.")
                  return false
              end
          end

          -- Start with Strength/Fitness which need special handling
          print("[ZM_SecondChance] Starting Strength/Fitness processing...")
          Events.OnTick.Add(processStrengthFitness)

          -- Remove server command listener
          Events.OnServerCommand.Remove(onServerCommand)
      end
  end

  Events.OnServerCommand.Add(onServerCommand)
end

return PlayerProgressHandler