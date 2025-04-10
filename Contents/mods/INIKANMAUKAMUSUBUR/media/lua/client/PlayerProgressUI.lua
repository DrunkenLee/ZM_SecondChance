require "PlayerProgressHandler"

-- Store the last saved progress data
local lastSavedProgress = {
    username = nil,
    perks = nil,
    timestamp = nil
}

local UI

-- Function to format perks for display
local function formatPerksText(perks)
    local text = "<H1>Progress Saved Successfully!<LINE><SIZE:small>"

    -- Sort perks by name
    local perksList = {}
    for perkName, xp in pairs(perks) do
        table.insert(perksList, {name = perkName, xp = xp})
    end
    table.sort(perksList, function(a, b) return a.name < b.name end)

    -- Add each perk with level calculation
    for _, perkData in ipairs(perksList) do
        local perk = PerkFactory.getPerkFromName(perkData.name)
        local level = 0

        if perk then
            local currentXP = perkData.xp
            while currentXP >= perk:getXpForLevel(level + 1) do
                currentXP = currentXP - perk:getXpForLevel(level + 1)
                level = level + 1
            end
        end

        text = text .. "<LINE>" .. perkData.name .. ": Level " .. level .. " (XP: " .. math.floor(perkData.xp) .. ")"
    end

    return text
end

-- Function to close the UI
local function closeUI()
    if UI then
        UI:close()
        UI = nil
    end
end

-- Function to display saved progress
function showSavedProgress(username, perks)
    -- Close existing UI if open
    closeUI()

    -- Create new UI
    UI = NewUI(0.6) -- Using 60% of screen width

    -- Add window title
    UI:addText("title", "Player Progress - " .. username, "Title", "Center")
    UI["title"]:setBorder(true)
    UI:nextLine()

    -- Add progress details in a rich text element
    local perksText = formatPerksText(perks)
    UI:addRichText("progress", perksText)
    UI:nextLine()

    -- Add close button
    UI:addButton("closeBtn", "Close", closeUI)
    UI:nextLine()

    -- Save the layout
    UI:saveLayout()
end

-- Store progress data when saved
Events.OnServerCommand.Add(function(module, command, args)
    if module == "PlayerProgressServer" and command == "saveProgressResponse" then
        local username = args.username
        if args.progress and args.progress.Perks then
            -- Store the progress data for later display
            lastSavedProgress.username = username
            lastSavedProgress.perks = args.progress.Perks
            lastSavedProgress.timestamp = getGameTime():getWorldAgeHours()
            print("[ZM_SecondChance] Progress data stored for " .. username)
        end
    end
end)

-- Show UI when pressing Numpad 6 - using proper key code
local function onKeyPressed(key)
    -- Numpad 6 is key code 102
    if key == 102 then
        print("[ZM_SecondChance] Numpad 6 pressed, trying to show progress UI")
        if lastSavedProgress.username and lastSavedProgress.perks then
            print("[ZM_SecondChance] Showing progress for " .. lastSavedProgress.username)
            showSavedProgress(lastSavedProgress.username, lastSavedProgress.perks)
        else
            -- No saved progress data available
            local player = getPlayer()
            if player then
                player:Say("No saved progress data available yet.")
                print("[ZM_SecondChance] No progress data available to display")
            end
        end
    end
end

-- Register key binding
Events.OnKeyPressed.Add(onKeyPressed)

-- For testing purposes - add direct call through a chat command
local function onServerCommand(module, command, args)
    if module == "PlayerProgressDebug" and command == "showUI" then
        if lastSavedProgress.username and lastSavedProgress.perks then
            showSavedProgress(lastSavedProgress.username, lastSavedProgress.perks)
        else
            getPlayer():Say("No saved progress data available yet.")
        end
    end
end
Events.OnServerCommand.Add(onServerCommand)

-- Clean up the UI on player death or logout
Events.OnPlayerDeath.Add(closeUI)

-- Export for other files to use
PlayerProgressUI = {
    showSavedProgress = showSavedProgress,
    closeUI = closeUI
}

return PlayerProgressUI