--[[
    YUEN | 99 Nights in the Forest — Scout & Survival Assistant
    Version: 1.0

    Client-side, read-only helper:
      * Rayfield UI with category toggles
      * Local highlights for recognizable nearby world objects
      * Object-name diagnostics to help adapt to game updates
      * Survival notes based on public game guides

    It intentionally does NOT fire game remotes, grant items, auto-rescue,
    auto-collect, teleport, modify server state, or bypass server validation.
    Object names are heuristic and may change when the game updates.

    Public references consulted:
      https://www.roblox.com/games/79546208627805/99-Nights-in-the-Forest
      https://99nightsinforest.wiki/wiki/campfire/
      https://99nightsinforest.wiki/wiki/chests/
      https://99nightsinforest.wiki/wiki/missing-children/
      https://99nightsinforest.wiki/wiki/materials/
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local Rayfield
local success, result = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not success or not result then
    warn("[YUEN 99 Nights] Could not load Rayfield: " .. tostring(result))
    return
end
Rayfield = result

local Window = Rayfield:CreateWindow({
    Name = "YUEN | 99 Nights",
    LoadingTitle = "YUEN Scout",
    LoadingSubtitle = "99 Nights in the Forest",
    Theme = "Amethyst",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = { Enabled = false }
})

local OverviewTab = Window:CreateTab("Overview", 4483362458)
local ScoutTab = Window:CreateTab("World Scout", 4483362458)
local DiagnosticsTab = Window:CreateTab("Diagnostics", 4483362458)
local GuideTab = Window:CreateTab("Survival Guide", 4483362458)

local MAX_DISTANCE = 250
local SCAN_INTERVAL = 7
local RUNNING = true
local VISUALS = {} -- [target] = {Category, Highlight, Billboard, Label}
local Enabled = {
    Children = false,
    Chests = false,
    Resources = false,
    Enemies = false,
    Campfire = false,
    Locations = false
}

local CategoryInfo = {
    Children = {Color = Color3.fromRGB(255, 105, 180), Emoji = "CHILD"},
    Chests = {Color = Color3.fromRGB(255, 205, 75), Emoji = "CHEST"},
    Resources = {Color = Color3.fromRGB(90, 220, 130), Emoji = "RESOURCE"},
    Enemies = {Color = Color3.fromRGB(255, 85, 85), Emoji = "HOSTILE"},
    Campfire = {Color = Color3.fromRGB(255, 145, 55), Emoji = "CAMPFIRE"},
    Locations = {Color = Color3.fromRGB(100, 190, 255), Emoji = "LOCATION"}
}

local CategoryByNameCache = {}

local Keywords = {
    Children = {
        "dinokid", "krakenkid", "squidkid", "koalakid", "missingchild",
        "missingkid", "childcage", "kidcage", "children", "cage"
    },
    Chests = {"chest", "supplycrate", "supplydrop", "lootcrate"},
    Resources = {
        "scrap", "coal", "log", "wood", "fuelcanister", "canister", "oilbarrel",
        "biofuel", "gasoline", "gascan", "medkit", "bandage", "carrot", "berry",
        "berries", "meat", "seed", "pelt", "ammo", "brokenfan", "brokenradio",
        "metalchair", "oldcarengine", "washingmachine", "rabbit", "firewood"
    },
    Enemies = {
        "cultist", "deer", "ram", "owl", "bat", "wolf", "bear", "frog",
        "mammoth", "arcticfox", "polar bear", "thecat", "monster", "alpha wolf"
    },
    Campfire = {"campfire", "camp fire", "firepit", "fire pit"},
    Locations = {
        "stronghold", "cave", "cavern", "workshop", "cabin", "shack", "temple",
        "bunker", "clinic", "armory", "tower", "volcano", "mothership", "ufo",
        "frog cave", "ice temple", "tool workshop"
    }
}

local function normalize(value)
    return tostring(value or ""):lower():gsub("[%s_%-]", "")
end

local function getCategoryFromName(name)
    local n = normalize(name)
    if CategoryByNameCache[n] ~= nil then
        return CategoryByNameCache[n] or nil
    end
    -- Order matters: specific targets are classified before broader ones.
    local order = {"Children", "Enemies", "Chests", "Campfire", "Resources", "Locations"}
    for _, category in ipairs(order) do
        for _, keyword in ipairs(Keywords[category]) do
            if n:find(normalize(keyword), 1, true) then
                CategoryByNameCache[n] = category
                return category
            end
        end
    end
    CategoryByNameCache[n] = false
    return nil
end

local function resolveTarget(candidate)
    local current = candidate
    while current and current ~= Workspace do
        local category = getCategoryFromName(current.Name)
        if category then
            if current:IsA("Model") or current:IsA("BasePart") then
                return category, current
            end
        end
        current = current.Parent
    end
    return nil, nil
end

local function getAnchor(target)
    if not target or not target.Parent then return nil end
    if target:IsA("BasePart") then return target end
    if target:IsA("Model") then
        if target.PrimaryPart then return target.PrimaryPart end
        for _, descendant in ipairs(target:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end
    return nil
end

local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getDistance(target)
    local root = getRoot()
    local anchor = getAnchor(target)
    if not root or not anchor then return math.huge end
    return (root.Position - anchor.Position).Magnitude
end

local function makeLabel(target, anchor, category)
    local info = CategoryInfo[category]
    local highlight = Instance.new("Highlight")
    highlight.Name = "YUEN_99_ScoutHighlight"
    highlight.Adornee = target
    highlight.FillColor = info.Color
    highlight.OutlineColor = info.Color
    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0.05
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- no through-wall highlight
    highlight.Parent = Workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "YUEN_99_ScoutLabel"
    billboard.Adornee = anchor
    billboard.Size = UDim2.fromOffset(170, 30)
    billboard.StudsOffset = Vector3.new(0, 2.7, 0)
    billboard.AlwaysOnTop = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = MAX_DISTANCE + 25
    billboard.Parent = anchor

    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    label.BackgroundTransparency = 0.18
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextColor3 = info.Color
    label.TextStrokeTransparency = 0.65
    label.Text = info.Emoji .. "  " .. target.Name
    label.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    return {Category = category, Highlight = highlight, Billboard = billboard, Label = label}
end

local function removeVisual(target)
    local entry = VISUALS[target]
    if not entry then return end
    pcall(function() entry.Highlight:Destroy() end)
    pcall(function() entry.Billboard:Destroy() end)
    VISUALS[target] = nil
end

local function clearVisuals(category)
    local targets = {}
    for target, entry in pairs(VISUALS) do
        if not category or entry.Category == category then
            table.insert(targets, target)
        end
    end
    for _, target in ipairs(targets) do
        removeVisual(target)
    end
end

local function enabledCount()
    local count = 0
    for _, value in pairs(Enabled) do
        if value then count += 1 end
    end
    return count
end

local function scanWorld(showNotification)
    if not RUNNING then return end
    local root = getRoot()
    if not root then
        if showNotification then
            Rayfield:Notify({Title = "YUEN Scout", Content = "Character not ready yet. Try scanning again in a moment.", Duration = 4})
        end
        return
    end

    local found = {}
    local visibleCount = 0
    local scanned = 0

    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") or object:IsA("BasePart") then
            scanned += 1
            local category, target = resolveTarget(object)
            if category and target and Enabled[category] and not found[target] then
                local anchor = getAnchor(target)
                if anchor and target.Parent then
                    local distance = (root.Position - anchor.Position).Magnitude
                    if distance <= MAX_DISTANCE then
                        found[target] = category
                        visibleCount += 1
                        local entry = VISUALS[target]
                        if not entry or entry.Category ~= category then
                            removeVisual(target)
                            VISUALS[target] = makeLabel(target, anchor, category)
                        else
                            entry.Highlight.Adornee = target
                            entry.Billboard.Adornee = anchor
                            entry.Billboard.MaxDistance = MAX_DISTANCE + 25
                            entry.Label.Text = CategoryInfo[category].Emoji .. "  " .. target.Name .. "  [" .. math.floor(distance) .. " studs]"
                        end
                    end
                end
            end
        end
    end

    for target in pairs(VISUALS) do
        if not found[target] or not target.Parent then
            removeVisual(target)
        end
    end

    print(string.format("[YUEN 99 Nights] Scan complete | models/parts checked: %d | targets shown: %d | range: %d studs", scanned, visibleCount, MAX_DISTANCE))
    if showNotification then
        Rayfield:Notify({
            Title = "Scout scan complete",
            Content = tostring(visibleCount) .. " recognizable target(s) found within " .. tostring(MAX_DISTANCE) .. " studs. Check the executor console for scan details.",
            Duration = 5
        })
    end
end

local function printDiagnostics()
    local root = getRoot()
    local names = {}
    local totalModels, totalParts = 0, 0
    local broadWords = {"kid", "child", "cage", "chest", "crate", "wood", "log", "scrap", "coal", "fuel", "deer", "cultist", "campfire", "fire", "cave", "bear", "wolf", "ram", "owl", "bat", "food", "medkit", "bandage", "key", "temple", "stronghold"}

    print("========== YUEN 99 NIGHTS DIAGNOSTICS ==========")
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") then totalModels += 1 end
        if object:IsA("BasePart") then totalParts += 1 end
        if object:IsA("Model") or object:IsA("BasePart") then
            local n = normalize(object.Name)
            local candidate = false
            for _, word in ipairs(broadWords) do
                if n:find(normalize(word), 1, true) then
                    candidate = true
                    break
                end
            end
            if candidate then
                local distance = getDistance(object)
                table.insert(names, {Name = object.Name, Path = object:GetFullName(), Distance = distance})
            end
        end
    end

    table.sort(names, function(a, b) return a.Distance < b.Distance end)
    print("Models:", totalModels, " BaseParts:", totalParts, " matching name candidates:", #names)
    for index = 1, math.min(#names, 120) do
        local entry = names[index]
        local dist = entry.Distance == math.huge and "?" or tostring(math.floor(entry.Distance))
        print(string.format("[YUEN CANDIDATE %03d] %s", index, entry.Path))
        print("  distance=" .. dist .. " studs")
    end
    if #names == 0 then
        print("No common target keywords found. This game version may use different internal object names.")
    elseif #names > 120 then
        print("Output capped at 120 candidates; found " .. tostring(#names) .. " total.")
    end
    print("========== END DIAGNOSTICS ==========")

    Rayfield:Notify({
        Title = "Diagnostics printed",
        Content = tostring(#names) .. " candidate names printed to the executor console (maximum 120 shown).",
        Duration = 5
    })
end

OverviewTab:CreateParagraph({
    Title = "YUEN Scout & Survival Assistant",
    Content = "A lightweight client-side helper for 99 Nights in the Forest. It scans recognizable local Workspace names and adds labels/highlights only; it does not collect items or change server state. Press K to toggle the Rayfield UI."
})
OverviewTab:CreateParagraph({
    Title = "Included",
    Content = "• Children / cages scanner\n• Chest and resource scanner\n• Hostile and campfire scanner\n• Named location scanner\n• Name diagnostics for future fixes\n• Short survival guide"
})
OverviewTab:CreateButton({
    Name = "Scan world now",
    Callback = function() scanWorld(true) end
})
OverviewTab:CreateButton({
    Name = "Clear all scout labels",
    Callback = function()
        clearVisuals()
        Rayfield:Notify({Title = "YUEN Scout", Content = "All scout visuals cleared.", Duration = 3})
    end
})

ScoutTab:CreateParagraph({
    Title = "World Scout",
    Content = "Enable the categories you want. Targets are matched by recognizable object/model names, so updates or different map variants may require adjusting the keyword list. Visuals are occluded by walls; this script does not use through-wall highlights."
})
ScoutTab:CreateToggle({Name = "Missing children / cages", CurrentValue = false, Flag = "YUEN99_Children", Callback = function(value) Enabled.Children = value; scanWorld(false) end})
ScoutTab:CreateToggle({Name = "Chests / supply crates", CurrentValue = false, Flag = "YUEN99_Chests", Callback = function(value) Enabled.Chests = value; scanWorld(false) end})
ScoutTab:CreateToggle({Name = "Resources / healing / fuel", CurrentValue = false, Flag = "YUEN99_Resources", Callback = function(value) Enabled.Resources = value; scanWorld(false) end})
ScoutTab:CreateToggle({Name = "Hostile entities", CurrentValue = false, Flag = "YUEN99_Enemies", Callback = function(value) Enabled.Enemies = value; scanWorld(false) end})
ScoutTab:CreateToggle({Name = "Campfire", CurrentValue = false, Flag = "YUEN99_Campfire", Callback = function(value) Enabled.Campfire = value; scanWorld(false) end})
ScoutTab:CreateToggle({Name = "Named locations / structures", CurrentValue = false, Flag = "YUEN99_Locations", Callback = function(value) Enabled.Locations = value; scanWorld(false) end})
ScoutTab:CreateSlider({
    Name = "Maximum scan distance",
    Range = {50, 500},
    Increment = 25,
    Suffix = " studs",
    CurrentValue = 250,
    Flag = "YUEN99_MaxDistance",
    Callback = function(value)
        MAX_DISTANCE = value
        scanWorld(false)
    end
})
ScoutTab:CreateButton({Name = "Refresh scout scan", Callback = function() scanWorld(true) end})
ScoutTab:CreateButton({Name = "Remove all highlights", Callback = function() clearVisuals() end})

DiagnosticsTab:CreateParagraph({
    Title = "Object-name diagnostics",
    Content = "If a category says zero targets, run this diagnostic and check the executor console. It prints matching object paths and distances so the name-matching list can be adjusted instead of guessing. Output is capped at 120 candidate names."
})
DiagnosticsTab:CreateButton({Name = "Run deep name scan", Callback = printDiagnostics})
DiagnosticsTab:CreateButton({
    Name = "Print enabled categories",
    Callback = function()
        print("[YUEN 99 Nights] Max distance:", MAX_DISTANCE)
        for category, value in pairs(Enabled) do
            print("[YUEN 99 Nights]", category, value and "ON" or "OFF")
        end
        print("[YUEN 99 Nights] Current scout visuals:", (function() local n = 0; for _ in pairs(VISUALS) do n += 1 end; return n end)())
    end
})

GuideTab:CreateParagraph({
    Title = "Core loop",
    Content = "By day, gather wood/scrap, loot structures and improve equipment. Keep the campfire fueled and upgrade it; at night it creates a safety zone against several roaming threats, but Cultists can still enter camp. The main objective includes rescuing four missing children."
})
GuideTab:CreateParagraph({
    Title = "Campfire priorities",
    Content = "The public fan wiki documents six campfire levels. Fuel drains over time and more quickly during rain/blizzards. The fire helps with visibility, health regeneration, cold protection, cooking and flashlight recharging. Once the fire is around level 4, the wiki recommends considering logs for crafting rather than relying on them as the main upgrade fuel."
})
GuideTab:CreateParagraph({
    Title = "Loot and resources",
    Content = "Chests may contain fuel, healing items, diamonds, weapons, armor and other gear; variants can have different loot. Wood, scrap and fuel are central resources. Use the scanner as a name-based visual aid only; not every object has a recognizable client-side name."
})
GuideTab:CreateParagraph({
    Title = "Limits / troubleshooting",
    Content = "This script cannot reveal server-only state. If a target is not named with a recognized keyword, no highlight will appear. Run World Scout > Deep name scan and share the [YUEN CANDIDATE] output to tune the scanner for your current game version. This is not tested against every map variant or update."
})

-- Keep selected visual labels fresh as target positions and distances change.
task.spawn(function()
    while RUNNING do
        task.wait(SCAN_INTERVAL)
        local anyEnabled = enabledCount() > 0
        if anyEnabled then
            scanWorld(false)
        else
            clearVisuals()
        end
    end
end)

-- Best-effort cleanup if the local player leaves the session.
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        RUNNING = false
        clearVisuals()
    end
end)

Rayfield:Notify({
    Title = "YUEN | 99 Nights",
    Content = "Scout loaded. Open World Scout and enable a category, or run a diagnostic scan.",
    Duration = 6
})
print("[YUEN 99 Nights] Loaded successfully. Open World Scout to begin.")
