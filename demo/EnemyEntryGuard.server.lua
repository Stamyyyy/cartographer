-- Copyright (c) 2026 Stamyyyy. Licensed under the MIT License.
--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local runtimeFolder = ServerScriptService:WaitForChild("CartographerRuntime")
local zonePolicyModule = runtimeFolder:WaitForChild("ZonePolicyService")
assert(zonePolicyModule:IsA("ModuleScript"), "ZonePolicyService must be a ModuleScript")
local ZonePolicyService = require(zonePolicyModule)

local ENEMY_TAG = "CartographerEnemy"
local CHECK_INTERVAL = 0.15
local elapsed = 0
local lastAllowedPivot: { [Model]: CFrame } = {}

local function getRoot(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

local function checkEnemy(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local root = getRoot(instance)
	if not root then
		return
	end

	if not ZonePolicyService.BlocksEnemyAt(root.Position) then
		lastAllowedPivot[instance] = instance:GetPivot()
		return
	end

	local zones = ZonePolicyService.GetZonesAt(root.Position)
	local blockingZone: any = nil
	for _, zone in ipairs(zones) do
		if zone.blockEnemies then
			blockingZone = zone
			break
		end
	end
	if not blockingZone then
		return
	end

	local previous = lastAllowedPivot[instance]
	if previous then
		instance:PivotTo(previous)
	else
		instance:PivotTo(CFrame.new(ZonePolicyService.GetExitPosition(blockingZone, root.Position)))
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < CHECK_INTERVAL then
		return
	end
	elapsed = 0
	for _, enemy in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
		checkEnemy(enemy)
	end
end)

CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(function(instance)
	if instance:IsA("Model") then
		lastAllowedPivot[instance] = nil
	end
end)
