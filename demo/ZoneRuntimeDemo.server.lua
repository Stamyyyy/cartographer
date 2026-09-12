-- Copyright (c) 2026 Stamyyyy. All rights reserved.
--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local runtimeFolder = ServerScriptService:WaitForChild("CartographerRuntime")
local zonePolicyModule = runtimeFolder:WaitForChild("ZonePolicyService")
assert(zonePolicyModule:IsA("ModuleScript"), "ZonePolicyService must be a ModuleScript")
local ZonePolicyService = require(zonePolicyModule)

local activeZones: { [Player]: { [string]: boolean } } = {}
local elapsed = 0
local CHECK_INTERVAL = 0.2

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < CHECK_INTERVAL then
		return
	end
	elapsed = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local active = activeZones[player] or {}
			activeZones[player] = active
			local nowInside: { [string]: boolean } = {}
			for _, zone in ipairs(ZonePolicyService.GetZonesAt(root.Position)) do
				nowInside[zone.name] = true
				if not active[zone.name] then
					print(`{player.Name} entered {zone.zoneType} zone: {zone.name}`)
				end
			end
			activeZones[player] = nowInside
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeZones[player] = nil
end)
