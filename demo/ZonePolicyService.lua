-- Copyright (c) 2026 Stamyyyy. All rights reserved.
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local manifest = ReplicatedStorage:WaitForChild("CartographerZoneManifest")
assert(manifest:IsA("Folder"), "CartographerZoneManifest must be a Folder")

type RuntimeZone = {
	name: string,
	zoneType: string,
	position: Vector3,
	rotation: Vector3,
	size: Vector3,
	cframe: CFrame,
	allowFiring: boolean,
	allowEquip: boolean,
	blockEnemies: boolean,
	allowedTeam: string,
}

type ZonePolicyApi = {
	Reload: () -> (),
	GetZonesAt: (position: Vector3) -> { RuntimeZone },
	CanFireAt: (position: Vector3) -> boolean,
	CanEquipAt: (position: Vector3) -> boolean,
	GetBlockingPlayerZone: (player: Player, position: Vector3) -> RuntimeZone?,
	CanPlayerEnter: (player: Player, position: Vector3) -> boolean,
	BlocksEnemyAt: (position: Vector3) -> boolean,
	GetExitPosition: (zone: RuntimeZone, position: Vector3, padding: number?) -> Vector3,
}

local ZonePolicyService: ZonePolicyApi = {} :: any

local function getBooleanAttribute(instance: Instance, name: string, fallback: boolean): boolean
	local value = instance:GetAttribute(name)
	return if type(value) == "boolean" then value else fallback
end

local function getStringAttribute(instance: Instance, name: string, fallback: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

local function readZones(): { RuntimeZone }
	local zones = {}
	for _, child in manifest:GetChildren() do
		if child:IsA("Folder") then
			local position = child:GetAttribute("Position")
			local rotation = child:GetAttribute("Rotation")
			local size = child:GetAttribute("Size")
			if typeof(position) == "Vector3" and typeof(size) == "Vector3" then
				local rotationVector = if typeof(rotation) == "Vector3" then rotation else Vector3.zero
				table.insert(zones, {
					name = child.Name,
					zoneType = getStringAttribute(child, "ZoneType", "Objective"),
					position = position,
					rotation = rotationVector,
					size = size,
					cframe = CFrame.new(position) * CFrame.fromOrientation(
						math.rad(rotationVector.X),
						math.rad(rotationVector.Y),
						math.rad(rotationVector.Z)
					),
					allowFiring = getBooleanAttribute(child, "AllowFiring", true),
					allowEquip = getBooleanAttribute(child, "AllowEquip", true),
					blockEnemies = getBooleanAttribute(child, "BlockEnemies", false),
					allowedTeam = getStringAttribute(child, "AllowedTeam", "Everyone"),
				})
			end
		end
	end
	return zones
end

local zones = readZones()

local function contains(zone: RuntimeZone, position: Vector3): boolean
	local delta = zone.cframe:PointToObjectSpace(position)
	local half = zone.size / 2
	return math.abs(delta.X) <= half.X
		and math.abs(delta.Y) <= half.Y
		and math.abs(delta.Z) <= half.Z
end

local function getZonesAt(position: Vector3): { RuntimeZone }
	local result = {}
	for _, zone in ipairs(zones) do
		if contains(zone, position) then
			table.insert(result, zone)
		end
	end
	return result
end

function ZonePolicyService.Reload()
	zones = readZones()
end

function ZonePolicyService.GetZonesAt(position: Vector3): { RuntimeZone }
	return getZonesAt(position)
end

function ZonePolicyService.CanFireAt(position: Vector3): boolean
	for _, zone in ipairs(getZonesAt(position)) do
		if not zone.allowFiring then
			return false
		end
	end
	return true
end

function ZonePolicyService.CanEquipAt(position: Vector3): boolean
	for _, zone in ipairs(getZonesAt(position)) do
		if not zone.allowEquip then
			return false
		end
	end
	return true
end

function ZonePolicyService.GetBlockingPlayerZone(player: Player, position: Vector3): RuntimeZone?
	for _, zone in ipairs(getZonesAt(position)) do
		if zone.allowedTeam == "No players" then
			return zone
		end
		if zone.allowedTeam ~= "Everyone" and (not player.Team or player.Team.Name ~= zone.allowedTeam) then
			return zone
		end
	end
	return nil
end

function ZonePolicyService.CanPlayerEnter(player: Player, position: Vector3): boolean
	return ZonePolicyService.GetBlockingPlayerZone(player, position) == nil
end

function ZonePolicyService.BlocksEnemyAt(position: Vector3): boolean
	for _, zone in ipairs(getZonesAt(position)) do
		if zone.blockEnemies then
			return true
		end
	end
	return false
end

function ZonePolicyService.GetExitPosition(zone: RuntimeZone, position: Vector3, padding: number?): Vector3
	local half = zone.size / 2
	local delta = zone.cframe:PointToObjectSpace(position)
	local safePadding = padding or 2
	local distances = {
		x = half.X - math.abs(delta.X),
		y = half.Y - math.abs(delta.Y),
		z = half.Z - math.abs(delta.Z),
	}

	if distances.x <= distances.y and distances.x <= distances.z then
		local direction = if delta.X >= 0 then 1 else -1
		return zone.cframe:PointToWorldSpace(Vector3.new((half.X + safePadding) * direction, delta.Y, delta.Z))
	elseif distances.y <= distances.z then
		local direction = if delta.Y >= 0 then 1 else -1
		return zone.cframe:PointToWorldSpace(Vector3.new(delta.X, (half.Y + safePadding) * direction, delta.Z))
	else
		local direction = if delta.Z >= 0 then 1 else -1
		return zone.cframe:PointToWorldSpace(Vector3.new(delta.X, delta.Y, (half.Z + safePadding) * direction))
	end
end

return ZonePolicyService
