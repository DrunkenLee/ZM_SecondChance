require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISLabel"
require "PlayerProgressHandler"

PerkProgressUI = ISPanel:derive("PerkProgressUI")

function PerkProgressUI:initialise()
    ISPanel.initialise(self)

    -- Create a title bar
    self.titleBar = ISPanel:new(0, 0, self.width, 50)
    self.titleBar:initialise()
    self.titleBar.backgroundColor = {r=0.2, g=0.2, b=0.2, a=0.8}
    self:addChild(self.titleBar)

    -- Create title text
    self.titleLabel = ISLabel:new(10, 2, 20, "Saved Perk Progress Confirmation", 1, 1, 1, 1, UIFont.Medium, true)
    self.titleLabelTwo = ISLabel:new(10, 22, 20, "is this data correct ?", 1, 1, 1, 1, UIFont.Medium, true)
    self.titleBar:addChild(self.titleLabel)
    self.titleBar:addChild(self.titleLabelTwo)

    -- Create close button
    self.closeButton = ISButton:new(self.width - 30, 0, 30, 20, "X", self, PerkProgressUI.onCloseButtonClick)
    self.closeButton.backgroundColor = {r=0.5, g=0.0, b=0.0, a=1.0}
    self.closeButton.backgroundColorMouseOver = {r=1.0, g=0.0, b=0.0, a=1.0}
    self.titleBar:addChild(self.closeButton)

    -- Create perk list
    self.perkList = ISScrollingListBox:new(10, 65, self.width - 20, self.height - 70)
    self.perkList:initialise()
    self.perkList:setFont(UIFont.Small, 3)
    self.perkList.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.8}
    self:addChild(self.perkList)

    -- Add status label
    self.statusLabel = ISLabel:new(10, self.height - 30, 20, "", 1, 1, 1, 1, UIFont.Small, false)
    self:addChild(self.statusLabel)

    -- Create buttons at bottom
    self.loadButton = ISButton:new(10, self.height - 30, self.width/2 - 15, 20, "Refresh", self, PerkProgressUI.loadFromINI)
    self.loadButton.backgroundColor = {r=0.2, g=0.4, b=0.2, a=0.8}
    self.loadButton.backgroundColorMouseOver = {r=0.3, g=0.5, b=0.3, a=0.8}
    self:addChild(self.loadButton)

    self.confirmButton = ISButton:new(self.width/2 + 5, self.height - 30, self.width/2 - 15, 20, "Confirm", self, PerkProgressUI.onConfirmButtonClick)
    self.confirmButton.backgroundColor = {r=0.2, g=0.4, b=0.2, a=0.8}
    self.confirmButton.backgroundColorMouseOver = {r=0.3, g=0.5, b=0.3, a=0.8}
    self:addChild(self.confirmButton)

    self.closeButtonBottom = ISButton:new(self.width/2 + 5, self.height - 30, self.width/2 - 15, 20, "Close", self, PerkProgressUI.onCloseButtonClick)
    self.closeButtonBottom.backgroundColor = {r=0.5, g=0.0, b=0.0, a=0.8}
    self.closeButtonBottom.backgroundColorMouseOver = {r=0.6, g=0.0, b=0.0, a=0.8}
    -- self:addChild(self.closeButtonBottom)

    -- Register for server events
    self:setupServerListeners()

    -- Load the saved perks data for current player automatically
    self:loadFromINI()
end

function PerkProgressUI:setupServerListeners()
    -- Remove any existing listeners
    if self.onServerCommandFunction then
        Events.OnServerCommand.Remove(self.onServerCommandFunction)
    end

    -- Create a new listener
    self.onServerCommandFunction = function(module, command, args)
        if module == "PlayerProgressServer" and command == "loadProgressResponse" then
            -- Process the loaded progress data
            if args.progress then
                self:displayProgress(args.progress, args.username)
            else
                self.perkList:clear()
            end
        end
    end

    Events.OnServerCommand.Add(self.onServerCommandFunction)
end

function PerkProgressUI:loadFromINI()
    local player = getPlayer()
    if not player then return end

    local username = player:getUsername()
    if not username or username == "" then
        username = player:getDisplayName() -- Fallback to display name
    end

    if username and username ~= "" then
        sendClientCommand(player, "PlayerProgressServer", "loadProgress", { username = username })
    else

    end
end

function PerkProgressUI:displayProgress(progress, username)
    self.perkList:clear()

    -- Debug the type of progress.Perks
    print("Progress.Perks type: " .. type(progress.Perks))

    -- Parse perks data if it's a string
    local perksData = {}
    if type(progress.Perks) == "string" then
        print("Parsing perk string: " .. progress.Perks)
        local perksStr = progress.Perks
        for perkData in string.gmatch(perksStr, "([^;]+)") do
            local perkName, xpValue = string.match(perkData, "([^=]+)=([^=]+)")
            if perkName and xpValue then
                perksData[perkName] = tonumber(xpValue) or 0
                print("Parsed: " .. perkName .. " = " .. perksData[perkName])
            end
        end
    else
        perksData = progress.Perks
    end

    -- Parse boosts data if applicable
    local boostsData = {}
    if progress.Boosts then
        if type(progress.Boosts) == "string" then
            for boostData in string.gmatch(progress.Boosts, "([^;]+)") do
                local boostName, boostValue = string.match(boostData, "([^=]+)=([^=]+)")
                if boostName and boostValue then
                    boostsData[boostName] = tonumber(boostValue) or 0
                end
            end
        else
            boostsData = progress.Boosts
        end
    end

    -- Sort perks by name
    local sortedPerks = {}
    for perkName, xp in pairs(perksData) do
        table.insert(sortedPerks, {name = perkName, xp = xp})
    end

    table.sort(sortedPerks, function(a, b) return a.name < b.name end)

    -- Add perks to the list
    for _, perk in ipairs(sortedPerks) do
        local perkObj = PerkFactory.getPerkFromName(perk.name)
        if perkObj then
            local xpValue = tonumber(perk.xp) or 0
            local estimatedLevel = PerkProgressUI.estimateLevelFromXP(perk.name, xpValue)

            -- Format XP value with comma separators for readability
            local formattedXP = tostring(xpValue)
            if xpValue >= 1000 then
                -- Add commas for thousands
                while true do
                    formattedXP, k = string.gsub(formattedXP, "^(-?%d+)(%d%d%d)", '%1,%2')
                    if k == 0 then break end
                end
            end


            local perkText = string.format(perk.name .. " (XpValue %d)", xpValue)
            -- Show perks with XP > 0 (or all perks if desired)
            if xpValue > 0 then
                local item = self.perkList:addItem(perkText, formattedXP) -- Use perkText, not perk.xp

                if xpValue >= 30000 then
                    item.backgroundColor = {r=0.0, g=0.5, b=0.0, a=0.3} -- Green for high level
                elseif xpValue >= 15000 then
                    item.backgroundColor = {r=0.5, g=0.5, b=0.0, a=0.3} -- Yellow for medium level
                else
                    item.backgroundColor = {r=0.5, g=0.0, b=0.0, a=0.3} -- Red for low level
                end
            end
        end
    end
end

-- Utility function to estimate level from XP
function PerkProgressUI.estimateLevelFromXP(perkName, xp)
    local perk = PerkFactory.getPerkFromName(perkName)
    if not perk then return 0 end

    local level = 0
    local remainingXP = xp

    while true do
        local nextLevelXP = perk:getXpForLevel(level + 1)
        if remainingXP >= nextLevelXP then
            level = level + 1
            remainingXP = remainingXP - nextLevelXP
        else
            break
        end

        -- Safety check to avoid infinite loops
        if level >= 10 then break end
    end

    return level
end

function PerkProgressUI:onCloseButtonClick()
    -- Clean up listeners
    if self.onServerCommandFunction then
        Events.OnServerCommand.Remove(self.onServerCommandFunction)
    end

    -- Set the consent value to 0 (declined)
    self.userConsent = 0

    -- Trigger any callback if registered
    if self.onConfirmCallback then
        self.onConfirmCallback(self.userConsent)
    end

    self:setVisible(false)
    self:removeFromUIManager()

    return self.userConsent
end

function PerkProgressUI:onConfirmButtonClick()
    -- Clean up listeners
    if self.onServerCommandFunction then
        Events.OnServerCommand.Remove(self.onServerCommandFunction)
    end

    -- Set the consent value to 1 (confirmed)
    self.userConsent = 1

    -- Trigger any callback if registered
    if self.onConfirmCallback then
        self.onConfirmCallback(self.userConsent)
    end

    self:setVisible(false)
    self:removeFromUIManager()

    return self.userConsent
end

function PerkProgressUI:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.variableColor = {r=0.9, g=0.55, b=0.1, a=1.0}
    o.borderColor = {r=0.4, g=0.4, b=0.4, a=1.0}
    o.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.8}
    o.moveWithMouse = true
    o.userConsent = 0 -- Default to no consent
    return o
end

-- Add a method to set a callback for when the user confirms/declines
function PerkProgressUI:setConfirmationCallback(callback)
    self.onConfirmCallback = callback
end

-- Function to create and show the UI
function PerkProgressUI.ShowUI()
    local width = 450
    local height = 500
    local x = getCore():getScreenWidth() / 2 - width / 2
    local y = getCore():getScreenHeight() / 2 - height / 2

    local ui = PerkProgressUI:new(x, y, width, height)
    ui:initialise()
    ui:addToUIManager()
    return ui
end

-- Console-safe function with error handling
function ShowPerkUI()
    local success, result = pcall(function()
        return PerkProgressUI.ShowUI()
    end)

    if success then
        print("UI opened successfully")
        return result
    else
        print("Error creating UI: " .. tostring(result))
        return nil
    end
end

-- Add key binding to toggle UI
local function OnKeyPressed(key)
    if key == Keyboard.KEY_P and isKeyDown(Keyboard.KEY_LSHIFT) then  -- Shift+P to open the UI
        if not PerkProgressUI.instance or not PerkProgressUI.instance:isVisible() then
            PerkProgressUI.instance = PerkProgressUI.ShowUI()
        else
            PerkProgressUI.instance:onCloseButtonClick()
        end
    end
end

-- Events.OnKeyPressed.Add(OnKeyPressed)

-- Global function for easy access from console
function ShowPerkProgress()
    if not PerkProgressUI.instance or not PerkProgressUI.instance:isVisible() then
        PerkProgressUI.instance = PerkProgressUI.ShowUI()
    else
        PerkProgressUI.instance:onCloseButtonClick()
    end
    return "Perk Progress UI toggled"
end