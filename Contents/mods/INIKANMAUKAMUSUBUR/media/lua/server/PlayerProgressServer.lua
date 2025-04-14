PlayerProgressServer = {}
local progressFilePath = "playerprogress" -- Base directory without slash
local progressInMemory = {}

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

-- Modified function to save the player's progress to a separate file
function PlayerProgressServer.saveProgressToFile(username, progress)
    -- Sanitize username for safe file operations
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
    local userFilePath = progressFilePath .. "_" .. sanitizedUsername .. ".ini"

    print("[ZM_SecondChance] Saving progress for user: " .. username .. " to file: " .. userFilePath)

    -- Serialize and save directly to the user-specific file
    local fileWriter = getFileWriter(userFilePath, true, false)
    if fileWriter then
        local serializedData = serializeTable(progress) -- Serialize the progress table
        fileWriter:write(serializedData)
        fileWriter:close()
        print("[ZM_SecondChance] Successfully saved progress for user: " .. username)
        return true
    else
        print("[ZM_SecondChance] ERROR: Failed to open file for writing: " .. userFilePath)
        return false
    end
end

-- Modified function to load progress from a separate file
function PlayerProgressServer.loadProgressFromFile(username)
    -- Sanitize username for safe file operations
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
    local userFilePath = progressFilePath .. "_" .. sanitizedUsername .. ".ini"

    print("[ZM_SecondChance] Loading progress for user: " .. username .. " from file: " .. userFilePath)

    local file = getFileReader(userFilePath, true)
    if not file then
        print("[ZM_SecondChance] File not found: " .. userFilePath)
        return nil
    end

    -- Read the entire file content
    local content = ""
    local line = file:readLine()
    while line do
        content = content .. line
        line = file:readLine()
    end
    file:close()

    -- Deserialize the content
    local progress = nil
    if content and content ~= "" then
        progress = deserializeTable(content)
        print("[ZM_SecondChance] Progress loaded successfully for user: " .. username)
    else
        print("[ZM_SecondChance] Empty content in file: " .. userFilePath)
    end

    return progress
end

-- Modified function to save all progress to files (saves each user to their own file)
function PlayerProgressServer.saveAllProgressToFile()
    for username, progress in pairs(progressInMemory) do
        PlayerProgressServer.saveProgressToFile(username, progress)
    end
    print("[ZM_SecondChance] All in-memory progress have been saved to individual files.")
end

function PlayerProgressServer.handleClientSaveProgress(username, progress)
    print("[ZM_SecondChance] Handling save progress for user: " .. username)
    progressInMemory[username] = progress
    local success = PlayerProgressServer.saveProgressToFile(username, progress)
    print("[ZM_SecondChance] Save success: " .. tostring(success) .. " for user: " .. tostring(username))
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
      if command == "saveProgress" then
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