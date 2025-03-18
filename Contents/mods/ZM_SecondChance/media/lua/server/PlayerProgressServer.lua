PlayerProgressServer = {}
local progressFilePath = "server-player-progress.ini"
local progressInMemory = {}

-- Function to save the player's progress to a file
function PlayerProgressServer.saveProgressToFile(username, progress)
    local data = {}
    print("[ZM_SecondChance] Saving progress for user: " .. username)

    local file = getFileReader(progressFilePath, true)
    if file then
        local line = file:readLine()
        while line do
            local user, traits = line:match("([^,]+),([^,]+)")
            data[user] = traits
            line = file:readLine()
        end
        file:close()
    end

    data[username] = progress

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
        local user, traits = line:match("([^,]+),([^,]+)")
        data[user] = traits
        line = file:readLine()
    end
    file:close()

    local progress = data[username]
    print("[ZM_SecondChance] Progress for user " .. username .. ": " .. tostring(progress))
    return progress
end

function PlayerProgressServer.handleClientSaveProgress(username, progress)
    print("[ZM_SecondChance] Saving progress for user: " .. username)
    progressInMemory[username] = progress
    PlayerProgressServer.saveProgressToFile(username, progress)
end

function PlayerProgressServer.handleClientLoadProgress(username)
    local progress = PlayerProgressServer.loadProgressFromFile(username)
    sendServerCommand("PlayerProgressServer", "loadProgressResponse", { username = username, progress = progress })
end

local function OnClientCommand(module, command, player, args)
    if module == "PlayerProgressServer" then
        if command == "saveProgress" then
            PlayerProgressServer.handleClientSaveProgress(args.username, args.progress)
        elseif command == "loadProgress" then
            PlayerProgressServer.handleClientLoadProgress(args.username)
        end
    end
end

Events.OnClientCommand.Add(OnClientCommand)

return PlayerProgressServer