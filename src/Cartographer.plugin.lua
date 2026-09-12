-- Copyright (c) 2026 Stamyyyy. Licensed under the MIT License.
--!strict

assert(plugin, "Cartographer must run as a Roblox Studio plugin")

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local PLUGIN_ID = "stam.cartographer.zone-builder"
local TOOLBAR_NAME = "Cartographer"
local WIDGET_TITLE = "Cartographer"
local ZONES_FOLDER_NAME = "CartographerZones"
local MANIFEST_FOLDER_NAME = "CartographerZoneManifest"
local ZONE_TAG = "CartographerZone"
local DEFAULT_SIZE = Vector3.new(12, 8, 12)
local DEFAULT_DISTANCE = 24

type ZoneType = "Objective" | "Spawn" | "Danger"
type ZonePolicy = {
	allowFiring: boolean,
	allowEquip: boolean,
	blockEnemies: boolean,
	allowedTeam: string,
}
type GuardStyle = {
	modelName: string,
	displayName: string,
	teamName: string,
	uniform: Color3,
	armor: Color3,
	accent: Color3,
	visor: Color3,
	isEnemy: boolean,
}

local zoneTypes: { ZoneType } = { "Objective", "Spawn", "Danger" }
local typeColors: { [ZoneType]: Color3 } = {
	Objective = Color3.fromRGB(71, 184, 255),
	Spawn = Color3.fromRGB(92, 230, 154),
	Danger = Color3.fromRGB(255, 105, 105),
}
local typePolicies: { [ZoneType]: ZonePolicy } = {
	Objective = { allowFiring = true, allowEquip = true, blockEnemies = false, allowedTeam = "Everyone" },
	Spawn = { allowFiring = false, allowEquip = false, blockEnemies = true, allowedTeam = "Allied Team" },
	Danger = { allowFiring = true, allowEquip = true, blockEnemies = false, allowedTeam = "Everyone" },
}
local accessOptions = { "Everyone", "Allied Team", "Enemy Team", "No players" }
local presetOptions = { "Custom", "Safe Spawn", "Capture Point", "Extraction", "PvP Arena", "Boss Arena", "Wave Spawn" }
local missionActions = { "None", "Start", "Complete" }
local lightingPresets = { "None", "Alert", "Night", "Neutral" }
local alliedGuardStyle: GuardStyle = {
	modelName = "AlliedGuard",
	displayName = "Allied Guard",
	teamName = "Allied Team",
	uniform = Color3.fromRGB(42, 54, 72),
	armor = Color3.fromRGB(141, 157, 175),
	accent = Color3.fromRGB(89, 203, 237),
	visor = Color3.fromRGB(34, 63, 80),
	isEnemy = false,
}
local enemyGuardStyle: GuardStyle = {
	modelName = "EnemyGuard",
	displayName = "Enemy Guard",
	teamName = "Enemy Team",
	uniform = Color3.fromRGB(54, 45, 48),
	armor = Color3.fromRGB(111, 104, 108),
	accent = Color3.fromRGB(235, 97, 91),
	visor = Color3.fromRGB(68, 31, 35),
	isEnemy = true,
}

local ZONE_POLICY_SOURCE = [=[--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local manifest = ReplicatedStorage:WaitForChild("CartographerZoneManifest")
local Service = {}
local zones = {}

local function readZones()
	local result = {}
	for _, child in ipairs(manifest:GetChildren()) do
		if child:IsA("Folder") then
			local position = child:GetAttribute("Position")
			local size = child:GetAttribute("Size")
			local rotation = child:GetAttribute("Rotation")
			if typeof(position) == "Vector3" and typeof(size) == "Vector3" then
				local angles = if typeof(rotation) == "Vector3" then rotation else Vector3.zero
				table.insert(result, {
					name = child.Name,
					size = size,
					cframe = CFrame.new(position) * CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z)),
					allowFiring = child:GetAttribute("AllowFiring") ~= false,
					allowEquip = child:GetAttribute("AllowEquip") ~= false,
					blockEnemies = child:GetAttribute("BlockEnemies") == true,
					allowedTeam = child:GetAttribute("AllowedTeam") or "Everyone",
					enabled = child:GetAttribute("Enabled") ~= false,
				})
			end
		end
	end
	return result
end

function Service.Reload()
	zones = readZones()
end

local function contains(zone, position)
	local localPosition = zone.cframe:PointToObjectSpace(position)
	local half = zone.size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
end

function Service.GetZonesAt(position)
	local result = {}
	for _, zone in ipairs(zones) do
		if zone.enabled and contains(zone, position) then
			table.insert(result, zone)
		end
	end
	return result
end

function Service.CanFireAt(position)
	for _, zone in ipairs(Service.GetZonesAt(position)) do
		if not zone.allowFiring then return false end
	end
	return true
end

function Service.CanEquipAt(position)
	for _, zone in ipairs(Service.GetZonesAt(position)) do
		if not zone.allowEquip then return false end
	end
	return true
end

function Service.GetBlockingPlayerZone(player, position)
	for _, zone in ipairs(Service.GetZonesAt(position)) do
		if zone.allowedTeam == "No players" then return zone end
		if zone.allowedTeam ~= "Everyone" and (not player.Team or player.Team.Name ~= zone.allowedTeam) then return zone end
	end
	return nil
end

function Service.BlocksEnemyAt(position)
	for _, zone in ipairs(Service.GetZonesAt(position)) do
		if zone.blockEnemies then return true end
	end
	return false
end

function Service.GetExitPosition(zone, position, padding)
	local localPosition = zone.cframe:PointToObjectSpace(position)
	local half = zone.size / 2
	local gap = padding or 2
	local x = half.X - math.abs(localPosition.X)
	local y = half.Y - math.abs(localPosition.Y)
	local z = half.Z - math.abs(localPosition.Z)
	if x <= y and x <= z then
		return zone.cframe:PointToWorldSpace(Vector3.new((half.X + gap) * (localPosition.X >= 0 and 1 or -1), localPosition.Y, localPosition.Z))
	elseif y <= z then
		return zone.cframe:PointToWorldSpace(Vector3.new(localPosition.X, (half.Y + gap) * (localPosition.Y >= 0 and 1 or -1), localPosition.Z))
	end
	return zone.cframe:PointToWorldSpace(Vector3.new(localPosition.X, localPosition.Y, (half.Z + gap) * (localPosition.Z >= 0 and 1 or -1)))
end

Service.Reload()
return Service
]=]

local PLAYER_GUARD_SOURCE = [=[--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Policy = require(script.Parent:WaitForChild("ZonePolicyService"))
local lastAllowed = {}
local elapsed = 0

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.15 then return end
	elapsed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local blocked = Policy.GetBlockingPlayerZone(player, root.Position)
			if not blocked then
				lastAllowed[player] = character:GetPivot()
			elseif lastAllowed[player] then
				character:PivotTo(lastAllowed[player])
			else
				character:PivotTo(CFrame.new(Policy.GetExitPosition(blocked, root.Position)))
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAllowed[player] = nil
end)
]=]

local ENEMY_GUARD_SOURCE = [=[--!strict
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Policy = require(script.Parent:WaitForChild("ZonePolicyService"))
local lastAllowed = {}
local elapsed = 0

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.15 then return end
	elapsed = 0
	for _, enemy in ipairs(CollectionService:GetTagged("CartographerEnemy")) do
		if enemy:IsA("Model") then
			local root = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
			if root and root:IsA("BasePart") then
				local blockingZone: any = nil
				for _, zone in ipairs(Policy.GetZonesAt(root.Position)) do
					if zone.blockEnemies then blockingZone = zone break end
				end
				if not blockingZone then
					lastAllowed[enemy] = enemy:GetPivot()
				elseif lastAllowed[enemy] then
					enemy:PivotTo(lastAllowed[enemy])
				else
					enemy:PivotTo(CFrame.new(Policy.GetExitPosition(blockingZone, root.Position)))
				end
			end
		end
	end
end)
]=]

local EVENT_CONTROLLER_SOURCE = [=[local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local runtime = script.Parent
local manifest = ReplicatedStorage:WaitForChild("CartographerZoneManifest")
local objectiveEvent = ReplicatedStorage:WaitForChild("CartographerZoneEvent")
local customEvents = runtime:WaitForChild("CustomEvents")
local missionStep = runtime:WaitForChild("MissionStep")
local originalLighting = { ClockTime = Lighting.ClockTime, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness }
local zones = {}
local active = {}
local elapsed = 0

local function reload()
	zones = {}
	for _, child in ipairs(manifest:GetChildren()) do
		if child:IsA("Folder") then
			local p, s, r = child:GetAttribute("Position"), child:GetAttribute("Size"), child:GetAttribute("Rotation")
			if typeof(p) == "Vector3" and typeof(s) == "Vector3" then
				local a = if typeof(r) == "Vector3" then r else Vector3.zero
				table.insert(zones, { name = child.Name, size = s, cframe = CFrame.new(p) * CFrame.fromOrientation(math.rad(a.X), math.rad(a.Y), math.rad(a.Z)), enabled = child:GetAttribute("Enabled") ~= false, objective = child:GetAttribute("ObjectiveText") or "", action = child:GetAttribute("MissionAction") or "None", music = child:GetAttribute("MusicId") or "", lighting = child:GetAttribute("LightingPreset") or "None", custom = child:GetAttribute("CustomEvent") or "" })
			end
		end
	end
end

local function contains(zone, position)
	local p, h = zone.cframe:PointToObjectSpace(position), zone.size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function applyLighting(preset)
	if preset == "Alert" then
		Lighting.ClockTime, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = 19, Color3.fromRGB(78, 36, 36), Color3.fromRGB(110, 54, 54), 2
	elseif preset == "Night" then
		Lighting.ClockTime, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = 1, Color3.fromRGB(18, 22, 34), Color3.fromRGB(32, 40, 58), 1.2
	elseif preset == "Neutral" then
		Lighting.ClockTime, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = originalLighting.ClockTime, originalLighting.Ambient, originalLighting.OutdoorAmbient, originalLighting.Brightness
	end
end

local function playMusic(id)
	if id == "" then return end
	local sound = SoundService:FindFirstChild("CartographerZoneMusic")
	if not sound then sound = Instance.new("Sound"); sound.Name = "CartographerZoneMusic"; sound.Looped = true; sound.Parent = SoundService end
	if sound:IsA("Sound") then sound.SoundId = "rbxassetid://" .. id; sound:Play() end
end

local function fireCustom(name, player, zoneName)
	if name == "" then return end
	local event = customEvents:FindFirstChild(name)
	if not event then event = Instance.new("BindableEvent"); event.Name = name; event.Parent = customEvents end
	if event:IsA("BindableEvent") then event:Fire(player, zoneName) end
end

local function entered(player, zone)
	if zone.objective ~= "" then objectiveEvent:FireClient(player, "Objective", zone.name, zone.objective) end
	if zone.action ~= "None" then missionStep:Fire(zone.action, zone.name, player) end
	playMusic(zone.music)
	applyLighting(zone.lighting)
	fireCustom(zone.custom, player, zone.name)
end

reload()
manifest.ChildAdded:Connect(reload)
manifest.ChildRemoved:Connect(reload)
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.15 then return end
	elapsed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local was = active[player] or {}
			local now = {}
			for _, zone in ipairs(zones) do
				if zone.enabled and contains(zone, root.Position) then now[zone.name] = true; if not was[zone.name] then entered(player, zone) end end
			end
			active[player] = now
		end
	end
end)
Players.PlayerRemoving:Connect(function(player) active[player] = nil end)
]=]

local ZONE_CLIENT_SOURCE = [=[local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local manifest = ReplicatedStorage:WaitForChild("CartographerZoneManifest")
local objectiveEvent = ReplicatedStorage:WaitForChild("CartographerZoneEvent")
local gui = Instance.new("ScreenGui")
gui.Name = "CartographerZoneUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local objective = Instance.new("TextLabel")
objective.Size = UDim2.fromOffset(440, 46); objective.Position = UDim2.new(0.5, -220, 0.08, 0); objective.BackgroundColor3 = Color3.fromRGB(15, 18, 24); objective.BackgroundTransparency = 0.15; objective.TextColor3 = Color3.fromRGB(240, 244, 250); objective.Font = Enum.Font.BuilderSansBold; objective.TextSize = 18; objective.TextWrapped = true; objective.Visible = false; objective.Parent = gui
local debug = Instance.new("TextLabel")
debug.Size = UDim2.fromOffset(300, 90); debug.Position = UDim2.new(0, 14, 1, -104); debug.BackgroundColor3 = Color3.fromRGB(15, 18, 24); debug.BackgroundTransparency = 0.2; debug.TextColor3 = Color3.fromRGB(180, 220, 255); debug.Font = Enum.Font.Code; debug.TextSize = 14; debug.TextXAlignment = Enum.TextXAlignment.Left; debug.TextYAlignment = Enum.TextYAlignment.Top; debug.TextWrapped = true; debug.Visible = false; debug.Parent = gui
objectiveEvent.OnClientEvent:Connect(function(_, zoneName, text)
	objective.Text = zoneName .. "\n" .. text; objective.Visible = true
	task.delay(4, function() objective.Visible = false end)
end)
local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.2 then return end
	elapsed = 0
	debug.Visible = manifest:GetAttribute("DebugOverlay") == true
	if not debug.Visible then return end
	local character = player.Character; local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then debug.Text = "Cartographer debug\nNo character"; return end
	local names = {}
	for _, child in ipairs(manifest:GetChildren()) do
		local p, s, r = child:GetAttribute("Position"), child:GetAttribute("Size"), child:GetAttribute("Rotation")
		if child:IsA("Folder") and child:GetAttribute("Enabled") ~= false and typeof(p) == "Vector3" and typeof(s) == "Vector3" then
			local a = if typeof(r) == "Vector3" then r else Vector3.zero
			local localPosition = (CFrame.new(p) * CFrame.fromOrientation(math.rad(a.X), math.rad(a.Y), math.rad(a.Z))):PointToObjectSpace(root.Position)
			local h = s / 2
			if math.abs(localPosition.X) <= h.X and math.abs(localPosition.Y) <= h.Y and math.abs(localPosition.Z) <= h.Z then table.insert(names, child.Name) end
		end
	end
	debug.Text = "Cartographer debug\nActive zones: " .. (#names > 0 and table.concat(names, ", ") or "none")
end)
]=]

local selectedType: ZoneType = "Objective"
local allowFiring = true
local allowEquip = true
local blockEnemies = false
local allowedTeam = "Everyone"
local showZoneColor = true
local showZoneTitle = true
local selectedPreset = "Custom"
local selectedMissionAction = "None"
local selectedLightingPreset = "None"

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toolbarButton = toolbar:CreateButton(
	"Open Cartographer",
	"Open the Cartographer mission-zone builder",
	"rbxassetid://4458901886"
)
toolbarButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	420,
	680,
	340,
	480
)
local widget = plugin:CreateDockWidgetPluginGuiAsync(PLUGIN_ID, widgetInfo)
widget.Title = WIDGET_TITLE

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local root = make("ScrollingFrame", widget) :: ScrollingFrame
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(31, 33, 38)
root.BorderSizePixel = 0
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.CanvasSize = UDim2.fromOffset(0, 0)
root.ScrollingDirection = Enum.ScrollingDirection.Y
root.ScrollBarThickness = 5

local padding = make("UIPadding", root) :: UIPadding
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)

local layout = make("UIListLayout", root) :: UIListLayout
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 9)

local function makeLabel(parent: Instance, text: string, height: number, isMuted: boolean): TextLabel
	local label = make("TextLabel", parent) :: TextLabel
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = Enum.Font.BuilderSans
	label.TextSize = isMuted and 13 or 16
	label.TextColor3 = if isMuted then Color3.fromRGB(172, 178, 192) else Color3.fromRGB(242, 244, 248)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = text
	return label
end

local function makeButton(parent: Instance, text: string, accent: boolean): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Size = UDim2.new(1, 0, 0, 34)
	button.BackgroundColor3 = if accent then Color3.fromRGB(49, 122, 192) else Color3.fromRGB(53, 57, 66)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.BuilderSansMedium
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(245, 247, 250)
	button.Text = text
	local corner = make("UICorner", button) :: UICorner
	corner.CornerRadius = UDim.new(0, 5)
	return button
end

local function makeTextBox(parent: Instance, text: string, width: UDim): TextBox
	local box = make("TextBox", parent) :: TextBox
	box.Size = UDim2.new(width, -4, 1, 0)
	box.BackgroundColor3 = Color3.fromRGB(48, 51, 58)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.BuilderSans
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(245, 247, 250)
	box.PlaceholderColor3 = Color3.fromRGB(140, 146, 158)
	box.ClearTextOnFocus = false
	box.Text = text
	local corner = make("UICorner", box) :: UICorner
	corner.CornerRadius = UDim.new(0, 5)
	return box
end

local banner = make("Frame", root) :: Frame
banner.Size = UDim2.new(1, 0, 0, 82)
banner.BackgroundColor3 = Color3.fromRGB(28, 47, 67)
banner.BorderSizePixel = 0
local bannerCorner = make("UICorner", banner) :: UICorner
bannerCorner.CornerRadius = UDim.new(0, 7)
local bannerStroke = make("UIStroke", banner) :: UIStroke
bannerStroke.Color = Color3.fromRGB(102, 165, 210)
bannerStroke.Transparency = 0.38
local bannerGradient = make("UIGradient", banner) :: UIGradient
bannerGradient.Rotation = 18
bannerGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 44, 62)),
	ColorSequenceKeypoint.new(0.54, Color3.fromRGB(42, 79, 108)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 32, 45)),
})

local bannerLine = make("Frame", banner) :: Frame
bannerLine.Size = UDim2.new(1, -24, 0, 2)
bannerLine.Position = UDim2.fromOffset(12, 10)
bannerLine.BackgroundColor3 = Color3.fromRGB(142, 211, 250)
bannerLine.BorderSizePixel = 0

local mark = make("Frame", banner) :: Frame
mark.Size = UDim2.fromOffset(42, 42)
mark.Position = UDim2.fromOffset(12, 25)
mark.BackgroundColor3 = Color3.fromRGB(18, 31, 45)
mark.BorderSizePixel = 0
local markCorner = make("UICorner", mark) :: UICorner
markCorner.CornerRadius = UDim.new(0, 5)
local markStroke = make("UIStroke", mark) :: UIStroke
markStroke.Color = Color3.fromRGB(146, 211, 247)
markStroke.Transparency = 0.18
for index = 0, 2 do
	local square = make("Frame", mark) :: Frame
	square.Size = UDim2.fromOffset(8, 8)
	square.Position = UDim2.fromOffset(8 + index * 9, 17 - index * 5)
	square.BackgroundColor3 = Color3.fromRGB(181 - index * 22, 223 - index * 18, 247 - index * 12)
	square.BorderSizePixel = 0
	local squareCorner = make("UICorner", square) :: UICorner
	squareCorner.CornerRadius = UDim.new(0, 2)
end

local bannerTitle = make("TextLabel", banner) :: TextLabel
bannerTitle.BackgroundTransparency = 1
bannerTitle.Position = UDim2.fromOffset(66, 24)
bannerTitle.Size = UDim2.new(1, -138, 0, 22)
bannerTitle.Font = Enum.Font.BuilderSansBold
bannerTitle.TextSize = 18
bannerTitle.TextColor3 = Color3.fromRGB(240, 246, 251)
bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
bannerTitle.Text = "CARTOGRAPHER"

local bannerSubtitle = make("TextLabel", banner) :: TextLabel
bannerSubtitle.BackgroundTransparency = 1
bannerSubtitle.Position = UDim2.fromOffset(67, 48)
bannerSubtitle.Size = UDim2.new(1, -150, 0, 15)
bannerSubtitle.Font = Enum.Font.BuilderSansMedium
bannerSubtitle.TextSize = 10
bannerSubtitle.TextColor3 = Color3.fromRGB(183, 213, 234)
bannerSubtitle.TextXAlignment = Enum.TextXAlignment.Left
bannerSubtitle.Text = "MISSION-ZONE SYSTEM"

local versionBadge = make("TextLabel", banner) :: TextLabel
versionBadge.BackgroundColor3 = Color3.fromRGB(16, 29, 42)
versionBadge.Position = UDim2.new(1, -58, 0, 29)
versionBadge.Size = UDim2.fromOffset(44, 24)
versionBadge.BorderSizePixel = 0
versionBadge.Font = Enum.Font.BuilderSansMedium
versionBadge.TextSize = 10
versionBadge.TextColor3 = Color3.fromRGB(196, 226, 246)
versionBadge.Text = "v1.3"
local badgeCorner = make("UICorner", versionBadge) :: UICorner
badgeCorner.CornerRadius = UDim.new(0, 4)

makeLabel(root, "Build a zone, select it when you need to edit, then validate before you playtest.", 36, true)

makeLabel(root, "1 / CREATE A ZONE", 18, false)
local nameLabel = makeLabel(root, "Name", 18, true)
local nameBox = makeTextBox(root, "Objective", UDim.new(1, 0))
nameBox.Size = UDim2.new(1, 0, 0, 32)

makeLabel(root, "Type — click to cycle", 18, true)
local typeButton = makeButton(root, "Objective", false)

makeLabel(root, "2 / EDIT THE SELECTED ZONE", 18, false)
makeLabel(root, "Policies — click a control to switch it", 18, true)
local firingButton = makeButton(root, "Firing: allowed", false)
local equipButton = makeButton(root, "Equip tools: allowed", false)
local enemyButton = makeButton(root, "Enemy access: allowed", false)
local playerAccessButton = makeButton(root, "Players: everyone", false)

makeLabel(root, "Size in studs", 18, true)
local sizeRow = make("Frame", root) :: Frame
sizeRow.Size = UDim2.new(1, 0, 0, 32)
sizeRow.BackgroundTransparency = 1
local rowLayout = make("UIListLayout", sizeRow) :: UIListLayout
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rowLayout.Padding = UDim.new(0, 6)
local sizeX = makeTextBox(sizeRow, tostring(DEFAULT_SIZE.X), UDim.new(1 / 3, 0))
local sizeY = makeTextBox(sizeRow, tostring(DEFAULT_SIZE.Y), UDim.new(1 / 3, 0))
local sizeZ = makeTextBox(sizeRow, tostring(DEFAULT_SIZE.Z), UDim.new(1 / 3, 0))

makeLabel(root, "Map presentation", 18, true)
local colorVisibilityButton = makeButton(root, "Zone colour: visible", false)
local titleVisibilityButton = makeButton(root, "Zone title: visible", false)
local debugOverlayButton = makeButton(root, "Runtime debug overlay: off", false)

makeLabel(root, "3 / GROUPS, PRESETS & EVENTS", 18, false)
makeLabel(root, "Zone group", 18, true)
local groupBox = makeTextBox(root, "Ungrouped", UDim.new(1, 0))
groupBox.Size = UDim2.new(1, 0, 0, 32)
local groupToggleButton = makeButton(root, "Toggle selected group", false)

makeLabel(root, "Preset — click to cycle", 18, true)
local presetButton = makeButton(root, "Preset: Custom", false)

makeLabel(root, "Mission events", 18, true)
local objectiveTextBox = makeTextBox(root, "", UDim.new(1, 0))
objectiveTextBox.Size = UDim2.new(1, 0, 0, 32)
objectiveTextBox.PlaceholderText = "Objective text shown on entry"
local missionActionButton = makeButton(root, "Mission step: None", false)
local musicIdBox = makeTextBox(root, "", UDim.new(1, 0))
musicIdBox.Size = UDim2.new(1, 0, 0, 32)
musicIdBox.PlaceholderText = "Music asset ID (optional)"
local lightingPresetButton = makeButton(root, "Lighting: None", false)
local customEventBox = makeTextBox(root, "", UDim.new(1, 0))
customEventBox.Size = UDim2.new(1, 0, 0, 32)
customEventBox.PlaceholderText = "Custom server event name (optional)"

makeLabel(root, "4 / MANAGE & PLAYTEST", 18, false)
local createButton = makeButton(root, "Create zone from these settings", true)
local applyButton = makeButton(root, "Apply changes to selected zone", false)
local duplicateButton = makeButton(root, "Duplicate selected zone", false)
local deleteButton = makeButton(root, "Delete selected zone", false)
local validateButton = makeButton(root, "Check all zones", false)
local exportButton = makeButton(root, "Publish runtime manifest", false)

makeLabel(root, "Zone browser", 18, true)
local refreshZonesButton = makeButton(root, "Refresh zone list", false)
local nextZoneButton = makeButton(root, "Select next zone", false)
local repairSetupButton = makeButton(root, "Repair missing setup", false)
local zoneBrowser = makeLabel(root, "No zones in the place yet.", 62, true)
zoneBrowser.TextYAlignment = Enum.TextYAlignment.Top
zoneBrowser.TextWrapped = true

makeLabel(root, "Playtest NPCs", 18, true)
local alliedGuardButton = makeButton(root, "Create Allied Guard", false)
local enemyGuardButton = makeButton(root, "Create Enemy Guard", false)

local status = makeLabel(root, "Ready. Select a part to copy its placement and size, or create a zone in front of the Studio camera.", 55, true)
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true

local function setStatus(message: string, isError: boolean?)
	status.Text = message
	status.TextColor3 = if isError then Color3.fromRGB(255, 143, 143) else Color3.fromRGB(172, 204, 231)
end

local function refreshPolicyButtons()
	firingButton.Text = if allowFiring then "Firing: allowed" else "Firing: blocked"
	equipButton.Text = if allowEquip then "Equip tools: allowed" else "Equip tools: blocked"
	enemyButton.Text = if blockEnemies then "Enemy access: blocked" else "Enemy access: allowed"
	playerAccessButton.Text = `Players: {allowedTeam}`
	firingButton.BackgroundColor3 = if allowFiring then Color3.fromRGB(52, 112, 83) else Color3.fromRGB(126, 66, 66)
	equipButton.BackgroundColor3 = if allowEquip then Color3.fromRGB(52, 112, 83) else Color3.fromRGB(126, 66, 66)
	enemyButton.BackgroundColor3 = if blockEnemies then Color3.fromRGB(126, 66, 66) else Color3.fromRGB(52, 112, 83)
	playerAccessButton.BackgroundColor3 = if allowedTeam == "Everyone" then Color3.fromRGB(53, 57, 66) else Color3.fromRGB(69, 89, 132)
end

local useTypePolicy: any

local function refreshMissionControls()
	colorVisibilityButton.Text = if showZoneColor then "Zone colour: visible" else "Zone colour: hidden"
	titleVisibilityButton.Text = if showZoneTitle then "Zone title: visible" else "Zone title: hidden"
	debugOverlayButton.Text = if (ReplicatedStorage:FindFirstChild(MANIFEST_FOLDER_NAME) and ReplicatedStorage[MANIFEST_FOLDER_NAME]:GetAttribute("DebugOverlay") == true) then "Runtime debug overlay: on" else "Runtime debug overlay: off"
	presetButton.Text = `Preset: {selectedPreset}`
	missionActionButton.Text = `Mission step: {selectedMissionAction}`
	lightingPresetButton.Text = `Lighting: {selectedLightingPreset}`
	colorVisibilityButton.BackgroundColor3 = if showZoneColor then Color3.fromRGB(52, 112, 83) else Color3.fromRGB(53, 57, 66)
	titleVisibilityButton.BackgroundColor3 = if showZoneTitle then Color3.fromRGB(52, 112, 83) else Color3.fromRGB(53, 57, 66)
end

local function setTypeAppearance()
	typeButton.Text = selectedType
	typeButton.BackgroundColor3 = typeColors[selectedType]:Lerp(Color3.fromRGB(37, 40, 47), 0.4)
end

local function applyPreset(preset: string)
	selectedPreset = preset
	if preset == "Custom" then
		refreshMissionControls()
		return
	end
	if preset == "Safe Spawn" then
		selectedType = "Spawn"
		useTypePolicy(selectedType)
		allowedTeam = "Allied Team"
		groupBox.Text = "Spawns"
		objectiveTextBox.Text = "Allied safe spawn"
	elseif preset == "Capture Point" then
		selectedType = "Objective"
		useTypePolicy(selectedType)
		groupBox.Text = "Objectives"
		objectiveTextBox.Text = "Capture the point"
		selectedMissionAction = "Start"
	elseif preset == "Extraction" then
		selectedType = "Objective"
		useTypePolicy(selectedType)
		groupBox.Text = "Extraction"
		objectiveTextBox.Text = "Reach the extraction zone"
		selectedMissionAction = "Complete"
	elseif preset == "PvP Arena" then
		selectedType = "Danger"
		useTypePolicy(selectedType)
		groupBox.Text = "Combat"
		objectiveTextBox.Text = "Combat zone"
	elseif preset == "Boss Arena" then
		selectedType = "Danger"
		useTypePolicy(selectedType)
		groupBox.Text = "Boss"
		objectiveTextBox.Text = "Boss arena"
		selectedMissionAction = "Start"
	elseif preset == "Wave Spawn" then
		selectedType = "Danger"
		useTypePolicy(selectedType)
		groupBox.Text = "Waves"
		objectiveTextBox.Text = "Incoming hostile wave"
		blockEnemies = false
	end
	setTypeAppearance()
	refreshPolicyButtons()
	refreshMissionControls()
end

useTypePolicy = function(zoneType: ZoneType)
	local policy = typePolicies[zoneType]
	allowFiring = policy.allowFiring
	allowEquip = policy.allowEquip
	blockEnemies = policy.blockEnemies
	allowedTeam = policy.allowedTeam
	refreshPolicyButtons()
end

local function getZonesFolder(): Folder
	local existing = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if existing then
		assert(existing:IsA("Folder"), (`Workspace.{ZONES_FOLDER_NAME} exists but is not a Folder`))
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = ZONES_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function getUniqueName(folder: Folder, requestedName: string): string
	local baseName = requestedName:gsub("^%s*(.-)%s*$", "%1")
	if baseName == "" then
		baseName = selectedType
	end

	if not folder:FindFirstChild(baseName) then
		return baseName
	end

	local index = 2
	while folder:FindFirstChild(`{baseName}_{index}`) do
		index += 1
	end
	return `{baseName}_{index}`
end

local function parseSize(): Vector3?
	local x = tonumber(sizeX.Text)
	local y = tonumber(sizeY.Text)
	local z = tonumber(sizeZ.Text)
	if not x or not y or not z then
		setStatus("Size must contain three numbers.", true)
		return nil
	end

	if x < 1 or y < 1 or z < 1 or x > 512 or y > 512 or z > 512 then
		setStatus("Each size value must be between 1 and 512 studs.", true)
		return nil
	end

	return Vector3.new(x, y, z)
end

local function getPlacement(): (CFrame, Vector3)
	local selected = Selection:Get()
	for _, instance in selected do
		if instance:IsA("BasePart") then
			return instance.CFrame, instance.Size
		end
		if instance:IsA("Model") then
			return instance:GetPivot(), instance:GetExtentsSize()
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local position = camera.CFrame.Position + camera.CFrame.LookVector * DEFAULT_DISTANCE
		return CFrame.new(position), DEFAULT_SIZE
	end

	return CFrame.new(0, DEFAULT_SIZE.Y / 2, 0), DEFAULT_SIZE
end

local function getGuardFolder(): Folder
	local existing = Workspace:FindFirstChild("CartographerGuards")
	if existing then
		assert(existing:IsA("Folder"), "Workspace.CartographerGuards exists but is not a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "CartographerGuards"
	folder.Parent = Workspace
	return folder
end

local function ensureTeam(name: string, color: BrickColor): boolean
	local existing = Teams:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Team"), (`Teams.{name} exists but is not a Team`))
		return false
	end
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = Teams
	return true
end

local function installRuntimeSource(parent: Instance, name: string, source: string, isModule: boolean): boolean
	if parent:FindFirstChild(name) then
		return false
	end
	local sourceContainer = if isModule then Instance.new("ModuleScript") else Instance.new("Script")
	sourceContainer.Name = name
	local success, message = pcall(function()
		sourceContainer.Source = source
	end)
	if not success then
		sourceContainer:Destroy()
		warn(`Cartographer could not install {name}: {message}`)
		return false
	end
	sourceContainer.Parent = parent
	return true
end

local function installLocalSource(parent: Instance, name: string, source: string): boolean
	if parent:FindFirstChild(name) then
		return false
	end
	local sourceContainer = Instance.new("LocalScript")
	sourceContainer.Name = name
	local success, message = pcall(function()
		sourceContainer.Source = source
	end)
	if not success then
		sourceContainer:Destroy()
		warn(`Cartographer could not install {name}: {message}`)
		return false
	end
	sourceContainer.Parent = parent
	return true
end

local function ensureAutomaticSetup()
	local created = {}
	if ensureTeam("Allied Team", BrickColor.new("Bright blue")) then
		table.insert(created, "Allied Team")
	end
	if ensureTeam("Enemy Team", BrickColor.new("Bright red")) then
		table.insert(created, "Enemy Team")
	end
	getZonesFolder()
	getGuardFolder()

	local manifest = ReplicatedStorage:FindFirstChild(MANIFEST_FOLDER_NAME)
	if not manifest then
		manifest = Instance.new("Folder")
		manifest.Name = MANIFEST_FOLDER_NAME
		manifest:SetAttribute("GeneratedBy", "Cartographer bootstrap")
		manifest.Parent = ReplicatedStorage
		table.insert(created, "runtime manifest")
	elseif not manifest:IsA("Folder") then
		warn(`Cartographer expected ReplicatedStorage.{MANIFEST_FOLDER_NAME} to be a Folder`)
	end
	if not ReplicatedStorage:FindFirstChild("CartographerZoneEvent") then
		local event = Instance.new("RemoteEvent")
		event.Name = "CartographerZoneEvent"
		event.Parent = ReplicatedStorage
		table.insert(created, "zone client event")
	end

	local runtimeFolder = ServerScriptService:FindFirstChild("CartographerRuntime")
	if not runtimeFolder then
		runtimeFolder = Instance.new("Folder")
		runtimeFolder.Name = "CartographerRuntime"
		runtimeFolder.Parent = ServerScriptService
		table.insert(created, "runtime folder")
	elseif not runtimeFolder:IsA("Folder") then
		warn("CartographerRuntime exists but is not a Folder")
		return created
	end

	if installRuntimeSource(runtimeFolder, "ZonePolicyService", ZONE_POLICY_SOURCE, true) then
		table.insert(created, "policy service")
	end
	if installRuntimeSource(runtimeFolder, "PlayerEntryGuard", PLAYER_GUARD_SOURCE, false) then
		table.insert(created, "player guard")
	end
	if installRuntimeSource(runtimeFolder, "EnemyEntryGuard", ENEMY_GUARD_SOURCE, false) then
		table.insert(created, "enemy guard")
	end
	if not runtimeFolder:FindFirstChild("CustomEvents") then
		local events = Instance.new("Folder")
		events.Name = "CustomEvents"
		events.Parent = runtimeFolder
		table.insert(created, "custom event folder")
	end
	if not runtimeFolder:FindFirstChild("MissionStep") then
		local missionStep = Instance.new("BindableEvent")
		missionStep.Name = "MissionStep"
		missionStep.Parent = runtimeFolder
		table.insert(created, "mission step event")
	end
	if installRuntimeSource(runtimeFolder, "ZoneEventController", EVENT_CONTROLLER_SOURCE, false) then
		table.insert(created, "zone event controller")
	end
	local playerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	if installLocalSource(playerScripts, "CartographerZoneClient", ZONE_CLIENT_SOURCE) then
		table.insert(created, "zone client UI")
	end
	return created
end

local function getUniqueGuardName(folder: Folder, requestedName: string): string
	if not folder:FindFirstChild(requestedName) then
		return requestedName
	end
	local index = 2
	while folder:FindFirstChild(`{requestedName}_{index}`) do
		index += 1
	end
	return `{requestedName}_{index}`
end

local function createGuardPart(
	guard: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = guard
	return part
end

local function createMotor(name: string, part0: BasePart, part1: BasePart): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = part0
	return motor
end

local function weldAccessory(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
end

local function createSampleGuard(style: GuardStyle)
	local placement = getPlacement()
	local guard = Instance.new("Model")
	guard.Name = getUniqueGuardName(getGuardFolder(), style.modelName)
	guard:SetAttribute("CartographerGuard", true)
	guard:SetAttribute("Faction", style.teamName)
	guard:SetAttribute("Loadout", "Training carbine")
	guard.Parent = getGuardFolder()

	local rootCFrame = CFrame.new(placement.Position + Vector3.new(0, 3, 0))
	local root = createGuardPart(guard, "HumanoidRootPart", Vector3.new(2, 2, 1), rootCFrame, style.uniform, Enum.Material.SmoothPlastic, false)
	root.Transparency = 1
	local torso = createGuardPart(guard, "Torso", Vector3.new(2, 2, 1), rootCFrame, style.uniform, Enum.Material.SmoothPlastic, true)
	local head = createGuardPart(guard, "Head", Vector3.new(2, 1, 1), rootCFrame * CFrame.new(0, 1.5, 0), style.armor, Enum.Material.SmoothPlastic, true)
	local rightArm = createGuardPart(guard, "Right Arm", Vector3.new(1, 2, 1), rootCFrame * CFrame.new(1.5, 0, 0), style.uniform, Enum.Material.SmoothPlastic, false)
	local leftArm = createGuardPart(guard, "Left Arm", Vector3.new(1, 2, 1), rootCFrame * CFrame.new(-1.5, 0, 0), style.uniform, Enum.Material.SmoothPlastic, false)
	local rightLeg = createGuardPart(guard, "Right Leg", Vector3.new(1, 2, 1), rootCFrame * CFrame.new(0.5, -2, 0), style.uniform, Enum.Material.SmoothPlastic, true)
	local leftLeg = createGuardPart(guard, "Left Leg", Vector3.new(1, 2, 1), rootCFrame * CFrame.new(-0.5, -2, 0), style.uniform, Enum.Material.SmoothPlastic, true)

	createMotor("RootJoint", root, torso)
	createMotor("Neck", torso, head)
	createMotor("Right Shoulder", torso, rightArm)
	createMotor("Left Shoulder", torso, leftArm)
	createMotor("Right Hip", torso, rightLeg)
	createMotor("Left Hip", torso, leftLeg)

	local chestPlate = createGuardPart(guard, "ChestPlate", Vector3.new(1.86, 1.45, 0.24), rootCFrame * CFrame.new(0, 0, -0.62), style.armor, Enum.Material.Metal, false)
	local belt = createGuardPart(guard, "UtilityBelt", Vector3.new(2.06, 0.25, 1.06), rootCFrame * CFrame.new(0, -0.86, 0), style.armor, Enum.Material.Metal, false)
	local helmet = createGuardPart(guard, "Helmet", Vector3.new(2.08, 0.52, 1.1), rootCFrame * CFrame.new(0, 2.08, 0), style.armor, Enum.Material.Metal, false)
	local visor = createGuardPart(guard, "Visor", Vector3.new(1.52, 0.3, 0.1), rootCFrame * CFrame.new(0, 1.63, -0.53), style.visor, Enum.Material.Neon, false)
	local chestLight = createGuardPart(guard, "ChestLight", Vector3.new(0.38, 0.22, 0.08), rootCFrame * CFrame.new(0, 0.25, -0.78), style.accent, Enum.Material.Neon, false)
	local rightShoulder = createGuardPart(guard, "RightShoulderPad", Vector3.new(0.54, 0.58, 1.1), rootCFrame * CFrame.new(1.42, 0.55, 0), style.armor, Enum.Material.Metal, false)
	local leftShoulder = createGuardPart(guard, "LeftShoulderPad", Vector3.new(0.54, 0.58, 1.1), rootCFrame * CFrame.new(-1.42, 0.55, 0), style.armor, Enum.Material.Metal, false)
	local rightBoot = createGuardPart(guard, "RightBoot", Vector3.new(1.08, 0.34, 1.14), rootCFrame * CFrame.new(0.5, -2.84, -0.08), style.armor, Enum.Material.Metal, false)
	local leftBoot = createGuardPart(guard, "LeftBoot", Vector3.new(1.08, 0.34, 1.14), rootCFrame * CFrame.new(-0.5, -2.84, -0.08), style.armor, Enum.Material.Metal, false)
	local carbine = createGuardPart(guard, "TrainingCarbine", Vector3.new(0.32, 0.32, 1.62), rootCFrame * CFrame.new(0.78, -0.25, -0.83) * CFrame.Angles(math.rad(-18), 0, 0), style.armor, Enum.Material.Metal, false)
	local carbineCore = createGuardPart(guard, "CarbineCore", Vector3.new(0.14, 0.14, 0.9), rootCFrame * CFrame.new(0.78, -0.25, -1.07) * CFrame.Angles(math.rad(-18), 0, 0), style.accent, Enum.Material.Neon, false)

	for _, accessory in ipairs({ chestPlate, belt, helmet, visor, chestLight, rightShoulder, leftShoulder, carbine, carbineCore }) do
		weldAccessory(torso, accessory)
	end
	weldAccessory(rightLeg, rightBoot)
	weldAccessory(leftLeg, leftBoot)

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.DisplayName = style.displayName
	humanoid.WalkSpeed = 12
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = guard
	guard.PrimaryPart = root

	for _, descendant in ipairs(guard:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	CollectionService:AddTag(guard, "CartographerGuard")
	if style.isEnemy then
		CollectionService:AddTag(guard, "CartographerEnemy")
	end
	Selection:Set({ guard })
	ChangeHistoryService:SetWaypoint(`Cartographer: Create {style.displayName}`)
	setStatus(`Created {guard.Name}. {if style.isEnemy then "It is tagged CartographerEnemy." else "It represents Allied Team."}`)
end

local function isCartographerZone(instance: Instance?): boolean
	return instance ~= nil
		and instance:IsA("BasePart")
		and instance:IsDescendantOf(getZonesFolder())
		and CollectionService:HasTag(instance, ZONE_TAG)
end

local function getSelectedZone(): BasePart?
	for _, instance in Selection:Get() do
		if isCartographerZone(instance) then
			return instance :: BasePart
		end
	end
	return nil
end

local function styleZone(zone: BasePart, zoneType: ZoneType)
	local showColor = zone:GetAttribute("ShowColor") ~= false
	local showTitle = zone:GetAttribute("ShowTitle") ~= false
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Material = Enum.Material.Glass
	zone.Transparency = if showColor then 0.82 else 1
	zone.Reflectance = 0.08
	zone.Color = typeColors[zoneType]
	zone:SetAttribute("ZoneType", zoneType)
	zone:SetAttribute("CartographerVersion", "1.3.0")

	local outline = zone:FindFirstChild("CartographerOutline")
	if not outline then
		outline = Instance.new("SelectionBox")
		outline.Name = "CartographerOutline"
		outline.Parent = zone
	end
	if outline:IsA("SelectionBox") then
		outline.Adornee = zone
		outline.Color3 = typeColors[zoneType]
		outline.SurfaceColor3 = typeColors[zoneType]
		outline.SurfaceTransparency = 0.95
		outline.LineThickness = 0.06
		outline.Visible = showColor
	end

	local title = zone:FindFirstChild("CartographerTitle")
	if not title then
		title = Instance.new("BillboardGui")
		title.Name = "CartographerTitle"
		title.Size = UDim2.fromOffset(240, 40)
		title.AlwaysOnTop = true
		title.Parent = zone
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.25
		label.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
		label.BorderSizePixel = 0
		label.Font = Enum.Font.BuilderSansBold
		label.TextSize = 14
		label.TextColor3 = Color3.fromRGB(242, 245, 250)
		label.TextStrokeTransparency = 0.7
		label.Parent = title
	end
	if title:IsA("BillboardGui") then
		title.Adornee = zone
		title.Enabled = showTitle
		title.StudsOffsetWorldSpace = Vector3.new(0, zone.Size.Y / 2 + 1.6, 0)
		local label = title:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			local group = zone:GetAttribute("Group")
			label.Text = if type(group) == "string" and group ~= "Ungrouped" then `{zone.Name}  |  {group}` else zone.Name
		end
	end
end

local function applyPolicy(zone: BasePart)
	zone:SetAttribute("AllowFiring", allowFiring)
	zone:SetAttribute("AllowEquip", allowEquip)
	zone:SetAttribute("BlockEnemies", blockEnemies)
	zone:SetAttribute("AllowedTeam", allowedTeam)
	zone:SetAttribute("ShowColor", showZoneColor)
	zone:SetAttribute("ShowTitle", showZoneTitle)
	zone:SetAttribute("Group", groupBox.Text:gsub("^%s*(.-)%s*$", "%1") ~= "" and groupBox.Text:gsub("^%s*(.-)%s*$", "%1") or "Ungrouped")
	zone:SetAttribute("Preset", selectedPreset)
	zone:SetAttribute("ObjectiveText", objectiveTextBox.Text)
	zone:SetAttribute("MissionAction", selectedMissionAction)
	zone:SetAttribute("MusicId", musicIdBox.Text:gsub("%D", ""))
	zone:SetAttribute("LightingPreset", selectedLightingPreset)
	zone:SetAttribute("CustomEvent", customEventBox.Text:gsub("^%s*(.-)%s*$", "%1"))
	if type(zone:GetAttribute("Enabled")) ~= "boolean" then
		zone:SetAttribute("Enabled", true)
	end
end

local function readPolicy(zone: BasePart, zoneType: ZoneType)
	local defaults = typePolicies[zoneType]
	local firing = zone:GetAttribute("AllowFiring")
	local equip = zone:GetAttribute("AllowEquip")
	local enemyBlock = zone:GetAttribute("BlockEnemies")
	local teamAccess = zone:GetAttribute("AllowedTeam")
	local group = zone:GetAttribute("Group")
	local preset = zone:GetAttribute("Preset")
	local objectiveText = zone:GetAttribute("ObjectiveText")
	local missionAction = zone:GetAttribute("MissionAction")
	local musicId = zone:GetAttribute("MusicId")
	local lightingPreset = zone:GetAttribute("LightingPreset")
	local customEvent = zone:GetAttribute("CustomEvent")
	allowFiring = if type(firing) == "boolean" then firing else defaults.allowFiring
	allowEquip = if type(equip) == "boolean" then equip else defaults.allowEquip
	blockEnemies = if type(enemyBlock) == "boolean" then enemyBlock else defaults.blockEnemies
	allowedTeam = if type(teamAccess) == "string" then teamAccess else defaults.allowedTeam
	showZoneColor = zone:GetAttribute("ShowColor") ~= false
	showZoneTitle = zone:GetAttribute("ShowTitle") ~= false
	groupBox.Text = if type(group) == "string" then group else "Ungrouped"
	selectedPreset = if type(preset) == "string" then preset else "Custom"
	objectiveTextBox.Text = if type(objectiveText) == "string" then objectiveText else ""
	selectedMissionAction = if type(missionAction) == "string" then missionAction else "None"
	musicIdBox.Text = if type(musicId) == "string" then musicId else ""
	selectedLightingPreset = if type(lightingPreset) == "string" then lightingPreset else "None"
	customEventBox.Text = if type(customEvent) == "string" then customEvent else ""
	refreshPolicyButtons()
	refreshMissionControls()
end

local function ensureNativeSpawnMarker(zone: BasePart)
	local existing = zone:FindFirstChild("CartographerSpawnMarker")
	local zoneType = zone:GetAttribute("ZoneType")
	local teamName = zone:GetAttribute("AllowedTeam")
	if zoneType ~= "Spawn" or type(teamName) ~= "string" or teamName == "Everyone" or teamName == "No players" then
		if existing then
			existing:Destroy()
		end
		return
	end
	local team = Teams:FindFirstChild(teamName)
	if not team or not team:IsA("Team") then
		return
	end
	local marker = existing
	if not marker then
		marker = Instance.new("SpawnLocation")
		marker.Name = "CartographerSpawnMarker"
		marker.Parent = zone
	end
	if marker:IsA("SpawnLocation") then
		marker.Size = Vector3.new(math.clamp(zone.Size.X - 1, 4, 12), 1, math.clamp(zone.Size.Z - 1, 4, 12))
		marker.CFrame = zone.CFrame * CFrame.new(0, zone.Size.Y / 2 + 0.5, 0)
		marker.Anchored = true
		marker.CanCollide = false
		marker.Neutral = false
		marker.AllowTeamChangeOnTouch = false
		marker.TeamColor = team.TeamColor
		marker.BrickColor = team.TeamColor
		marker.Transparency = if zone:GetAttribute("ShowColor") == false then 1 else 0.55
		marker:SetAttribute("CartographerManaged", true)
	end
end

local function createZone()
	local requestedSize = parseSize()
	if not requestedSize then
		return
	end

	local folder = getZonesFolder()
	local placement, selectedSize = getPlacement()
	local selected = Selection:Get()[1]
	local finalSize = if selected and (selected:IsA("BasePart") or selected:IsA("Model")) then selectedSize else requestedSize

	local zone = Instance.new("Part")
	zone.Name = getUniqueName(folder, nameBox.Text)
	zone.CFrame = placement
	zone.Size = finalSize
	zone:SetAttribute("ZoneId", HttpService:GenerateGUID(false))
	applyPolicy(zone)
	styleZone(zone, selectedType)
	zone.Parent = folder
	CollectionService:AddTag(zone, ZONE_TAG)
	ensureNativeSpawnMarker(zone)
	Selection:Set({ zone })
	ChangeHistoryService:SetWaypoint(`Cartographer: Create {zone.Name}`)
	setStatus(`Created {zone.Name}. It is stored in Workspace.{ZONES_FOLDER_NAME}.`)
end

local function applySettingsToSelectedZone()
	local zone = getSelectedZone()
	if not zone then
		setStatus("Select a Cartographer zone first.", true)
		return
	end

	local requestedSize = parseSize()
	if not requestedSize then
		return
	end

	local requestedName = nameBox.Text:gsub("^%s*(.-)%s*$", "%1")
	if requestedName == "" then
		requestedName = selectedType
	end
	if requestedName ~= zone.Name then
		zone.Name = getUniqueName(getZonesFolder(), requestedName)
	end

	zone.Size = requestedSize
	applyPolicy(zone)
	styleZone(zone, selectedType)
	ensureNativeSpawnMarker(zone)
	ChangeHistoryService:SetWaypoint(`Cartographer: Update {zone.Name}`)
	setStatus(`Updated {zone.Name}: players {allowedTeam}, firing {if allowFiring then "allowed" else "blocked"}.`)
end

local function duplicateSelectedZone()
	local source = getSelectedZone()
	if not source then
		setStatus("Select a Cartographer zone first.", true)
		return
	end

	local folder = getZonesFolder()
	local copy = source:Clone()
	copy.Name = getUniqueName(folder, `${source.Name}_copy`)
	copy.CFrame *= CFrame.new(source.Size.X + 2, 0, 0)
	copy:SetAttribute("ZoneId", HttpService:GenerateGUID(false))
	copy.Parent = folder
	CollectionService:AddTag(copy, ZONE_TAG)
	local copyType = copy:GetAttribute("ZoneType")
	if copyType == "Objective" or copyType == "Spawn" or copyType == "Danger" then
		styleZone(copy, copyType)
		ensureNativeSpawnMarker(copy)
	end
	Selection:Set({ copy })
	ChangeHistoryService:SetWaypoint(`Cartographer: Duplicate {source.Name}`)
	setStatus(`Duplicated {source.Name} as {copy.Name}.`)
end

local function deleteSelectedZone()
	local zone = getSelectedZone()
	if not zone then
		setStatus("Select a Cartographer zone first.", true)
		return
	end

	local zoneName = zone.Name
	zone:Destroy()
	Selection:Set({})
	ChangeHistoryService:SetWaypoint(`Cartographer: Delete {zoneName}`)
	setStatus(`Deleted {zoneName}. Use Studio Undo if needed.`)
end

local function getZones(): { BasePart }
	local zones = {}
	for _, child in getZonesFolder():GetChildren() do
		if child:IsA("BasePart") and CollectionService:HasTag(child, ZONE_TAG) then
			table.insert(zones, child)
		end
	end
	return zones
end

local function toggleSelectedGroup()
	local requestedGroup = groupBox.Text:gsub("^%s*(.-)%s*$", "%1")
	if requestedGroup == "" or requestedGroup == "Ungrouped" then
		setStatus("Enter a named group before toggling it.", true)
		return
	end
	local zones = getZones()
	local currentEnabled = true
	for _, zone in ipairs(zones) do
		if zone:GetAttribute("Group") == requestedGroup then
			currentEnabled = zone:GetAttribute("Enabled") ~= false
			break
		end
	end
	local nextEnabled = not currentEnabled
	local affected = 0
	for _, zone in ipairs(zones) do
		if zone:GetAttribute("Group") == requestedGroup then
			zone:SetAttribute("Enabled", nextEnabled)
			affected += 1
		end
	end
	if affected == 0 then
		setStatus(`No zones belong to {requestedGroup}. Apply that group to a zone first.`, true)
		return
	end
	ChangeHistoryService:SetWaypoint(`Cartographer: Toggle group {requestedGroup}`)
	setStatus(`{requestedGroup} is now {if nextEnabled then "enabled" else "disabled"} across {affected} zone(s). Export to update runtime.`)
end

local browserIndex = 0

local function refreshZoneBrowser()
	local zones = getZones()
	if #zones == 0 then
		zoneBrowser.Text = "No zones in the place yet. Create your first zone above."
		return
	end

	table.sort(zones, function(first, second)
		return first.Name:lower() < second.Name:lower()
	end)
	local previews = {}
	for index, zone in ipairs(zones) do
		if index > 5 then
			break
		end
		local zoneType = zone:GetAttribute("ZoneType")
		local access = zone:GetAttribute("AllowedTeam")
		table.insert(previews, `{zone.Name} - {zoneType or "Unknown"} - {access or "Unknown"}`)
	end
	local overflow = if #zones > #previews then `\n+{#zones - #previews} more zone(s)` else ""
	zoneBrowser.Text = `{#zones} zone(s)\n{table.concat(previews, "\n")}{overflow}`
end

local function selectNextZone()
	local zones = getZones()
	if #zones == 0 then
		setStatus("No zones to select yet.", true)
		return
	end
	table.sort(zones, function(first, second)
		return first.Name:lower() < second.Name:lower()
	end)
	browserIndex = (browserIndex % #zones) + 1
	local zone = zones[browserIndex]
	Selection:Set({ zone })
	setStatus(`Selected {zone.Name}. Update its settings above, then apply.`)
end

local function getAabbHalfExtents(part: BasePart): Vector3
	local half = part.Size / 2
	local right = part.CFrame.RightVector
	local up = part.CFrame.UpVector
	local look = part.CFrame.LookVector
	return Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
	)
end

local function potentiallyOverlaps(first: BasePart, second: BasePart): boolean
	local firstHalf = getAabbHalfExtents(first)
	local secondHalf = getAabbHalfExtents(second)
	local difference = first.Position - second.Position
	return math.abs(difference.X) <= firstHalf.X + secondHalf.X
		and math.abs(difference.Y) <= firstHalf.Y + secondHalf.Y
		and math.abs(difference.Z) <= firstHalf.Z + secondHalf.Z
end

local function validateZones(): boolean
	local zones = getZones()
	if #zones == 0 then
		setStatus("No zones yet. Create one first.", true)
		return false
	end

	local warnings = {}
	local knownIds: { [string]: boolean } = {}
	for _, zone in zones do
		local zoneId = zone:GetAttribute("ZoneId")
		local zoneType = zone:GetAttribute("ZoneType")
		if type(zoneId) ~= "string" or zoneId == "" then
			table.insert(warnings, `{zone.Name} is missing a ZoneId`)
		elseif knownIds[zoneId] then
			table.insert(warnings, `{zone.Name} has a duplicate ZoneId`)
		else
			knownIds[zoneId] = true
		end
		if zoneType ~= "Objective" and zoneType ~= "Spawn" and zoneType ~= "Danger" then
			table.insert(warnings, `{zone.Name} has an unknown ZoneType`)
		end
		for _, policyName in { "AllowFiring", "AllowEquip", "BlockEnemies" } do
			if type(zone:GetAttribute(policyName)) ~= "boolean" then
				table.insert(warnings, `{zone.Name} is missing {policyName}`)
			end
		end
		local teamAccess = zone:GetAttribute("AllowedTeam")
		if type(teamAccess) ~= "string" or not table.find(accessOptions, teamAccess) then
			table.insert(warnings, `{zone.Name} has an invalid AllowedTeam policy`)
		elseif teamAccess ~= "Everyone" and teamAccess ~= "No players" and not Teams:FindFirstChild(teamAccess) then
			table.insert(warnings, `{zone.Name} expects a Team named {teamAccess}`)
		end
	end

	for firstIndex = 1, #zones - 1 do
		for secondIndex = firstIndex + 1, #zones do
			if potentiallyOverlaps(zones[firstIndex], zones[secondIndex]) then
				table.insert(warnings, `{zones[firstIndex].Name} may overlap {zones[secondIndex].Name}`)
			end
		end
	end

	if #warnings == 0 then
		setStatus(`Validation passed: {#zones} zones are ready for runtime export.`)
		return true
	end

	setStatus(`Validation found {#warnings} warning(s): {warnings[1]}`, true)
	return false
end

local function exportManifest()
	if not validateZones() then
		return
	end

	local oldManifest = ReplicatedStorage:FindFirstChild(MANIFEST_FOLDER_NAME)
	local debugOverlay = oldManifest and oldManifest:GetAttribute("DebugOverlay") == true
	if oldManifest then
		oldManifest:Destroy()
	end

	local manifest = Instance.new("Folder")
	manifest.Name = MANIFEST_FOLDER_NAME
	manifest:SetAttribute("GeneratedBy", "Cartographer 1.3.0")
	manifest:SetAttribute("DebugOverlay", debugOverlay)
	manifest.Parent = ReplicatedStorage

	for _, zone in getZones() do
		local entry = Instance.new("Folder")
		entry.Name = zone.Name
		entry:SetAttribute("ZoneId", zone:GetAttribute("ZoneId"))
		entry:SetAttribute("ZoneType", zone:GetAttribute("ZoneType"))
		entry:SetAttribute("Position", zone.Position)
		entry:SetAttribute("Rotation", zone.Orientation)
		entry:SetAttribute("Size", zone.Size)
		entry:SetAttribute("AllowFiring", zone:GetAttribute("AllowFiring"))
		entry:SetAttribute("AllowEquip", zone:GetAttribute("AllowEquip"))
		entry:SetAttribute("BlockEnemies", zone:GetAttribute("BlockEnemies"))
		entry:SetAttribute("AllowedTeam", zone:GetAttribute("AllowedTeam"))
		entry:SetAttribute("ShowColor", zone:GetAttribute("ShowColor"))
		entry:SetAttribute("ShowTitle", zone:GetAttribute("ShowTitle"))
		entry:SetAttribute("Group", zone:GetAttribute("Group"))
		entry:SetAttribute("Preset", zone:GetAttribute("Preset"))
		entry:SetAttribute("ObjectiveText", zone:GetAttribute("ObjectiveText"))
		entry:SetAttribute("MissionAction", zone:GetAttribute("MissionAction"))
		entry:SetAttribute("MusicId", zone:GetAttribute("MusicId"))
		entry:SetAttribute("LightingPreset", zone:GetAttribute("LightingPreset"))
		entry:SetAttribute("CustomEvent", zone:GetAttribute("CustomEvent"))
		entry:SetAttribute("Enabled", zone:GetAttribute("Enabled"))
		entry.Parent = manifest
	end

	ChangeHistoryService:SetWaypoint("Cartographer: Export runtime manifest")
	setStatus(`Exported {#getZones()} zones to ReplicatedStorage.{MANIFEST_FOLDER_NAME}.`)
end

local function cycleZoneType()
	local currentIndex = table.find(zoneTypes, selectedType) or 1
	selectedType = zoneTypes[(currentIndex % #zoneTypes) + 1]
	useTypePolicy(selectedType)
	selectedPreset = "Custom"
	setTypeAppearance()
	refreshMissionControls()
end

toolbarButton.Click:Connect(function()
	local created = ensureAutomaticSetup()
	if #created > 0 then
		setStatus(`Automatic setup created: {table.concat(created, ", ")}.`)
	end
	widget.Enabled = not widget.Enabled
	toolbarButton:SetActive(widget.Enabled)
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toolbarButton:SetActive(widget.Enabled)
end)

widget:BindToClose(function()
	widget.Enabled = false
end)

typeButton.Activated:Connect(cycleZoneType)
firingButton.Activated:Connect(function()
	allowFiring = not allowFiring
	refreshPolicyButtons()
end)
equipButton.Activated:Connect(function()
	allowEquip = not allowEquip
	refreshPolicyButtons()
end)
enemyButton.Activated:Connect(function()
	blockEnemies = not blockEnemies
	refreshPolicyButtons()
end)
playerAccessButton.Activated:Connect(function()
	local currentIndex = table.find(accessOptions, allowedTeam) or 1
	allowedTeam = accessOptions[(currentIndex % #accessOptions) + 1]
	refreshPolicyButtons()
end)
colorVisibilityButton.Activated:Connect(function()
	showZoneColor = not showZoneColor
	selectedPreset = "Custom"
	refreshMissionControls()
end)
titleVisibilityButton.Activated:Connect(function()
	showZoneTitle = not showZoneTitle
	selectedPreset = "Custom"
	refreshMissionControls()
end)
debugOverlayButton.Activated:Connect(function()
	ensureAutomaticSetup()
	local manifest = ReplicatedStorage:FindFirstChild(MANIFEST_FOLDER_NAME)
	if manifest and manifest:IsA("Folder") then
		manifest:SetAttribute("DebugOverlay", manifest:GetAttribute("DebugOverlay") ~= true)
		refreshMissionControls()
		setStatus(`Runtime debug overlay {if manifest:GetAttribute("DebugOverlay") == true then "enabled" else "disabled"}.`)
	end
end)
groupToggleButton.Activated:Connect(toggleSelectedGroup)
presetButton.Activated:Connect(function()
	local currentIndex = table.find(presetOptions, selectedPreset) or 1
	applyPreset(presetOptions[(currentIndex % #presetOptions) + 1])
end)
missionActionButton.Activated:Connect(function()
	local currentIndex = table.find(missionActions, selectedMissionAction) or 1
	selectedMissionAction = missionActions[(currentIndex % #missionActions) + 1]
	selectedPreset = "Custom"
	refreshMissionControls()
end)
lightingPresetButton.Activated:Connect(function()
	local currentIndex = table.find(lightingPresets, selectedLightingPreset) or 1
	selectedLightingPreset = lightingPresets[(currentIndex % #lightingPresets) + 1]
	selectedPreset = "Custom"
	refreshMissionControls()
end)
createButton.Activated:Connect(createZone)
applyButton.Activated:Connect(applySettingsToSelectedZone)
duplicateButton.Activated:Connect(duplicateSelectedZone)
deleteButton.Activated:Connect(deleteSelectedZone)
validateButton.Activated:Connect(validateZones)
exportButton.Activated:Connect(exportManifest)
refreshZonesButton.Activated:Connect(refreshZoneBrowser)
nextZoneButton.Activated:Connect(selectNextZone)
repairSetupButton.Activated:Connect(function()
	local created = ensureAutomaticSetup()
	if #created == 0 then
		setStatus("Automatic setup is already present.")
	else
		setStatus(`Automatic setup created: {table.concat(created, ", ")}.`)
	end
end)
alliedGuardButton.Activated:Connect(function()
	createSampleGuard(alliedGuardStyle)
end)
enemyGuardButton.Activated:Connect(function()
	createSampleGuard(enemyGuardStyle)
end)

Selection.SelectionChanged:Connect(function()
	local zone = getSelectedZone()
	if not zone then
		return
	end
	nameBox.Text = zone.Name
	sizeX.Text = string.format("%.2f", zone.Size.X)
	sizeY.Text = string.format("%.2f", zone.Size.Y)
	sizeZ.Text = string.format("%.2f", zone.Size.Z)
	local zoneType = zone:GetAttribute("ZoneType")
	if zoneType == "Objective" or zoneType == "Spawn" or zoneType == "Danger" then
		selectedType = zoneType
		setTypeAppearance()
		readPolicy(zone, selectedType)
	end
end)

useTypePolicy(selectedType)
setTypeAppearance()
refreshMissionControls()
refreshZoneBrowser()

plugin.Unloading:Connect(function()
	toolbarButton:SetActive(false)
end)
