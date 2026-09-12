-- Copyright (c) 2026 Stamyyyy. Licensed under the MIT License.
--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local runtimeFolder = ServerScriptService:WaitForChild("CartographerRuntime")
local zonePolicyModule = runtimeFolder:WaitForChild("ZonePolicyService")
assert(zonePolicyModule:IsA("ModuleScript"), "ZonePolicyService must be a ModuleScript")
local ZonePolicyService = require(zonePolicyModule)

local function getCharacterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function canPlayerFire(player: Player): boolean
	local position = getCharacterPosition(player)
	return position ~= nil and ZonePolicyService.CanFireAt(position)
end

local function canPlayerEquip(player: Player): boolean
	local position = getCharacterPosition(player)
	return position ~= nil and ZonePolicyService.CanEquipAt(position)
end

print("Cartographer combat hooks ready", canPlayerFire, canPlayerEquip)
