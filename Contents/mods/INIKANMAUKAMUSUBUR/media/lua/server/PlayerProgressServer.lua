PlayerProgressServer = {}
local progressFilePath = "playerprogress/" -- Base directory without slash
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

function PlayerProgressServer.saveProgressToFile(username, progress)
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
    local userFilePath = progressFilePath .. "_" .. sanitizedUsername .. ".ini"

    print("[ZM_SecondChance] Saving progress for user: " .. username .. " to file: " .. userFilePath)

    -- Always use truncate mode (false for append) to ensure we're writing to a clean file
    local fileWriter = getFileWriter(userFilePath, true, false)
    if fileWriter then
        local serializedData = serializeTable(progress)
        fileWriter:write(serializedData)
        fileWriter:close()
        print("[ZM_SecondChance] Successfully saved progress for user: " .. username)
        return true
    else
        print("[ZM_SecondChance] ERROR: Failed to open file for writing: " .. userFilePath)
        return false
    end
end

function PlayerProgressServer.loadProgressFromFile(username)
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
    local userFilePath = progressFilePath .. "_" .. sanitizedUsername .. ".ini"

    print("[ZM_SecondChance] Loading progress for user: " .. username .. " from file: " .. userFilePath)

    local file = getFileReader(userFilePath, true)
    if not file then
        print("[ZM_SecondChance] File not found: " .. userFilePath)
        return nil
    end

    local content = ""
    local line = file:readLine()
    while line do
        content = content .. line
        line = file:readLine()
    end
    file:close()

    local progress = nil
    if content and content ~= "" then
        progress = deserializeTable(content)
        print("[ZM_SecondChance] Progress loaded successfully for user: " .. username)
    else
        print("[ZM_SecondChance] Empty content in file: " .. userFilePath)
    end

    return progress
end

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

-- New backup function that works without os.rename
function PlayerProgressServer.archiveProgressFile(username)
    local sanitizedUsername = string.gsub(username, "[^%w_-]", "_")
    local userFilePath = progressFilePath .. "_" .. sanitizedUsername .. ".ini"
    local backupFilePath = userFilePath .. ".backup_" .. os.time()

    print("[ZM_SecondChance] Creating backup of progress file for: " .. username)

    -- Read the original file content
    local file = getFileReader(userFilePath, true)
    if file then
        -- Read all content
        local content = ""
        local line = file:readLine()
        while line do
            content = content .. line
            if file:readLine() then
                content = content .. "\n"
            end
            line = file:readLine()
        end
        file:close()

        -- Write content to a backup file
        local backupWriter = getFileWriter(backupFilePath, true, false)
        if backupWriter then
            backupWriter:write(content)
            backupWriter:close()
            print("[ZM_SecondChance] Successfully created backup at: " .. backupFilePath)

            -- Clear the original file to prevent XP stacking on next save
            local clearWriter = getFileWriter(userFilePath, true, false)
            if clearWriter then
                clearWriter:write("")
                clearWriter:close()
                print("[ZM_SecondChance] Cleared original file after backup: " .. userFilePath)
            end

            return true
        else
            print("[ZM_SecondChance] ERROR: Failed to create backup file: " .. backupFilePath)
            return false
        end
    else
        print("[ZM_SecondChance] No file to backup at: " .. userFilePath)
        return false
    end
end

function PlayerProgressServer.handleClientLoadProgressXP(username, requestId)
  print("[DEBUG] Looking for progress file for: " .. username)
  print("[DEBUG] Request ID: " .. tostring(requestId))

  -- First load the progress
  local progress = PlayerProgressServer.loadProgressFromFile(username)

  -- Send the progress data to client WITH the request ID to match the request
  sendServerCommand("PlayerProgressServer", "loadProgressResponse", {
      username = username,
      progress = progress,
      requestId = requestId  -- Echo back the request ID
  })
end

function PlayerProgressServer.handleClientLoadProgress(username)
    print("[DEBUG] Looking for progress file for: " .. username)
    print("[DEBUG] Checking path: " .. progressFilePath .. username .. ".ini")
    print("[DEBUG] Also checking: Lua/playerprogress_" .. username .. ".ini")
    print("[ZM_SecondChance] Handling load progress for user: " .. username)

    -- First load the progress
    local progress = PlayerProgressServer.loadProgressFromFile(username)

    -- Then create a backup before sending response
    if progress then
        PlayerProgressServer.archiveProgressFile(username)
    end

    -- Send the progress data to client
    sendServerCommand("PlayerProgressServer", "loadProgressResponse", { username = username, progress = progress })
end

function PlayerProgressServer.handleTrait(player, traits)
    print("[ZM_SecondChance] Handling trait application for player: " .. player:getUsername())
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
        elseif command == "loadProgressXP" then
            print("[ZM_SecondChance] Executing loadProgress for user: " .. tostring(args.username) .. " with request ID: " .. tostring(args.requestId))
            PlayerProgressServer.handleClientLoadProgressXP(args.username, args.requestId)
        elseif command == "loadProgressTRAIT" then
            print("[ZM_SecondChance] Executing loadProgressTRAIT for user: " .. tostring(args.username) .. " with request ID: " .. tostring(args.requestId))
            PlayerProgressServer.handleClientLoadProgressXP(args.username, args.requestId)
        elseif command == "loadProgressDisplayOnly" then
            print("[ZM_SecondChance] Executing loadProgressDisplayOnly for user: " .. tostring(args.username))
            local progress = PlayerProgressServer.loadProgressFromFile(args.username)
            sendServerCommand("PlayerProgressServer", "loadProgressDisplayOnlyResponse", { username = args.username, progress = progress })
        elseif command == "applyTraits" then
            print("[ZM_SecondChance] Executing applyTraits for player.")
            PlayerProgressServer.handleTrait(player, args.traits)
        elseif command == "clearTraits" then
            print("[ZM_SecondChance] Executing clearTraits for player.")
            player:getTraits():clear()
        elseif command == "testcoba" then
            print("[ZM_SecondChance] Test command received. Args: " .. tostring(args.testKey))
        else
            print("[ZM_SecondChance] Unknown command: " .. tostring(command))
        end
    end
end

Events.OnClientCommand.Add(OnClientCommand)

return PlayerProgressServer