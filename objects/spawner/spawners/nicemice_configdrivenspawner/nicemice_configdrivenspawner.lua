--	MOD-FRIENDLY NPC SPAWNER  --  V2
--	LOFTY 2023-07-25
--  updated 2025-04-21
--  v2 2026-08-11
--
--	WTFPLV2
--
--	This spawner is intended to make it easier for modders to hook into each
--  others' content.
--
--	You are allowed to reuse redistribute etc this software
--	Make your universe a better place
--  Love you
--
------------------------------------------------------
--
--	WHAT CHANGED IN V2
--
--  V1 expected the whole variation table to be pasted into the Tiled object's
--  `parameters` field. That works, but it means anyone who wants to add a race
--  or an npctype to your dungeon has to patch the dungeon json -- which means
--  finding the right objectId inside a huge block of map data and writing a
--  json pointer against it. Clunky, fragile, and it breaks the moment you move
--  the object.
--
--  V2 keeps the variation table in a standalone .config file instead. The Tiled
--  object just names the file and which set inside it to use. Mod authors then
--  patch a small file at a stable path:
--
--      /spawners/whatever_dungeon_spawns.config.patch
--      [ { "op":"add", "path":"/medic/0/npcSpeciesOptions/-", "value":"neki" } ]
--
--  No objectIds, no map data, no re-patching when the dungeon layout moves.
--
--  V1 spawners keep working unchanged -- see LOADING ORDER below.
--
------------------------------------------------------
--
--	HOW TO SET UP THIS SPAWNER
--
--	In Tiled, place an NPC spawner object and set its object field to
--  lofty_irisil_modfriendlynpcspawner2 (or whatever you named your version).
--  Add a parameters field containing only the pointer to your config:
--
--      { "spawner" : { "variationSource" : "/spawners/mydungeon_spawns.config",
--                      "variationSet" : "medic" } }
--
--  variationSource -> path to the .config holding your variation sets.
--                     May also be a LIST of paths; every file is consulted and
--                     the matching sets are concatenated, so several mods can
--                     contribute without patching the same file. (required,
--                     unless possibleVariations is supplied inline)
--
--  variationSet    -> which named set inside that config to use. Omit it and
--                     the spawner uses the set named "default". (optional)
--
--  And the .config file itself looks like this -- one key per set, each holding
--  the same list of variation objects V1 took inline:
--
--      {
--        "medic" : [
--          {
--            "intendedUsage" : "M.A.U.S. cargo ship - medic",
--            "scriptedTargetTags" : [ "faction:nicemice", "species:any", "friendly" ],
--            "npcSpeciesOptions" : [ "nicemice_npc" ],
--            "npcTypeOptions" : [ "nicemice_npc_maus_medic" ],
--            "npcParameterOptions" : [],
--            "npcSeedOptions" : []
--          }
--        ]
--      }
--
--  The variation objects are UNCHANGED from V1, field for field:
--
--		intendedUsage 		-> plain description of what this spawner is for.
--                             makes your intent clear to other modders.
--
--		scriptedTargetTags 	-> tags other modders can hook into. still basically
--                             the wild west. be responsible :3
--			developer note: "species:any" is the tag I use to inject more races
--			into spawners with my hotpatch scripts
--
--		npcSpeciesOptions	-> races this spawner will try to make, picked at
--                             random (required)
--
--		npcTypeOptions		-> npc types this spawner will try to make, picked at
--                             random (required)
--
--		npcParameterOptions	-> whole npc parameter dumps if you want them, picked
--                             at random (optional)
--
--		npcSeedOptions		-> specific seeds, picked at random (optional)
--
------------------------------------------------------
--
--	LOADING ORDER
--
--  The variation list is resolved from the first of these that yields anything:
--
--    1. spawner.possibleVariations   (inline, exactly as V1)
--    2. spawner.variationSource      (one path or a list of them)
--
--  Inline wins so that a V1 spawner -- or anyone who already patched one --
--  behaves identically under this script. You can point the V2 object at this
--  script and lose nothing.
--
------------------------------------------------------
--
--	HOW TO HOOK INTO THIS SPAWNER WITH A SCRIPT
--
--		See lofty_irisil_mfnpcs_hotpatch_postoffice_neki for an example script
--		Patch the object file and add your hotpatch script to the scripts list
--			or
--		Patch the tiled file and add your hotpatch script to the scripts list
--		and/or make any other params changes you need to make
--
--  The three script hooks are unchanged and run at the same points, so existing
--  hotpatch scripts work against V2 without edits. possibleVariationsScriptHook
--  still receives the assembled list -- it does not care whether that list came
--  from the object or from a config file.
--
------------------------------------------------------

require "/scripts/util.lua"

function init()
  object.setInteractive(false)
  animator.setAnimationState("switchState", "on")
end

--template functions intended to be hijacked by hotpatch scripts
function possibleVariationsScriptHook(args)
	return args
end

function selectedVariationScriptHook(args)
	return args
end

function finalResultScriptHook(args)
	return args
end
---------

--complain once, then shut up. a spawner that silently does nothing is horrible
--to debug, but one that logs every tick is worse
local function complainOnce(message)
	if storage.loggedSpawnerComplaint then return end
	storage.loggedSpawnerComplaint = true
	sb.logWarn("[modfriendlynpcspawner2] %s (object at %s)", message, object.position())
end

--root.assetJson throws on a missing path rather than returning nil, so every
--read of a modder-supplied path goes through here
local function tryAssetJson(path)
	local ok, result = pcall(root.assetJson, path)
	if ok then return result end
	complainOnce(string.format("could not read variation config '%s': %s", tostring(path), tostring(result)))
	return nil
end

--accepts a single path or a list of them, so several mods can contribute sets
--without having to patch the same file
local function variationSourcePaths()
	local source = config.getParameter("spawner.variationSource")
	if source == nil then return {} end
	if type(source) == "string" then return { source } end
	return source
end

--pulls the named set out of every configured source and concatenates them
local function loadVariationsFromConfig()
	local setName = config.getParameter("spawner.variationSet", "default")
	local variations = {}

	for _, path in ipairs(variationSourcePaths()) do
		local loaded = tryAssetJson(path)
		if loaded ~= nil then
			local set = loaded[setName]
			if set == nil then
				complainOnce(string.format("config '%s' has no variation set named '%s'", path, tostring(setName)))
			else
				for _, variation in ipairs(set) do
					table.insert(variations, variation)
				end
			end
		end
	end

	return variations
end

--inline first, so V1 spawners and anything already patched onto them are
--completely unaffected by this script
local function resolveVariations()
	local inline = config.getParameter("spawner.possibleVariations")
	if inline ~= nil and #inline > 0 then
		return inline
	end
	return loadVariationsFromConfig()
end

function update(dt)

  --if player can see spawner, do nothing
  --sometimes this can create awkward situations if you /placedungeon in view distance
  --feel free to edit/patch offscreenOnly if you want the spawner to always fire

  if config.getParameter("offscreenOnly") == true then
	  if world.isVisibleToPlayer(object.boundBox()) then
		return nil
	  end
  end

  --force the RNG to do stuff several times across several ticks to make sure it gets seeded properly
  if not storage.multiplayer then
    storage.multiplayer = 1
  else
    storage.multiplayer = storage.multiplayer + math.random(1,10)
  end

  if storage.multiplayer < 49 then
    return nil
  end

  --grab the list of possible variations this spawner can make, use script hooks to dynamically modify
  local options = possibleVariationsScriptHook(resolveVariations())

  --nothing to spawn. do NOT smash: leaving the spawner in world is the only
  --clue a modder gets that their config path or set name was wrong
  if options == nil or #options == 0 then
    complainOnce("no variations to choose from -- check spawner.variationSource and spawner.variationSet")
    return nil
  end

  --choose one of our available options
  local selectedOption = options[math.random(1,#options)]

  --pipe the selected option through a scripted hook in case this particular variation needs additional changes
  selectedOption = selectedVariationScriptHook(selectedOption)

  --set up spawn parameters for our new NPC

  local npcSpecies = "notInstalled"
  if #selectedOption.npcSpeciesOptions > 0 then
	npcSpecies = selectedOption.npcSpeciesOptions[math.random(1,#selectedOption.npcSpeciesOptions)]
  end

  --trying to spawn a variant we don't have a race for - abort mission
  if npcSpecies == "notInstalled" then return nil end

  local npcType = "villager"
  if #selectedOption.npcTypeOptions > 0 then
    npcType = selectedOption.npcTypeOptions[math.random(1,#selectedOption.npcTypeOptions)]
  end

  local npcParameter = nil
  if #selectedOption.npcParameterOptions > 0 then
    npcParameter = selectedOption.npcParameterOptions[math.random(1,#selectedOption.npcParameterOptions)]
  end

  local npcSeed = nil;
  if #selectedOption.npcSeedOptions > 0 then
	npcSeed = selectedOption.npcSeedOptions[math.random(1,#selectedOption.npcSeedOptions)]
  end

  --now that we've set up our spawn parameters, do one final script-hook sanitycheck for our params
  local finalResult = { fnpcSpecies = npcSpecies, fnpcType = npcType, fnpcParameter = npcParameter, fnpcSeed = npcSeed }
  finalResult = finalResultScriptHook(finalResult)

  npcSpecies = finalResult.fnpcSpecies
  npcType = finalResult.fnpcType
  npcParameter = finalResult.fnpcParameter
  npcSeed = finalResult.fnpcSeed

  --preserved (slightly modified, possibly vestigial) code from vanilla spawners
  --originally this overwrote the scriptconfig for the npc entirely which was annoying. bug? who knows. fixed now.
  --
  --v2 note: V1 tested `fnpcParameter` here, which is a global that is never
  --assigned -- the local is `npcParameter`. So this block never actually ran.
  --Corrected to the local, which means spawnedBy is now genuinely set for the
  --first time. If that turns out to be unwanted, delete the block rather than
  --reverting to the typo.
  if npcParameter ~= nil then
	if npcParameter.scriptConfig ~= nil then
		--i'm not sure what this spawnedBy param is even used for, if anything
		npcParameter.scriptConfig.spawnedBy = object.position()
	end
  end

  --spawn the NPC and smash the spawner
  local worldPos = object.toAbsolutePosition({ 0.0, 2.0 })
  local offset = config.getParameter("spawner.offset")
  if offset then
	worldPos[1] = worldPos[1] + offset[1]
	worldPos[2] = worldPos[2] + offset[2]
  end
  world.spawnNpc(worldPos, npcSpecies, npcType, math.max(object.level(), 1), npcSeed, npcParameter);
  object.smash()

end
