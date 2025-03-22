PlayerProgressServer = {}
local progressFilePath = "server-player-progress.ini"
local progressInMemory = {}
local activeTransfers = {}

-- Function to serialize a table to a string
local function serializeTable(tbl)
  local function serialize(tbl, result)
      for k, v in pairs(tbl) do
          if type(k) ~= "string" and type(k) ~= "number" then
              error("Invalid key type in table: " .. tostring(k))
          end
          if type(v) == "table" then
              result[#result + 1] = tostring(k) .. "={" .. serializeTable(v) .. "}"
          elseif type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
              result[#result + 1] = tostring(k) .. "=" .. tostring(v)
          else
              error("Unsupported value type in table: " .. tostring(v))
          end
      end
  end

  if type(tbl) ~= "table" then
      error("Expected a table for serialization, got: " .. type(tbl))
  end

  local result = {}
  serialize(tbl, result)
  return table.concat(result, ";")
end

-- Function to deserialize a string to a table
local function deserializeTable(str)
    local function deserialize(str)
        local result = {}
        local key, value
        local i = 1
        while i <= #str do
            local char = str:sub(i, i)
            if char == "=" then
                key = str:sub(1, i - 1)
                str = str:sub(i + 1)
                i = 1
            elseif char == "{" then
                local count = 1
                local j = i + 1
                while count > 0 do
                    local c = str:sub(j, j)
                    if c == "{" then count = count + 1 end
                    if c == "}" then count = count - 1 end
                    j = j + 1
                end
                value = deserialize(str:sub(i + 1, j - 2))
                str = str:sub(j)
                i = 1
            elseif char == ";" then
                if not value then
                    value = str:sub(1, i - 1)
                end
                result[key] = value
                str = str:sub(i + 1)
                key, value = nil, nil
                i = 1
            else
                i = i + 1
            end
        end
        if key and not value then
            value = str
            result[key] = value
        end
        return result
    end

    return deserialize(str)
end

-- Function to save the player's progress to a file
function PlayerProgressServer.saveProgressToFile(username, progress)
    local data = {}
    print("[ZM_SecondChance] Saving progress for user: " .. username)

    local file = getFileReader(progressFilePath, true)
    if file then
        local line = file:readLine()
        while line do
            local user, traits = line:match("([^,]+),(.+)")
            if user and traits then
                data[user] = traits
            end
            line = file:readLine()
        end
        file:close()
    end

    data[username] = serializeTable(progress) -- Serialize the progress table

    local fileWriter = getFileWriter(progressFilePath, true, false)
    if fileWriter then
        for user, traits in pairs(data) do
            fileWriter:write(string.format("%s,%s\n", user, traits))
        end
        fileWriter:close()
        data[username] = nil
    else
        error("Failed to open file for writing: " .. progressFilePath)
    end
end

function PlayerProgressServer.saveAllProgressToFile()
    for username, progress in pairs(progressInMemory) do
        PlayerProgressServer.saveProgressToFile(username, progress)
    end
    print("[ZM_SecondChance] All in-memory progress have been saved to the file.")
end

function PlayerProgressServer.loadProgressFromFile(username)
    print("[ZM_SecondChance] Loading progress for user: " .. username)
    local file = getFileReader(progressFilePath, true)
    if not file then
        print("[ZM_SecondChance] File not found: " .. progressFilePath)
        return nil
    end

    local data = {}
    local line = file:readLine()
    while line do
        local user, traits = line:match("([^,]+),(.+)")
        if user and traits then
            data[user] = deserializeTable(traits) -- Deserialize the progress string
        end
        line = file:readLine()
    end
    file:close()

    local progress = data[username]
    print("[ZM_SecondChance] Progress for user " .. username .. ": " .. tostring(progress))
    return progress
end

-- Handle metadata for a new chunked transfer
function PlayerProgressServer.handleSaveProgressMetadata(username, transferId, metadata, totalChunks)
    print("[ZM_SecondChance] Starting new chunked transfer: " .. transferId .. " for user: " .. username)

    activeTransfers[transferId] = {
        username = username,
        progress = {
            Traits = {},
            Perks = {},
            Boosts = {},
            Recipes = {},
            ModData = {},
            Weight = metadata.weight or 0
        },
        receivedChunks = 0,
        totalChunks = totalChunks
    }

    return true
end

-- Handle an individual chunk for a transfer
function PlayerProgressServer.handleSaveProgressChunk(transferId, username, chunkType, data, chunkIndex, totalTypeChunks, chunkNum)
    print("[ZM_SecondChance] Processing chunk type: " .. chunkType .. " for transfer: " .. transferId)

    local transfer = activeTransfers[transferId]
    if not transfer then
        print("[ZM_SecondChance] ERROR: No active transfer found with ID: " .. transferId)
        return false
    end

    -- Process chunk based on type
    if chunkType == "traits" then
        transfer.progress.Traits = data
    elseif chunkType == "recipes" then
        transfer.progress.Recipes = data
    elseif chunkType == "perks" then
        -- For perks, merge chunks
        for k, v in pairs(data) do
            transfer.progress.Perks[k] = v
        end
    elseif chunkType == "boosts" then
        transfer.progress.Boosts = data
    elseif chunkType == "modData" then
        -- For modData, merge chunks
        for k, v in pairs(data) do
            transfer.progress.ModData[k] = v
        end
    end

    -- Track received chunks
    transfer.receivedChunks = transfer.receivedChunks + 1

    -- Send a response for this chunk
    sendServerCommand("PlayerProgressServer", "saveProgressChunkResponse", {
        transferId = transferId,
        username = username,
        chunkType = chunkType,
        chunkNum = chunkNum
    })

    -- If all chunks received, save the progress and clean up
    if transfer.receivedChunks >= transfer.totalChunks then
        print("[ZM_SecondChance] All " .. transfer.receivedChunks .. " chunks received for transfer: " .. transferId)
        progressInMemory[username] = transfer.progress
        PlayerProgressServer.saveProgressToFile(username, transfer.progress)
        activeTransfers[transferId] = nil
    end

    return true
end

function PlayerProgressServer.handleClientSaveProgress(username, progress)
    print("[ZM_SecondChance] Handling save progress for user: " .. username)
    progressInMemory[username] = progress
    PlayerProgressServer.saveProgressToFile(username, progress)
    print("[ZM_SecondChance] Args sent: " .. tostring(username) .. ", Progress: " .. tostring(progress))
    sendServerCommand("PlayerProgressServer", "saveProgressResponse", { username = username, progress = progress })
end

function PlayerProgressServer.handleClientLoadProgress(username)
    print("[ZM_SecondChance] Handling load progress for user: " .. username)
    local progress = PlayerProgressServer.loadProgressFromFile(username)
    sendServerCommand("PlayerProgressServer", "loadProgressResponse", { username = username, progress = progress })
end

function PlayerProgressServer.handleTrait(player, traits)
    player:getTraits():clear()
    for _, trait in pairs(traits) do
        print("[ZM_SecondChance] Adding trait: " .. trait .. " to player")
        player:getTraits():add(trait)
    end
end

local function OnClientCommand(module, command, player, args)
  if module == "PlayerProgressServer" then
      if command == "saveProgressMetadata" then
          print("[ZM_SecondChance] Executing saveProgressMetadata for user: " .. tostring(args.username))
          PlayerProgressServer.handleSaveProgressMetadata(args.username, args.transferId, args.metadata, args.totalChunks)
      elseif command == "saveProgressChunk" then
          print("[ZM_SecondChance] Executing saveProgressChunk for transfer: " .. tostring(args.transferId))
          PlayerProgressServer.handleSaveProgressChunk(args.transferId, args.username, args.chunkType, args.data, args.chunkIndex, args.totalTypeChunks, args.chunkNum)
      elseif command == "saveProgress" then
          print("[ZM_SecondChance] Executing saveProgress for user: " .. tostring(args.username))
          PlayerProgressServer.handleClientSaveProgress(args.username, args.progress)
      elseif command == "loadProgress" then
          print("[ZM_SecondChance] Executing loadProgress for user: " .. tostring(args.username))
          PlayerProgressServer.handleClientLoadProgress(args.username)
      elseif command == "applyTraits" then
          print("[ZM_SecondChance] Executing applyTraits for player.")
          PlayerProgressServer.handleTrait(player, args.traits)
      elseif command == "testcoba" then
          print("[ZM_SecondChance] Test command received. Args: " .. tostring(args.testKey))
      else
          print("[ZM_SecondChance] Unknown command: " .. tostring(command))
      end
  end
end

Events.OnClientCommand.Add(OnClientCommand)

return PlayerProgressServer