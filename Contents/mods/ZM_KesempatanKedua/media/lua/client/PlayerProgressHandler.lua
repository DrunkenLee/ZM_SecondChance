require "PlayerProgressServer"
require "PlayerTierHandler"


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

  -- Define allowed ModData keys based on the example
  local allowedModDataKeys = {
      "TrueMusicJukebox", "hotbar", "CHC_item_favorites", "tad",
      "Moodles", "PlayerTier", "PlayerTierValue", "ispwn",
      "SRJPassiveSkillsInit", "BrutalHandwork", "TimeSprite",
      "ProjectileTimer", "ProjectileHit", "Reducer", "LastBD"
  }

  -- Filter ModData to only include the allowed keys
  for _, key in ipairs(allowedModDataKeys) do
      if modData[key] then
          progress.ModData[key] = modData[key]
      end
  end

  -- Filter LastBD to only include specified body parts
  if progress.ModData.LastBD then
      local allowedBodyParts = {
          "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R",
          "Torso_Upper", "Torso_Lower", "Head", "Neck", "Groin",
          "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R"
      }

      local filteredLastBD = {}
      for _, part in ipairs(allowedBodyParts) do
          if progress.ModData.LastBD[part] then
              filteredLastBD[part] = progress.ModData.LastBD[part]
          end
      end

      progress.ModData.LastBD = filteredLastBD
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

  -- Define a temporary listener for the server response
  local function onServerCommand(module, command, args)
      if module == "PlayerProgressServer" and command == "saveProgressResponse" then
          if args.username == username then
              print("[ZM_SecondChance] Received saveProgressResponse for user: " .. args.username)
              print("Progress: " .. tostring(args.progress))
              player:Say("Progress saved successfully!")
              -- Remove the listener after handling the response
              Events.OnServerCommand.Remove(onServerCommand)
          end
      end
  end
  Events.OnServerCommand.Add(onServerCommand)

  -- Send the save progress request to the server
  sendClientCommand(player, "PlayerProgressServer", "saveProgress", { username = username, progress = progress })
  print("[ZM_SecondChance] Save progress request sent to server for user: " .. username)
end

-- Function to transfer progress data from one username to another
function PlayerProgressHandler.transferProgress(oldUsername, newPlayer)
  print("[ZM_SecondChance] Requesting server to load progress for user: " .. oldUsername)
  -- Request the server to load the progress data for the old username
  sendClientCommand(newPlayer, "PlayerProgressServer", "loadProgress", { username = oldUsername })

  -- Define the listener function
  local function onServerCommand(module, command, args)
      if module == "PlayerProgressServer" and command == "loadProgressResponse" then
          local progress = args.progress
          if not progress then
              print("[ZM_SecondChance] No progress data found for user: " .. oldUsername)
              -- Remove the listener after handling the response
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

          -- Remove the listener after handling the response
          Events.OnServerCommand.Remove(onServerCommand)
      end
  end

  -- Add the listener for OnServerCommand
  Events.OnServerCommand.Add(onServerCommand)
end

return PlayerProgressHandler

