# Cartographer v1.3.2

Cartographer is a Roblox Studio plugin for authoring, validating, and enforcing mission zones. It is a complete generic foundation for objective, spawn, and danger areas, with team-safe spawn rules and clean runtime hooks for combat, inventory, and NPC systems.

## Install the editor

1. Open a blank Roblox Studio place.
2. Insert a temporary Script under `ServerScriptService`.
3. Paste `src/Cartographer.plugin.lua` into that Script.
4. Right-click the Script in Explorer and choose **Save as Local Plugin**.
5. Remove the temporary Script. Open **Plugins > Cartographer > Open Cartographer**.

If an older Cartographer plugin is installed, disable it first so Studio does not show two toolbar buttons.

## One-pass test checklist

1. Open Cartographer. It automatically creates the missing `Allied Team` and `Enemy Team`, Cartographer folders, empty runtime manifest, and three runtime scripts. Existing objects are never overwritten.
2. Cycle zone type to **Spawn** and create a zone. It defaults to Allied Team only, with firing and tool equips disabled, and enemy NPCs blocked. A native team SpawnLocation is created with it.
3. Select a zone in Explorer or use **Select next zone**. Change its name, type, size, policies, group, presentation, and events, then click **Apply settings to selected zone**.
4. Drag or rotate a zone in Studio if needed. The glass volume, bright outline, and optional title stay attached to it.
5. Use **Validate all zones**, then **Export runtime manifest**.
6. Press Play and verify that an Enemy Team player is returned when attempting to enter an Allied Team spawn. Use **Repair automatic setup** only if a generated service was removed.

## Sample NPC models

Cartographer can create two original, low-poly R6-style sample NPCs from the editor:

- **Allied Guard** - steel and blue training guard, marked for `Allied Team`.
- **Enemy Guard** - charcoal and red training soldier, automatically tagged `CartographerEnemy`.

Use the **Sample NPC models** buttons at the bottom of the Cartographer panel. The Models appear in `Workspace/CartographerGuards` and have a Humanoid, collision-ready body parts, simple armor, helmet, visor, and training carbine. They are intentionally lightweight placeholders for testing zones and can be replaced by final art later.

## Automatic runtime installation

Opening Cartographer automatically creates `ServerScriptService/CartographerRuntime` and installs the essential services below if they are missing:

| File | Create as | Purpose |
| --- | --- | --- |
| `ZonePolicyService` | ModuleScript | Reads the manifest and exposes all zone queries. |
| `PlayerEntryGuard` | Script | Enforces player-team restrictions. |
| `EnemyEntryGuard` | Script | Enforces blocked-enemy zones for Models tagged `CartographerEnemy`. |
| `ZoneRuntimeDemo.server.lua` | Script | Optional console logging test. |
| `CombatPolicy.example.server.lua` | Reference | Server-side pattern for weapon/tool systems. |

The guards are intentionally separate so a client can opt into only the behavior their experience needs. They sample every 0.15 seconds and move an unauthorized character or tagged NPC back to its last safe position. A rotated zone is handled as a real oriented box at runtime. The source files in `demo/` remain available as readable reference copies.

## Mission events, groups, and presentation

Each zone can now have an objective message, mission action, music asset ID, lighting preset, and custom server event. When a player enters the zone, Cartographer can show the objective text, fire `MissionStep` with `Start` or `Complete`, play the configured global SoundService track, apply a global Alert/Night/Neutral lighting preset, and fire a named BindableEvent inside `ServerScriptService/CartographerRuntime/CustomEvents`.

Use **Zone groups** to enable or disable a whole related group such as `Objectives`, `Extraction`, or `Waves`. Disabled zones remain in the place but are ignored by the runtime. The **Preset library** sets up common patterns: Safe Spawn, Capture Point, Extraction, PvP Arena, Boss Arena, and Wave Spawn.

**Zone colour** and **Zone title** are separate options. A hidden-colour zone is fully transparent at runtime while its optional floating title can remain visible for map planning or world readability. Toggle the runtime debug overlay to show the active zone names during playtesting.

Music applies globally to the server and needs a valid audio asset the experience is permitted to use. Lighting presets also intentionally affect the entire experience, not only the entering player.

## Zone policies

- **Firing** - Whether the server should accept weapon fire while inside the zone.
- **Equip tools** - Whether the server should accept equip requests in the zone.
- **Enemy access** - Blocks Models tagged `CartographerEnemy` from the zone when the EnemyEntryGuard is installed.
- **Players** - Everyone, Allied Team, Enemy Team, or No players. PlayerEntryGuard enforces this choice.

For game-specific combat and inventory systems, use the server API rather than client-only checks:

```lua
local allowedToFire = ZonePolicyService.CanFireAt(character.HumanoidRootPart.Position)
local allowedToEquip = ZonePolicyService.CanEquipAt(character.HumanoidRootPart.Position)
```

## Included editor features

- Docked Studio widget and toolbar button.
- Glass holographic zones with bright type-coloured outlines.
- Objective, Spawn, and Danger presets with sensible defaults.
- Selection-aware creation using a selected BasePart or Model, or placement in front of the Studio camera.
- Editing, duplication, deletion, undo waypoints, validation, and a compact zone browser.
- Unique IDs, team and policy checks, and conservative overlap warnings.
- Export to `ReplicatedStorage/CartographerZoneManifest`.
- Rotation-aware runtime queries for players, NPCs, firing, and equipment.
- Two original low-poly guard models generated directly in Studio for playtest use.

## Important integration boundary

Cartographer can enforce player and generic tagged-NPC entry by itself. It cannot automatically know how an unrelated weapon, tool, inventory, or NPC pathfinding system works. That is why the package includes server-side API calls and integration examples instead of unsafe client-only blocking. Add the API checks to each system's existing server handler.

## Product path

The next commercial layer is templates: extraction points, capture areas, boss arenas, wave spawners, team bases, and a client-specific export adapter. The core plugin is now ready for that work.

## Copyright

Copyright (c) 2026 Stamyyyy. All rights reserved. See [LICENSE](LICENSE).
