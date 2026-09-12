-- Copyright (c) 2026 Stamyyyy. All rights reserved.
--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local runtimeFolder = ServerScriptService:WaitForChild("CartographerRuntime")
local zonePolicyModule = runtimeFolder:WaitForChild("ZonePolicyService")
assert(zonePolicyModule:IsA("ModuleScript"), "ZonePolicyService must be a ModuleScript")
local ZonePolicyService = require(zonePolicyModule)

local lastAllowedCFrame: { [Player]: CFrame } = {}
local elapsed = 0
local CHECK_INTERVAL = 0.15

local function checkPlayer(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local blockedZone = ZonePolicyService.GetBlockingPlayerZone(player, root.Position)
	if not blockedZone then
		lastAllowedCFrame[player] = character:GetPivot()
		return
	end

	local lastAllowed = lastAllowedCFrame[player]
	if lastAllowed then
		character:PivotTo(lastAllowed)
	else
		character:PivotTo(CFrame.new(ZonePolicyService.GetExitPosition(blockedZone, root.Position)))
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < CHECK_INTERVAL then
		return
	end
	elapsed = 0
	for _, player in Players:GetPlayers() do
		checkPlayer(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAllowedCFrame[player] = nil
end)
