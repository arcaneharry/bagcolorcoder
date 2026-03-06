----------------------------------------------------------------------
-- BagColorCoder  –  Highlight combined-bag slots by which bag they belong to
-- and start a new row when the bag changes.
-- Compatible with WoW: Midnight (12.0 / Interface 120001)
----------------------------------------------------------------------

local ADDON_NAME = "BagColorCoder"

-- Bag constants
local BACKPACK     = Enum.BagIndex.Backpack                          -- 0
local NUM_BAGS     = Constants.InventoryConstants.NumBagSlots         -- 4
local REAGENT_BAGS = Constants.InventoryConstants.NumReagentBagSlots or 0

----------------------------------------------------------------------
-- Default colours (RGBA, 0-1)  
----------------------------------------------------------------------
local DEFAULT_COLORS = {
    [0] = { r = 1.0,  g = 0.4,  b = 0.7,  a = 0.8 },  -- Backpack  – pink
    [1] = { r = 0.3,  g = 0.6,  b = 1.0,  a = 0.8 },  -- Bag 1    – blue
    [2] = { r = 0.3,  g = 1.0,  b = 0.3,  a = 0.8 },  -- Bag 2    – green
    [3] = { r = 1.0,  g = 0.85, b = 0.2,  a = 0.8 },  -- Bag 3    – gold
    [4] = { r = 0.7,  g = 0.3,  b = 1.0,  a = 0.8 },  -- Bag 4    – purple
}
if REAGENT_BAGS > 0 then
    DEFAULT_COLORS[5] = { r = 1.0, g = 0.5, b = 0.0, a = 0.8 }
end

----------------------------------------------------------------------
-- Saved variable & runtime state
----------------------------------------------------------------------
local db
local overlays = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function CopyColor(src)
    return { r = src.r, g = src.g, b = src.b, a = src.a }
end

local function EnsureDefaults()
    if not BagColorCoderDB then BagColorCoderDB = {} end
    if BagColorCoderDB.enabled   == nil then BagColorCoderDB.enabled   = true end
    if BagColorCoderDB.breakRows == nil then BagColorCoderDB.breakRows = true end
    if not BagColorCoderDB.colors then
        BagColorCoderDB.colors = {}
        for bagID, c in pairs(DEFAULT_COLORS) do
            BagColorCoderDB.colors[bagID] = CopyColor(c)
        end
    end
    for bagID, c in pairs(DEFAULT_COLORS) do
        if not BagColorCoderDB.colors[bagID] then
            BagColorCoderDB.colors[bagID] = CopyColor(c)
        end
    end
    -- Clean up removed setting
    BagColorCoderDB.showLabels = nil
    db = BagColorCoderDB
end

----------------------------------------------------------------------
-- Helper: get bagID from a button
----------------------------------------------------------------------
local function GetButtonBagID(button)
    if button.GetBagID then return button:GetBagID() end
    if button.bagID ~= nil then return button.bagID end
    return nil
end

----------------------------------------------------------------------
-- Border overlay (4 edges per button)
----------------------------------------------------------------------
local BORDER_THICKNESS = 2

local function GetOrCreateOverlay(button)
    if overlays[button] then return overlays[button] end

    local tex = "Interface\\BUTTONS\\WHITE8X8"
    local b = {}

    b.top = button:CreateTexture(nil, "OVERLAY", nil, 2)
    b.top:SetTexture(tex)
    b.top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    b.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    b.top:SetHeight(BORDER_THICKNESS)

    b.bottom = button:CreateTexture(nil, "OVERLAY", nil, 2)
    b.bottom:SetTexture(tex)
    b.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    b.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    b.bottom:SetHeight(BORDER_THICKNESS)

    b.left = button:CreateTexture(nil, "OVERLAY", nil, 2)
    b.left:SetTexture(tex)
    b.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    b.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    b.left:SetWidth(BORDER_THICKNESS)

    b.right = button:CreateTexture(nil, "OVERLAY", nil, 2)
    b.right:SetTexture(tex)
    b.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    b.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    b.right:SetWidth(BORDER_THICKNESS)

    function b:Hide()  self.top:Hide(); self.bottom:Hide(); self.left:Hide(); self.right:Hide() end
    function b:Show()  self.top:Show(); self.bottom:Show(); self.left:Show(); self.right:Show() end
    function b:SetColor(r, g, _b, a)
        self.top:SetVertexColor(r, g, _b, a)
        self.bottom:SetVertexColor(r, g, _b, a)
        self.left:SetVertexColor(r, g, _b, a)
        self.right:SetVertexColor(r, g, _b, a)
    end

    b:Hide()
    overlays[button] = b
    return b
end

local function ColorizeButton(button)
    if not db or not db.enabled then return end
    local bagID = GetButtonBagID(button)
    if bagID == nil then return end
    local color = db.colors[bagID]
    if not color then return end
    local border = GetOrCreateOverlay(button)
    border:SetColor(color.r, color.g, color.b, color.a)
    border:Show()
end

local function HideAllOverlays()
    for _, b in pairs(overlays) do b:Hide() end
end

----------------------------------------------------------------------
-- CORE LAYOUT: reposition combined-bag buttons with row breaks
----------------------------------------------------------------------
local SLOT_SPACING  = 5       -- gap between slots
local ROW_EXTRA_GAP = 4       -- extra vertical gap between bag sections

local function RelayoutCombinedBags(frame)
    if not db or not db.enabled then return end
    if not frame or not frame.Items or #frame.Items == 0 then return end

    local items = frame.Items

    -- Button size
    local btnW = items[1]:GetWidth()
    local btnH = items[1]:GetHeight()
    if btnW == 0 then btnW = 37 end
    if btnH == 0 then btnH = 37 end

    -- Column count from frame width
    local frameW = frame:GetWidth()
    local innerW = frameW - 14
    local cols = math.max(1, math.floor((innerW + SLOT_SPACING) / (btnW + SLOT_SPACING)))

    -- Build ordered list with bag IDs
    local ordered = {}
    for _, btn in ipairs(items) do
        local bagID = GetButtonBagID(btn)
        if bagID ~= nil then
            ordered[#ordered + 1] = { btn = btn, bagID = bagID }
        end
    end
    if #ordered == 0 then return end

    -- Calculate where to start placing items: below the search bar / title bar
    local startX = 7
    local startY = -30  -- fallback

    local searchBox = frame.SearchBox or frame.searchBox or frame.FilterDropdown or nil
    if not searchBox and frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.HasFocus and child:IsShown() then
                searchBox = child
                break
            end
        end
    end

    if searchBox and searchBox:IsShown() then
        local frameTop = frame:GetTop() or 0
        local searchBottom = searchBox:GetBottom() or 0
        startY = searchBottom - frameTop - 6
    end

    -- If break-rows is off, lay out as a continuous grid (no bag gaps)
    if not db.breakRows then
        local col = 0
        local curY = startY
        for _, entry in ipairs(ordered) do
            if col >= cols then
                col = 0
                curY = curY - btnH - SLOT_SPACING
            end
            local x = startX + col * (btnW + SLOT_SPACING)
            entry.btn:ClearAllPoints()
            entry.btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, curY)
            col = col + 1
            ColorizeButton(entry.btn)
        end
        local totalH = math.abs(curY) + btnH + SLOT_SPACING + 40
        if totalH > frame:GetHeight() then
            frame:SetHeight(totalH)
        end
        return
    end

    -- Position buttons with row breaks at bag boundaries
    local col = 0
    local curY = startY
    local prevBagID = ordered[1].bagID

    for i, entry in ipairs(ordered) do
        local btn = entry.btn
        local bagID = entry.bagID

        -- Bag boundary → force new row
        if bagID ~= prevBagID then
            col = 0
            curY = curY - btnH - SLOT_SPACING - ROW_EXTRA_GAP
            prevBagID = bagID
        end

        -- Normal column wrap
        if col >= cols then
            col = 0
            curY = curY - btnH - SLOT_SPACING
        end

        local x = startX + col * (btnW + SLOT_SPACING)

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, curY)
        col = col + 1

        ColorizeButton(btn)
    end

    -- Resize frame to fit content
    local totalH = math.abs(curY) + btnH + SLOT_SPACING + 40
    local minH = frame:GetHeight()
    if totalH > minH then
        frame:SetHeight(totalH)
    end
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
local function RefreshAllButtons()
    if not db or not db.enabled then return end

    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        RelayoutCombinedBags(ContainerFrameCombinedBags)
    end

    local containerParent = ContainerFrameContainer or UIParent
    if containerParent and containerParent.ContainerFrames then
        for _, frame in ipairs(containerParent.ContainerFrames) do
            if frame:IsShown() and frame.Items then
                for _, button in ipairs(frame.Items) do
                    ColorizeButton(button)
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------
local hookedFrames = {}

local function HookContainerFrame(frame)
    if hookedFrames[frame] then return end
    hookedFrames[frame] = true

    if frame.UpdateItems then
        hooksecurefunc(frame, "UpdateItems", function(self)
            if not db or not db.enabled then return end
            if self == ContainerFrameCombinedBags then
                RelayoutCombinedBags(self)
            elseif self.Items then
                for _, button in ipairs(self.Items) do
                    ColorizeButton(button)
                end
            end
        end)
    end
end

local function SetupHooks()
    if ContainerFrameCombinedBags then
        HookContainerFrame(ContainerFrameCombinedBags)
    end

    local containerParent = ContainerFrameContainer or UIParent
    if containerParent and containerParent.ContainerFrames then
        for _, frame in ipairs(containerParent.ContainerFrames) do
            HookContainerFrame(frame)
        end
    end

    hooksecurefunc("OpenBag", function()
        C_Timer.After(0.05, RefreshAllButtons)
    end)
    hooksecurefunc("OpenAllBags", function()
        C_Timer.After(0.05, RefreshAllButtons)
    end)
end

----------------------------------------------------------------------
-- Settings panel
----------------------------------------------------------------------
local SETTINGS_BAG_NAMES = {
    [0] = "Backpack",
    [1] = "Bag 1",
    [2] = "Bag 2",
    [3] = "Bag 3",
    [4] = "Bag 4",
}
if REAGENT_BAGS > 0 then SETTINGS_BAG_NAMES[5] = "Reagent Bag" end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame")
    panel.name = ADDON_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BagColorCoder")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Colour-code and separate bag slots in the combined bag view.")

    -- Helper to create a checkbox that works across WoW versions
    local function MakeCheckbox(parent, labelText, anchorTo, anchorPoint, xOff, yOff)
        local cb = CreateFrame("CheckButton", nil, parent)
        cb:SetSize(26, 26)
        cb:SetPoint(anchorPoint or "TOPLEFT", anchorTo, "BOTTOMLEFT", xOff or 0, yOff or -4)

        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

        local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)
        cb.label = label

        return cb
    end

    -- Enable checkbox
    local enableCB = MakeCheckbox(panel, "Enable bag colour borders", desc, "TOPLEFT", -2, -16)
    enableCB:SetChecked(db.enabled)
    enableCB:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked() and true or false
        if db.enabled then RefreshAllButtons() else HideAllOverlays() end
    end)

    -- Row-break checkbox
    local breakCB = MakeCheckbox(panel, "New row for each bag (combined view)", enableCB, "TOPLEFT", 0, -4)
    breakCB:SetChecked(db.breakRows)
    breakCB:SetScript("OnClick", function(self)
        db.breakRows = self:GetChecked() and true or false
        RefreshAllButtons()
    end)

    -- Colour pickers
    local prevAnchor = breakCB

    for bagIdx = 0, NUM_BAGS + REAGENT_BAGS do
        local label = SETTINGS_BAG_NAMES[bagIdx] or ("Bag " .. bagIdx)
        local color = db.colors[bagIdx]
        if not color then
            color = { r = 1, g = 1, b = 1, a = 0.8 }
            db.colors[bagIdx] = color
        end

        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(300, 26)
        row:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -10)
        prevAnchor = row

        local swatch = CreateFrame("Button", nil, row)
        swatch:SetSize(20, 20)
        swatch:SetPoint("LEFT", 4, 0)

        local swatchTex = swatch:CreateTexture(nil, "BACKGROUND")
        swatchTex:SetAllPoints()
        swatchTex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        swatchTex:SetVertexColor(color.r, color.g, color.b, 1)

        local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        txt:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        txt:SetText(label)

        local slider = CreateFrame("Slider", nil, row, BackdropTemplateMixin and "BackdropTemplate" or nil)
        slider:SetSize(120, 16)
        slider:SetPoint("LEFT", txt, "RIGHT", 16, 0)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(0, 1)
        slider:SetValueStep(0.05)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(color.a)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })

        local sliderText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sliderText:SetPoint("TOP", slider, "BOTTOM", 0, -1)
        sliderText:SetText(math.floor(color.a * 100) .. "%")

        local bagIndex = bagIdx

        slider:SetScript("OnValueChanged", function(self, value)
            db.colors[bagIndex].a = value
            sliderText:SetText(math.floor(value * 100) .. "%")
            RefreshAllButtons()
        end)

        swatch:SetScript("OnClick", function()
            local c = db.colors[bagIndex]
            local function OnColorChanged()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                c.r, c.g, c.b = r, g, b
                swatchTex:SetVertexColor(r, g, b, 1)
                RefreshAllButtons()
            end
            local function OnCancel(prev)
                c.r, c.g, c.b = prev.r, prev.g, prev.b
                swatchTex:SetVertexColor(c.r, c.g, c.b, 1)
                RefreshAllButtons()
            end
            local info = {}
            info.r, info.g, info.b = c.r, c.g, c.b
            info.swatchFunc = OnColorChanged
            info.cancelFunc = OnCancel
            info.hasOpacity = false
            ColorPickerFrame:SetupColorPickerAndShow(info)
        end)
    end

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 24)
    resetBtn:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 4, -20)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        for bagID, c in pairs(DEFAULT_COLORS) do
            db.colors[bagID] = CopyColor(c)
        end
        db.enabled = true
        db.breakRows = true
        ReloadUI()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
        category.ID = ADDON_NAME
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

----------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------
SLASH_BAGCOLORCODER1 = "/bagcolor"
SLASH_BAGCOLORCODER2 = "/bcc"
SlashCmdList["BAGCOLORCODER"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "toggle" then
        db.enabled = not db.enabled
        if db.enabled then
            RefreshAllButtons()
            print("|cff00ccffBagColorCoder|r: Enabled")
        else
            HideAllOverlays()
            print("|cff00ccffBagColorCoder|r: Disabled")
        end
    elseif msg == "break" then
        db.breakRows = not db.breakRows
        RefreshAllButtons()
        print("|cff00ccffBagColorCoder|r: Row break per bag " .. (db.breakRows and "ON" or "OFF"))
    elseif msg == "reset" then
        for bagID, c in pairs(DEFAULT_COLORS) do
            db.colors[bagID] = CopyColor(c)
        end
        db.enabled = true
        db.breakRows = true
        RefreshAllButtons()
        print("|cff00ccffBagColorCoder|r: Reset to defaults.")
    else
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ADDON_NAME)
        elseif InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(ADDON_NAME)
            InterfaceOptionsFrame_OpenToCategory(ADDON_NAME)
        end
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDefaults()
        CreateSettingsPanel()
        SetupHooks()
        print("|cff00ccffBagColorCoder|r loaded. |cffffd100/bcc|r settings  |cffffd100/bcc break|r toggle row breaks")
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, RefreshAllButtons)
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        C_Timer.After(0.1, RefreshAllButtons)
    end
end)
