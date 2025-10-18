--[[ BBConstants.lua

This file (should eventually) contain the static data for player state, buff relationships, and such

Responsibilities:
-Record the spellids & metadata for relevant buffs
-Record the interchangeable & mutually exclusive buff relationships
-Record the potential character roles
-Record the potential 

Dependencies:
None, yay!

Architecture:
Built as a Lua list, with a custom metatable, ala "setmetatable(instance_of, {__index = master_object})"
]]

-- load localization strings
local L = LibStub('AceLocale-3.0'):GetLocale('BuffBroker')

-- Namespace
BBConstants = {}
BBConstants.base = {}

-- Constructors

-- create a new instance from the base "base class"
function BBConstants.base:new()
	local newInstance = {}
	setmetatable(newInstance,self)
	self.__index = self
	return newInstance
end

BBConstants.cataclysm = BBConstants.base:new()
BBConstants.pandas = BBConstants.base:new()
BBConstants.draenor = BBConstants.base:new()

-- Create a new Player State based on the version
function BBConstants:new (clientVersion)
	local newInstance = nil
	local expansionConstants = nil
	local slotName, slotSpells
	local spellID, spellDetails
	local buffType
	
	-- if: Wrath of the Lich King, 30300 etc
	if clientVersion < 40000 then

		-- use base class
		newInstance = BBConstants.base:new()
    
    -- else: other expansion
    else
	    -- if: Cataclysm expansion
    	if clientVersion < 50000 then

        	newInstance = BBConstants.cataclysm:new()
			expansionConstants = BBConstants.cataclysm

	    -- if: Pandaria expansion
	    elseif clientVersion < 60000 then

	        newInstance = BBConstants.pandas:new()
			expansionConstants = BBConstants.pandas

	    -- if: current expansion (draenor)
		else
			newInstance = BBConstants.draenor:new()
			expansionConstants = BBConstants.draenor
		end

		-- seed the aura lookup table
		newInstance.DownRankLookup = {}
		
		-- for: each spell grouping
		for slotName, slotSpells in pairs(expansionConstants.BuffSlots) do

			-- for: each spell
			for spellID, spellDetails in pairs(slotSpells) do
				--[[ use these:
				["SEALS"] = { <- SlotName, v slotSpells
					[20164] = {Score = expansionConstants.Buffs.Basic, Types = {expansionConstants.BuffTypes.PALADIN_SEAL,}, MinLevel = 64, Scope = expansionConstants.Scope.Self}, -- seal of justice
				},
				]]
				
				-- for: each benefit this spell confers
				for _, buffType in pairs(spellDetails.Types) do

					--[[ to make these:
						["PALADIN_SEAL"] = {
							[53736] = {minspellid=53736,level=66, slot="SEALS"}, -- seal of corruption
						},
					]]

					if nil == newInstance.DownRankLookup[buffType] then
						newInstance.DownRankLookup[buffType] = {}
					end
					
					newInstance.DownRankLookup[buffType][spellID] = {
						minspellid = spellID,
						level = spellDetails.MinLevel,
						slot = slotName,
						totemspellid = spellDetails.AppliedBy,
					}
				end -- for: each benefit this spell confers
				
				-- if: applied by pet(s)
				if 'table' == type(spellDetails.AppliedBy) then
					-- for: each pet this requires
					for _, petName in pairs(spellDetails.AppliedBy) do
						expansionConstants.PetBuff[petName] = spellID
					end -- for: each pet this requires
				end -- if: applied by pet(s)
			end -- for: each spell
		end -- for: each spell grouping
	end

	return newInstance
end

function BBConstants.base:GetActiveSpec()
    return GetActiveTalentGroup(true, false)
end

function BBConstants.base:GetNumSpecs()
	return GetNumTalentGroups()
end

function BBConstants.base:GetGroupPrefix()
	local groupPrefix
	if UnitGUID('raid1') then
		groupPrefix = 'raid'
	elseif UnitGUID('party1') then
		groupPrefix = 'party'
	end
	
	return groupPrefix
end

function BBConstants.base:GetNumGroupMembers()
	local numMembers
	
	numMembers = GetNumRaidMembers()
	
	if 0 == numMembers then
		numMembers = GetNumPartyMembers()
	end
end

function BBConstants.base:SpellInfoFromID(spellid)
	local buffLabel = nil

	local buffSlotEntry = nil
	local slotName
	local scope
	
	local labelName
	local labelSpellidMap
	local minspellid
	
	-- for: each label lookup map (AP, MP5, HP, etc)
	for labelName, labelSpellidMap in pairs(self.DownRankLookup) do
		-- if: spell exists in downrank lookup table
		if labelSpellidMap[spellid] then
			-- figure out the relevant label, and other cool info

			-- TODO: get array containing just labelName,
			-- preferably from generated global lookup table
			buffLabel = labelName

			slotName = labelSpellidMap[spellid].slot
			minspellid = labelSpellidMap[spellid].minspellid
			buffSlotEntry = self.BuffSlots[slotName]
			if minspellid and buffSlotEntry and buffSlotEntry[minspellid] then
				scope = buffSlotEntry[minspellid].Scope
			end
			
			break
		end -- if: spell exists in downrank lookup table
	end -- for: each label lookup map

	return buffLabel, slotName, scope
end

function BBConstants.draenor:LookupForm(spellid)

	return nil
end

BBConstants.base.SpecSpells = {
		Primary = true,
		Secondary = true,
	}

BBConstants.base.TalentGroup = {
		None = -1, -- character doesn't have dual spec
		Unknown = 0, -- character hasn't been scanned yet
		Primary = 1, -- primary spec active
		Secondary = 2, -- secondary spec active
	}
		
BBConstants.base.Confidence = {
		Certain = 5, -- can provide best (as can others), all others committed
		Likely = 4, -- can provide best (as can others), no coverage
		Possible = 3, -- can provide best, slot coverage
		Optional = 2, -- can't provide best, no slot coverage
		Unlikely = 1, -- player coverage (not us); or can't provide best, slot coverage
		None = 0,
	}
BBConstants.base.Types = {
		Player = 0,
		WorldObject = 1,
		NPC = 3, -- includes temporary pets/guardians
		CombatPet = 4,
		Vehicle = 5,
		
	}
BBConstants.base.Classes = {
		Monk = "MONK",
		Warrior = "WARRIOR",
		Deathknight = "DEATHKNIGHT",
		Paladin = "PALADIN",
		Shaman = "SHAMAN",
		Hunter = "HUNTER",
		Rogue = "ROGUE",
		Druid = "DRUID",
		Warlock = "WARLOCK",
		Priest = "PRIEST",
		Mage = "MAGE",
		Raid = "RAID",
	}
BBConstants.base.Roles = {
		None = "No Role",
		ManaUser = "Caster",
		NoMana = "Melee DPS",
		Unknown = "Unknown Role",
		Tank = "Tank",
		PureMelee = "Melee DPS",
		MeleeMana = "Melee DPS (mana user)",
		Caster = "Caster",
		MeleeMana_Low = "Low level Melee DPS (mana user)",
		Healer = "Healer",
	}
BBConstants.base.Totems = {
		["FIRE_TOTEMS"] = 133,
		["EARTH_TOTEMS"] = 134,
		["WATER_TOTEMS"] = 135,
		["AIR_TOTEMS"] = 136,
	}
BBConstants.base.ActivatedBy = {
		LongSpell = 1,
		ShortSpell = 2,
		Pet = 3,
		Totem = 4,
	}
BBConstants.base.Buffed = {
		None,
		Partial,
		Full
	}

-- TODO:  Figure out a better name for this, i.e. 'How improved this buff is'
BBConstants.base.Buffs = {
		None = 1, -- can't provide
		ProfessionStats = 2, -- Leatherworking Kings
		Basic = 3, -- class inherent (shaman/warrior)
		BasicLong = 4, -- class inherent (paladin): wisdom, might, kings, sanctuary
		MinorTalented = 5, -- partial talent investment, warrior (1,2 /5), shaman (1/3)
		PartialTalented = 6, -- partial talent investment, druid (1/2), priest (1/2)
		PartialTalentedLong = 7, -- partial talent investment, paladin (1/2)
		MajorTalented = 8, -- partial talent investment, warrior (3,4 /5), shaman (2/3)
		FullTalented = 8, -- 3/3 shaman totems, 5/5 warrior shouts, druid (2/2), priest (2/2)
		FullTalentedLong = 9, -- 2/2 paladin wisdom, 2/2 Paladin might
		Awesome = 10, -- way better than anything we could do
	}
BBConstants.base.Scope = {
		Individual = 1,
		Class = 2,
		Raid = 3,
		Self = 4,
	}
	
function BBConstants.base:IsRaidWide(scope)

	return scope and scope == self.Scope.Raid
end

BBConstants.base.MaxBuffSlots = 40
BBConstants.base.MaxPlayers = 40

BBConstants.base.Forms = { -- warrior stances are dum-dums for now, until blizzard makes them an aura, OR, forms are checked on spellcast instead of aura scan (which is cludgy)
		[71] = BBConstants.base.Roles.Tank, -- defensive stance
		[2457] = BBConstants.base.Roles.PureMelee, -- battle stance
		[2458] = BBConstants.base.Roles.PureMelee, -- Berserker stance
		[25780] = BBConstants.base.Roles.Tank, -- righteous fury
		[48263] = BBConstants.base.Roles.Tank, -- frost presence
		[48265] = BBConstants.base.Roles.PureMelee, -- unholy presence
		[48266] = BBConstants.base.Roles.PureMelee, -- blood presence
		[5487] = BBConstants.base.Roles.Tank, -- Bear Form
		[9634] = BBConstants.base.Roles.Tank, -- Dire Bear Form
		[768] = BBConstants.base.Roles.PureMelee, -- Cat Form
}

BBConstants.base.BuffSlots = {
	["BLESSINGS_BASIC"] = {
		[19742] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 14, Scope = BBConstants.base.Scope.Individual}, -- wisdom
		[25894] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 54, Scope = BBConstants.base.Scope.Class}, -- greater wisdom
		[19740] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 4, Scope = BBConstants.base.Scope.Individual}, -- might
		[25782] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 52, Scope = BBConstants.base.Scope.Class}, -- greater might
		[20217] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 20, Scope = BBConstants.base.Scope.Individual}, -- kings
		[25898] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 60, Scope = BBConstants.base.Scope.Class}, -- greater kings
	},
	["BLESSINGS"] = {
		[19742] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 14, Scope = BBConstants.base.Scope.Individual}, -- wisdom
		[25894] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 54, Scope = BBConstants.base.Scope.Class}, -- greater wisdom
		[19740] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 4, Scope = BBConstants.base.Scope.Individual}, -- might
		[25782] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 52, Scope = BBConstants.base.Scope.Class}, -- greater might
		[20217] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 20, Scope = BBConstants.base.Scope.Individual}, -- kings
		[25898] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 60, Scope = BBConstants.base.Scope.Class}, -- greater kings
		[20911] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Individual}, -- sanctuary
		[25899] = {Score = BBConstants.base.Buffs.BasicLong, Target = true, MinLevel = 60, Scope = BBConstants.base.Scope.Class}, -- greater sanctuary
	},
	["SEALS"] = {
		[53736] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 66, Scope = BBConstants.base.Scope.Self}, -- seal of corruption
		[20164] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 22, Scope = BBConstants.base.Scope.Self}, -- seal of justice
		[20165] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Self}, -- seal of light
		[20154] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Self}, -- seal of righteousness
		[31801] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 64, Scope = BBConstants.base.Scope.Self}, -- seal of vengeance
		[20166] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 38, Scope = BBConstants.base.Scope.Self}, -- seal of wisdom
		[20375] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 20, Scope = BBConstants.base.Scope.Self}, -- seal of command
	},
	["SHOUTS"] = {
		[469] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 68, Scope = BBConstants.base.Scope.Raid}, -- commanding
		[6673] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 1, Scope = BBConstants.base.Scope.Raid}, -- battle
	},
	["ICY_TALONS"] = {
		[55610] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 36, Scope = BBConstants.base.Scope.Raid}, -- improved icy talons
	},
	["HORNS"] = {
		[57330] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 65, Scope = BBConstants.base.Scope.Raid}, -- horn of winter
	},
	["WATER_TOTEMS"] = {
		[5677] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 26, Scope = BBConstants.base.Scope.Raid}, -- mana spring
		[5672] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 20, Scope = BBConstants.base.Scope.Raid}, -- healing stream
	},
	["EARTH_TOTEMS"] = {
		[8072] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 4, Scope = BBConstants.base.Scope.Raid}, -- stoneskin
		[8076] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 10, Scope = BBConstants.base.Scope.Raid}, -- strength of earth
	},
	["FIRE_TOTEMS_BASIC"] = {
		[52109] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 28, Scope = BBConstants.base.Scope.Raid}, -- flametongue
		[3599] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 10, Scope = BBConstants.base.Scope.Raid}, -- searing totem
	},
	["FIRE_TOTEMS"] = {
		[52109] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 28, Scope = BBConstants.base.Scope.Raid}, -- flametongue
		[3599] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 10, Scope = BBConstants.base.Scope.Raid}, -- searing totem
		[57658] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 50, Scope = BBConstants.base.Scope.Raid}, -- wrath
	},
	["AIR_TOTEMS"] = {
		[8515] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 32, Scope = BBConstants.base.Scope.Raid}, -- windfury
		[2895] = {Score = BBConstants.base.Buffs.Basic, Target = false, MinLevel = 64, Scope = BBConstants.base.Scope.Raid}, -- wrath of air
	},
	["FORTITUDE"] = {
		[1243] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Individual}, -- Power Word: Fortitude 8
		[21562] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 48, Scope = BBConstants.base.Scope.Raid}, -- Prayer of Fortitude 4
	},
	["BRILLIANCE"] = {
		[61024] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 80, Scope = BBConstants.base.Scope.Individual}, -- Dalaran Intellect
		[61316] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 80, Scope = BBConstants.base.Scope.Raid}, -- Dalaran Brilliance
		[1459] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Individual}, -- Arcane Intellect 7 
		[23028] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 56, Scope = BBConstants.base.Scope.Raid}, -- Arcane Brilliance 3
	},
	["WILD"] = {
		[1126] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Individual}, -- Mark of the Wild 9
		[21849] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 50, Scope = BBConstants.base.Scope.Raid}, -- Gift of the Wild 4
	},
	["WILD_NPC"] = {
		[46119] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 70, Scope = BBConstants.base.Scope.Individual}, -- Blessing of D E H T A
	},
	["THORNS"] = {
		[467] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 6, Scope = BBConstants.base.Scope.Individual}, -- Thorns 8
	},
	["SPIRIT"] = {
		[14752] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Individual}, -- Divine Spirit 6
		[27681] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 60, Scope = BBConstants.base.Scope.Raid}, -- Prayer of Spirit 3
	},
	["PRIEST_INNER"] = {
		[588] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 12, Scope = BBConstants.base.Scope.Self}, -- Inner Fire
	},
	["PRIEST_PROTECTION"] = {
		[976] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Individual}, -- Shadow Protection
		[27683] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 56, Scope = BBConstants.base.Scope.Raid}, -- Prayer of Shadow Protection
	},
	["EMBRACE"] = {
		[15286] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Self}, -- Inner Fire
	},
	["MAGE_ARMOR"] = {
		[6117] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 64, Scope = BBConstants.base.Scope.Self}, -- Mage Armor
		[168] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Self}, -- Frost Armor
		[7302] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 30, Scope = BBConstants.base.Scope.Self}, -- Ice Armor
		[30482] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 62, Scope = BBConstants.base.Scope.Self}, -- Molten Armor
	},
	["WARLOCK_ARMOR"] = {
		[687] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 1, Scope = BBConstants.base.Scope.Self}, -- Demon Skin
		[706] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 20, Scope = BBConstants.base.Scope.Self}, -- Demon Armor
		[28176] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 62, Scope = BBConstants.base.Scope.Self}, -- Fel Armor
	},
	["RIGHTEOUS_FURY"] = {
		[25780] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 20, Scope = BBConstants.base.Scope.Self}, -- Righteous Fury
	},
	["PRIEST_FORM"] = {
		[15473] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 40, Scope = BBConstants.base.Scope.Self}, -- Shadow Form
	},

	["SHAPESHIFT"] = {
		[24858] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 40, Scope = BBConstants.base.Scope.Self}, -- Owl Form
		[33891] = {Score = BBConstants.base.Buffs.Basic, Target = true, MinLevel = 50, Scope = BBConstants.base.Scope.Self}, -- Tree Form
	},

	["PROFESSION_STATS"] = {
		[69378] = {Score = BBConstants.base.Buffs.ProfessionStats, Scope = BBConstants.base.Scope.Raid}, -- forgotten kings
	},
}


BBConstants.base.GreaterLookup = {
	["BLESSINGS"] = {
		[20217] = 25898, -- Kings
		[20911] = 25899, -- Sanctuary
		[19838] = 25782, -- Might 1
		[25291] = 25916, -- Might 2
		[27140] = 27141, -- Might 3
		[48931] = 48933, -- Might 4
		[48932] = 48934, -- Might 5
		[19854] = 25894, -- Wisdom 1
		[25290] = 25918, -- Wisdom 2
		[27142] = 27143, -- Wisdom 3
		[48935] = 48937, -- Wisdom 4
		[48936] = 48938, -- Wisdom 5
	},
	["FORTITUDE"] = {
		[10937] = 21562, -- Prayer of Fortitude 1
		[10938] = 21564, -- Prayer of Fortitude 2
		[25389] = 25392, -- Prayer of Fortitude 3
		[48161] = 48162, -- Prayer of Fortitude 4
	},
	["BRILLIANCE"] = {
		[10157] = 23028, -- Arcane Brilliance 1
		[27126] = 27127, -- Arcane Brilliance 2
		[42995] = 43002, -- Arcane Brilliance 3
	},
	["WILD"] = {
		[9884] = 21849, -- Gift of the Wild 1
		[9885] = 21850, -- Gift of the Wild 2
		[26990] = 26991, -- Gift of the Wild 3
		[48469] = 48470, -- Gift of the Wild 4
	},
	["SPIRIT"] = {
		[27841] = 27681, -- Prayer of Spirit 1
		[25312] = 32999, -- Prayer of Spirit 2
		[48073] = 48074, -- Prayer of Spirit 3
	},
	["PRIEST_PROTECTION"] = {
		[976] = 27683, -- Prayer of Spirit 1
		[25433] = 39374, -- Prayer of Spirit 2
		[48169] = 48170, -- Prayer of Spirit 3
	},
}

-- TODO:  add 'strength';  level is close, but not a perfect guidline (especially with MP5)
BBConstants.base.DownRankLookup = {
	["SHADOW_RESIST"] = {
		[976] = {minspellid=976, worstSpellID,level=30, slot="PRIEST_PROTECTION"},
		[10957] = {minspellid=976, worstSpellID,level=42, slot="PRIEST_PROTECTION"},
		[10958] = {minspellid=976, worstSpellID,level=56, slot="PRIEST_PROTECTION"},
		[27683] = {minspellid=27683, worstSpellID,level=56, slot="PRIEST_PROTECTION"},
		[25433] = {minspellid=976, worstSpellID,level=68, slot="PRIEST_PROTECTION"},
		[39374] = {minspellid=27683, worstSpellID,level=70, slot="PRIEST_PROTECTION"},
		[48169] = {minspellid=976, worstSpellID,level=76, slot="PRIEST_PROTECTION"},
		[48170] = {minspellid=27683, worstSpellID,level=77, slot="PRIEST_PROTECTION"},
	},
	["AP"] = {
		[6673] = {minspellid=6673, worstSpellID,level=1, slot="SHOUTS"},
		[19740] = {minspellid=19740,level=4, slot="BLESSINGS"},
		[5242] = {minspellid=6673,level=12, slot="SHOUTS"},
		[19834] = {minspellid=19740,level=12, slot="BLESSINGS"},
		[6192] = {minspellid=6673,level=22, slot="SHOUTS"},
		[19835] = {minspellid=19740,level=22, slot="BLESSINGS"},
		[11549] = {minspellid=6673,level=32, slot="SHOUTS"},
		[19836] = {minspellid=19740,level=32, slot="BLESSINGS"},
		[11550] = {minspellid=6673,level=42, slot="SHOUTS"},
		[19837] = {minspellid=19740,level=42, slot="BLESSINGS"},
		[11551] = {minspellid=6673,level=52, slot="SHOUTS"},
		[19838] = {minspellid=19740,level=52, slot="BLESSINGS"},
		[25782] = {minspellid=25782,level=52, slot="BLESSINGS"},
		[25289] = {minspellid=6673,level=60, slot="SHOUTS"},
		[25291] = {minspellid=19740,level=60, slot="BLESSINGS"},
		[25916] = {minspellid=25782,level=60, slot="BLESSINGS"},
		[2048] = {minspellid=6673,level=69, slot="SHOUTS"},
		[27140] = {minspellid=19740,level=70, slot="BLESSINGS"},
		[27141] = {minspellid=25782,level=70, slot="BLESSINGS"},
		[48931] = {minspellid=19740,level=73, slot="BLESSINGS"},
		[48933] = {minspellid=25782,level=73, slot="BLESSINGS"},
		[47436] = {minspellid=6673,level=78, slot="SHOUTS"},
		[48932] = {minspellid=19740,level=79, slot="BLESSINGS"},
		[48934] = {minspellid=25782,level=79, slot="BLESSINGS"},
	},
	["MP5"] = {
		[19742] = {minspellid=19742,level=14, slot="BLESSINGS"},
		[19850] = {minspellid=19742,level=24, slot="BLESSINGS"},
		[5677] = {minspellid=5677,level=26, totemspellid=5675, slot="WATER_TOTEMS"},
		[5675] = {minspellid=5675,level=26, slot="WATER_TOTEMS"},
		[19852] = {minspellid=19742,level=34, slot="BLESSINGS"},
		[10491] = {minspellid=5677,level=36, totemspellid=10495, slot="WATER_TOTEMS"},
		[10495] = {minspellid=5675,level=36, slot="WATER_TOTEMS"},
		[19853] = {minspellid=19742,level=44, slot="BLESSINGS"},
		[10493] = {minspellid=5677,level=46, totemspellid=10496, slot="WATER_TOTEMS"},
		[10496] = {minspellid=5675,level=46, slot="WATER_TOTEMS"},
		[19854] = {minspellid=19742,level=54, slot="BLESSINGS"},
		[25894] = {minspellid=25894,level=54, slot="BLESSINGS"},
		[10494] = {minspellid=5677,level=56, totemspellid=10497, slot="WATER_TOTEMS"},
		[10497] = {minspellid=5675,level=56, slot="WATER_TOTEMS"},
		[25290] = {minspellid=19742,level=60, slot="BLESSINGS"},
		[25918] = {minspellid=25894,level=60, slot="BLESSINGS"},
		[25569] = {minspellid=5677,level=65, totemspellid=25570, slot="WATER_TOTEMS"},
		[25570] = {minspellid=5675,level=65, slot="WATER_TOTEMS"},
		[27142] = {minspellid=19742,level=65, slot="BLESSINGS"},
		[27143] = {minspellid=25894,level=65, slot="BLESSINGS"},
		[58775] = {minspellid=5677,level=71, totemspellid=58771, slot="WATER_TOTEMS"},
		[58771] = {minspellid=5675,level=71, slot="WATER_TOTEMS"},
		[48935] = {minspellid=19742,level=71, slot="BLESSINGS"},
		[48937] = {minspellid=5675,level=71, slot="BLESSINGS"},
		[58776] = {minspellid=5675,level=76, totemspellid=58773, slot="WATER_TOTEMS"},
		[58773] = {minspellid=5675,level=76, slot="WATER_TOTEMS"},
		[48936] = {minspellid=5675,level=77, slot="BLESSINGS"},
		[48938] = {minspellid=25894,level=77, slot="BLESSINGS"},
		[58777] = {minspellid=5677,level=80, totemspellid=58774, slot="WATER_TOTEMS"},
		[58774] = {minspellid=5675,level=80, slot="WATER_TOTEMS"},
	},
	["HP5"] = {
		[5672] = {minspellid=5672,level=20, totemspellid=5394, slot="WATER_TOTEMS"},
		[5394] = {minspellid=5394,level=20, slot="WATER_TOTEMS"},
		[6371] = {minspellid=5672,level=30, totemspellid=6375, slot="WATER_TOTEMS"},
		[6375] = {minspellid=5394,level=30, slot="WATER_TOTEMS"},
		[6372] = {minspellid=5672,level=40, totemspellid=6377, slot="WATER_TOTEMS"},
		[6377] = {minspellid=5394,level=40, slot="WATER_TOTEMS"},
		[10460] = {minspellid=5672,level=50, totemspellid=10462, slot="WATER_TOTEMS"},
		[10462] = {minspellid=5394,level=50, slot="WATER_TOTEMS"},
		[10461] = {minspellid=5672,level=60, totemspellid=10463, slot="WATER_TOTEMS"},
		[10463] = {minspellid=5394,level=60, slot="WATER_TOTEMS"},
		[25566] = {minspellid=5672,level=69, totemspellid=25567, slot="WATER_TOTEMS"},
		[25567] = {minspellid=5394,level=69, slot="WATER_TOTEMS"},
		[58763] = {minspellid=5672,level=71, totemspellid=58755, slot="WATER_TOTEMS"},
		[58755] = {minspellid=5394,level=71, slot="WATER_TOTEMS"},
		[58764] = {minspellid=5672,level=76, totemspellid=58756, slot="WATER_TOTEMS"},
		[58756] = {minspellid=5394,level=76, slot="WATER_TOTEMS"},
		[65994] = {minspellid=5672,level=80, totemspellid=58757, slot="WATER_TOTEMS"},
		[58757] = {minspellid=5394,level=80, slot="WATER_TOTEMS"},
	},
	["ARMOR"] = {
		[8072] = {minspellid=8072,level=4, totemspellid=8071, slot="EARTH_TOTEMS"},
		[8071] = {minspellid=8071,level=4, slot="EARTH_TOTEMS"},
		[8156] = {minspellid=8072,level=14, totemspellid=8154, slot="EARTH_TOTEMS"},
		[8154] = {minspellid=8071,level=14, slot="EARTH_TOTEMS"},
		[8157] = {minspellid=8072,level=24, totemspellid=8155, slot="EARTH_TOTEMS"},
		[8155] = {minspellid=8071,level=24, slot="EARTH_TOTEMS"},
		[10403] = {minspellid=8072,level=34, totemspellid=10406, slot="EARTH_TOTEMS"},
		[10406] = {minspellid=8071,level=34, slot="EARTH_TOTEMS"},
		[10404] = {minspellid=8072,level=44, totemspellid=10407, slot="EARTH_TOTEMS"},
		[10407] = {minspellid=8071,level=44, slot="EARTH_TOTEMS"},
		[10405] = {minspellid=8072,level=54, totemspellid=10408, slot="EARTH_TOTEMS"},
		[10408] = {minspellid=8071,level=54, slot="EARTH_TOTEMS"},
		[25506] = {minspellid=8072,level=63, totemspellid=25508, slot="EARTH_TOTEMS"},
		[25508] = {minspellid=8071,level=63, slot="EARTH_TOTEMS"},
		[25507] = {minspellid=8072,level=70, totemspellid=25509, slot="EARTH_TOTEMS"},
		[25509] = {minspellid=8071,level=70, slot="EARTH_TOTEMS"},
		[58752] = {minspellid=8072,level=75, totemspellid=58751, slot="EARTH_TOTEMS"},
		[58751] = {minspellid=8071,level=75, slot="EARTH_TOTEMS"},
		[58754] = {minspellid=8072,level=78, totemspellid=58753, slot="EARTH_TOTEMS"},
		[58753] = {minspellid=8071,level=78, slot="EARTH_TOTEMS"},
	},
	["STRENGTH_AGILITY"] = {
		[8076] = {minspellid=8076,level=10, totemspellid=8075, slot="EARTH_TOTEMS"},
		[8075] = {minspellid=8075,level=10, slot="EARTH_TOTEMS"},
		[8162] = {minspellid=8076,level=24, totemspellid=8160, slot="EARTH_TOTEMS"},
		[8160] = {minspellid=8075,level=24, slot="EARTH_TOTEMS"},
		[8163] = {minspellid=8076,level=38, totemspellid=8161, slot="EARTH_TOTEMS"},
		[8161] = {minspellid=8075,level=38, slot="EARTH_TOTEMS"},
		[10441] = {minspellid=8076,level=52, totemspellid=10442, slot="EARTH_TOTEMS"},
		[10442] = {minspellid=8075,level=52, slot="EARTH_TOTEMS"},
		[25362] = {minspellid=8076,level=60, totemspellid=25361, slot="EARTH_TOTEMS"},
		[25361] = {minspellid=8075,level=60, slot="EARTH_TOTEMS"},
		[25527] = {minspellid=8076,level=65, totemspellid=25528, slot="EARTH_TOTEMS"},
		[25528] = {minspellid=8075,level=65, slot="EARTH_TOTEMS"},
		[57330] = {minspellid=57330,level=65, slot="HORNS"},
		[57621] = {minspellid=8076,level=75, totemspellid=57622, slot="EARTH_TOTEMS"},
		[57622] = {minspellid=8075,level=75, slot="EARTH_TOTEMS"},
		[57623] = {minspellid=57330,level=75, slot="HORNS"},
		[58646] = {minspellid=8076,level=80, totemspellid=58643, slot="EARTH_TOTEMS"},
		[58643] = {minspellid=8075,level=80, slot="EARTH_TOTEMS"},
	},
	["SOLO_FIRE_TOTEM"] = {
		[3599] = {minspellid=3599,level=10, totemspellid=3599, slot="FIRE_TOTEMS"},
		[3599] = {minspellid=3599,level=10, slot="FIRE_TOTEMS"},
		[6363] = {minspellid=3599,level=20, totemspellid=6363, slot="FIRE_TOTEMS"},
		[6363] = {minspellid=3599,level=20, slot="FIRE_TOTEMS"},
		[6364] = {minspellid=3599,level=30, totemspellid=6364, slot="FIRE_TOTEMS"},
		[6364] = {minspellid=3599,level=30, slot="FIRE_TOTEMS"},
		[6365] = {minspellid=3599,level=40, totemspellid=6365, slot="FIRE_TOTEMS"},
		[6365] = {minspellid=3599,level=40, slot="FIRE_TOTEMS"},
		[10437] = {minspellid=3599,level=50, totemspellid=10437, slot="FIRE_TOTEMS"},
		[10437] = {minspellid=3599,level=50, slot="FIRE_TOTEMS"},
		[10438] = {minspellid=3599,level=60, totemspellid=10438, slot="FIRE_TOTEMS"},
		[10438] = {minspellid=3599,level=60, slot="FIRE_TOTEMS"},
		[25533] = {minspellid=3599,level=69, totemspellid=25533, slot="FIRE_TOTEMS"},
		[25533] = {minspellid=3599,level=69, slot="FIRE_TOTEMS"},
		[58699] = {minspellid=3599,level=71, totemspellid=58699, slot="FIRE_TOTEMS"},
		[58699] = {minspellid=3599,level=71, slot="FIRE_TOTEMS"},
		[58703] = {minspellid=3599,level=75, totemspellid=58703, slot="FIRE_TOTEMS"},
		[58703] = {minspellid=3599,level=75, slot="FIRE_TOTEMS"},
		[58704] = {minspellid=3599,level=80, totemspellid=58704, slot="FIRE_TOTEMS"},
		[58704] = {minspellid=3599,level=80, slot="FIRE_TOTEMS"},
	},
	["FLAT_SPELL"] = {
		[52109] = {minspellid=52109,level=28, totemspellid=8227, slot="FIRE_TOTEMS"},
		[8227] = {minspellid=8227,level=28, slot="FIRE_TOTEMS"},
		[52110] = {minspellid=52109,level=38, totemspellid=8249, slot="FIRE_TOTEMS"},
		[8249] = {minspellid=8227,level=38, slot="FIRE_TOTEMS"},
		[52111] = {minspellid=52109,level=48, totemspellid=10526, slot="FIRE_TOTEMS"},
		[10526] = {minspellid=8227,level=48, slot="FIRE_TOTEMS"},
		[52112] = {minspellid=52109,level=58, totemspellid=16387, slot="FIRE_TOTEMS"},
		[16387] = {minspellid=8227,level=58, slot="FIRE_TOTEMS"},
		[52113] = {minspellid=52109,level=67, totemspellid=25557, slot="FIRE_TOTEMS"},
		[25557] = {minspellid=8227,level=67, slot="FIRE_TOTEMS"},
		[58651] = {minspellid=52109,level=71, totemspellid=58649, slot="FIRE_TOTEMS"},
		[58649] = {minspellid=8227,level=71, slot="FIRE_TOTEMS"},
		[58654] = {minspellid=52109,level=75, totemspellid=58652, slot="FIRE_TOTEMS"},
		[58652] = {minspellid=8227,level=75, slot="FIRE_TOTEMS"},
		[58655] = {minspellid=52109,level=80, totemspellid=58656, slot="FIRE_TOTEMS"},
		[58656] = {minspellid=8227,level=80, slot="FIRE_TOTEMS"},
	},
	["FLAT_SPELL_CRIT"] = {
		[57658] = {minspellid=57658,level=50, totemspellid=30706, slot="FIRE_TOTEMS"},
		[30706] = {minspellid=30706,level=50, slot="FIRE_TOTEMS"},
		[57660] = {minspellid=57658,level=60, totemspellid=57720, slot="FIRE_TOTEMS"},
		[57720] = {minspellid=30706,level=60, slot="FIRE_TOTEMS"},
		[57662] = {minspellid=57658,level=70, totemspellid=57721, slot="FIRE_TOTEMS"},
		[57721] = {minspellid=30706,level=70, slot="FIRE_TOTEMS"},
		[57663] = {minspellid=57658,level=80, totemspellid=57722, slot="FIRE_TOTEMS"},
		[57722] = {minspellid=30706,level=80, slot="FIRE_TOTEMS"},
	},
	["MELEE_HASTE"] = {
		[8515] = {minspellid=8515,level=32, totemspellid=8512, slot="AIR_TOTEMS"},
		[8512] = {minspellid=8512,level=32, slot="AIR_TOTEMS"},
		[55610] = {minspellid=55610,level=36, slot="ICY_TALONS"},
	},
	["SPELL_HASTE"] = {
		[2895] = {minspellid=2895,level=64, totemspellid=3738, slot="AIR_TOTEMS"},
		[3738] = {minspellid=3738,level=64, slot="AIR_TOTEMS"},
	},
	["STATS"] = {
		[20217] = {minspellid=20217,level=20, slot="BLESSINGS"},
		[25898] = {minspellid=25898,level=60, slot="BLESSINGS"},
	},
	["TANK"] = {
		[20911] = {minspellid=20911,level=30, slot="BLESSINGS"},
		[25899] = {minspellid=25899,level=60, slot="BLESSINGS"},
	},
	["HP"] = {
		[469] = {minspellid=469,level=68, slot="SHOUTS"},
		[47439] = {minspellid=469,level=74, slot="SHOUTS"},
		[47440] = {minspellid=469,level=80, slot="SHOUTS"},
	},
	["STAMINA"] = {
		[1243] = {minspellid=1243,level=1, slot="FORTITUDE"}, -- Power Word: Fortitude 1
		[1244] = {minspellid=1243,level=12, slot="FORTITUDE"}, -- Power Word: Fortitude 2
		[1245] = {minspellid=1243,level=24, slot="FORTITUDE"}, -- Power Word: Fortitude 3
		[2791] = {minspellid=1243,level=36, slot="FORTITUDE"}, -- Power Word: Fortitude 4
		[10937] = {minspellid=1243,level=48, slot="FORTITUDE"}, -- Power Word: Fortitude 5
		[21562] = {minspellid=21562,level=48, slot="FORTITUDE"}, -- Prayer of Fortitude 1
		[10938] = {minspellid=1243,level=60, slot="FORTITUDE"}, -- Power Word: Fortitude 6
		[21564] = {minspellid=21562,level=60, slot="FORTITUDE"}, -- Prayer of Fortitude 2
		[25389] = {minspellid=1243,level=70, slot="FORTITUDE"}, -- Power Word: Fortitude 7
		[25392] = {minspellid=21562,level=70, slot="FORTITUDE"}, -- Prayer of Fortitude 3
		[48161] = {minspellid=1243,level=80, slot="FORTITUDE"}, -- Power Word: Fortitude 8
		[48162] = {minspellid=21562,level=80, slot="FORTITUDE"}, -- Prayer of Fortitude 4
	},
	["INTELLECT"] = {
		[1459] = {minspellid=1459,level=1, slot="BRILLIANCE"}, -- Arcane Intellect 1
		[1460] = {minspellid=1459,level=14, slot="BRILLIANCE"}, -- Arcane Intellect 2
		[1461] = {minspellid=1459,level=28, slot="BRILLIANCE"}, -- Arcane Intellect 3
		[10156] = {minspellid=1459,level=42, slot="BRILLIANCE"}, -- Arcane Intellect 4
		[10157] = {minspellid=1459,level=56, slot="BRILLIANCE"}, -- Arcane Intellect 5
		[23028] = {minspellid=23028,level=56, slot="BRILLIANCE"}, -- Arcane Brilliance 1
		[27126] = {minspellid=1459,level=70, slot="BRILLIANCE"}, -- Arcane Intellect 6
		[27127] = {minspellid=23028,level=70, slot="BRILLIANCE"}, -- Arcane Brilliance 2
		[42995] = {minspellid=1459,level=80, slot="BRILLIANCE"}, -- Arcane Intellect 7 
		[43002] = {minspellid=23028,level=80, slot="BRILLIANCE"}, -- Arcane Brilliance 3
		[61024] = {minspellid=61024,level=80, slot="BRILLIANCE"}, -- Dalaran Intellect
		[61316] = {minspellid=61316,level=80, slot="BRILLIANCE"}, -- Dalaran Brilliance
	},
	["WILD"] = {
		[1126] = {minspellid=1126,level=1, slot="WILD"}, -- Mark of the Wild 1
		[5232] = {minspellid=1126,level=10, slot="WILD"}, -- Mark of the Wild 2
		[6756] = {minspellid=1126,level=20, slot="WILD"}, -- Mark of the Wild 3
		[5234] = {minspellid=1126,level=30, slot="WILD"}, -- Mark of the Wild 4
		[8907] = {minspellid=1126,level=40, slot="WILD"}, -- Mark of the Wild 5
		[9884] = {minspellid=1126,level=50, slot="WILD"}, -- Mark of the Wild 6
		[21849] = {minspellid=21849,level=50, slot="WILD"}, -- Gift of the Wild 1
		[9885] = {minspellid=1126,level=60, slot="WILD"}, -- Mark of the Wild 7
		[21850] = {minspellid=21849,level=60, slot="WILD"}, -- Gift of the Wild 2
		[26990] = {minspellid=1126,level=70, slot="WILD"}, -- Mark of the Wild 8
		[26991] = {minspellid=21849,level=70, slot="WILD"}, -- Gift of the Wild 3
		[48469] = {minspellid=1126,level=80, slot="WILD"}, -- Mark of the Wild 9
		[48470] = {minspellid=21849,level=80, slot="WILD"}, -- Gift of the Wild 4
		
		[46119] = {minspellid=46119,level=70, slot="WILD_NPC"}, -- Blessing of D E H T A
	},
	["THORNS"] = {
		[467] = {minspellid=467,level=6, slot="THORNS"}, -- Thorns 1
		[782] = {minspellid=467,level=14, slot="THORNS"}, -- Thorns 2
		[1075] = {minspellid=467,level=24, slot="THORNS"}, -- Thorns 3
		[8914] = {minspellid=467,level=34, slot="THORNS"}, -- Thorns 4
		[9756] = {minspellid=467,level=44, slot="THORNS"}, -- Thorns 5
		[9910] = {minspellid=467,level=54, slot="THORNS"}, -- Thorns 6
		[26992] = {minspellid=467,level=64, slot="THORNS"}, -- Thorns 7
		[53307] = {minspellid=467,level=74, slot="THORNS"}, -- Thorns 8
	},
	["SPIRIT"] = {
		[14752] = {minspellid=14752,level=30, slot="SPIRIT"}, -- Divine Spirit 1
		[14818] = {minspellid=14752,level=40, slot="SPIRIT"}, -- Divine Spirit 2
		[14819] = {minspellid=14752,level=50, slot="SPIRIT"}, -- Divine Spirit 3
		[27841] = {minspellid=14752,level=60, slot="SPIRIT"}, -- Divine Spirit 4
		[27681] = {minspellid=27681,level=60, slot="SPIRIT"}, -- Prayer of Spirit 1
		[25312] = {minspellid=14752,level=70, slot="SPIRIT"}, -- Divine Spirit 5
		[32999] = {minspellid=27681,level=70, slot="SPIRIT"}, -- Prayer of Spirit 2
		[48073] = {minspellid=14752,level=80, slot="SPIRIT"}, -- Divine Spirit 6
		[48074] = {minspellid=27681,level=80, slot="SPIRIT"}, -- Prayer of Spirit 3
	},
	["WARLOCK_ARMOR"] = {
		[687] = {minspellid=687,level=1, slot="WARLOCK_ARMOR"}, -- Demon Skin 1
		[696] = {minspellid=687,level=10, slot="WARLOCK_ARMOR"}, -- Demon Skin 2
		[706] = {minspellid=706,level=20, slot="WARLOCK_ARMOR"}, -- Demon Armor 1
		[1086] = {minspellid=706,level=30, slot="WARLOCK_ARMOR"}, -- Demon Armor 2
		[11733] = {minspellid=706,level=40, slot="WARLOCK_ARMOR"}, -- Demon Armor 3
		[11734] = {minspellid=706,level=50, slot="WARLOCK_ARMOR"}, -- Demon Armor 4
		[11735] = {minspellid=706,level=60, slot="WARLOCK_ARMOR"}, -- Demon Armor 5
		[27260] = {minspellid=706,level=70, slot="WARLOCK_ARMOR"}, -- Demon Armor 6
		[47793] = {minspellid=706,level=76, slot="WARLOCK_ARMOR"}, -- Demon Armor 7
		[47889] = {minspellid=706,level=80, slot="WARLOCK_ARMOR"}, -- Demon Armor 8
		[28176] = {minspellid=28176,level=62, slot="WARLOCK_ARMOR"}, -- Fel Armor 1
		[28189] = {minspellid=28176,level=69, slot="WARLOCK_ARMOR"}, -- Fel Armor 2
		[47892] = {minspellid=28176,level=74, slot="WARLOCK_ARMOR"}, -- Fel Armor 3
		[47893] = {minspellid=28176,level=79, slot="WARLOCK_ARMOR"}, -- Fel Armor 4
	},
	["MAGE_ARMOR"] = {
		[6117] = {minspellid=6117,level=34, slot="MAGE_ARMOR"}, -- Mage Armor 1
		[22782] = {minspellid=6117,level=46, slot="MAGE_ARMOR"}, -- Mage Armor 2
		[22783] = {minspellid=6117,level=58, slot="MAGE_ARMOR"}, -- Mage Armor 3
		[27125] = {minspellid=6117,level=69, slot="MAGE_ARMOR"}, -- Mage Armor 4
		[43023] = {minspellid=6117,level=71, slot="MAGE_ARMOR"}, -- Mage Armor 5
		[43024] = {minspellid=6117,level=79, slot="MAGE_ARMOR"}, -- Mage Armor 6
		[30482] = {minspellid=30482,level=62, slot="MAGE_ARMOR"}, -- Molten Armor 1
		[43045] = {minspellid=30482,level=71, slot="MAGE_ARMOR"}, -- Molten Armor 2
		[43046] = {minspellid=30482,level=79, slot="MAGE_ARMOR"}, -- Molten Armor 3
		[168] = {minspellid=168,level=1, slot="MAGE_ARMOR"}, -- Frost Armor 1
		[7300] = {minspellid=168,level=10, slot="MAGE_ARMOR"}, -- Frost Armor 2
		[7301] = {minspellid=168,level=20, slot="MAGE_ARMOR"}, -- Frost Armor 3
		[7302] = {minspellid=7302,level=30, slot="MAGE_ARMOR"}, -- Ice Armor 1
		[7320] = {minspellid=7302,level=40, slot="MAGE_ARMOR"}, -- Ice Armor 2
		[10219] = {minspellid=7302,level=50, slot="MAGE_ARMOR"}, -- Ice Armor 3
		[10220] = {minspellid=7302,level=60, slot="MAGE_ARMOR"}, -- Ice Armor 4
		[27124] = {minspellid=7302,level=69, slot="MAGE_ARMOR"}, -- Ice Armor 5
		[43008] = {minspellid=7302,level=79, slot="MAGE_ARMOR"}, -- Ice Armor 6
	},
	["PALADIN_SEAL"] = {
		[53736] = {minspellid=53736,level=66, slot="SEALS"}, -- seal of corruption
		[20164] = {minspellid=20164,level=22, slot="SEALS"}, -- seal of justice
		[20165] = {minspellid=20165,level=30, slot="SEALS"}, -- seal of light
		[20154] = {minspellid=20154,level=1, slot="SEALS"}, -- seal of righteousness
		[31801] = {minspellid=31801,level=64, slot="SEALS"}, -- seal of vengeance
		[20166] = {minspellid=20166,level=38, slot="SEALS"}, -- seal of wisdom
		[20375] = {minspellid=20375,level=20, slot="SEALS"}, -- seal of command
	},
	["RIGHTEOUS_FURY"] = {
		[25780] = {minspellid=25780,level=20, slot="RIGHTEOUS_FURY"}, -- Righteous Fury
	},
	["PRIEST_FORM"] = {
		[15473] = {minspellid=15473,level=40, slot="PRIEST_FORM"}, -- Shadow Form
	},

	["OWL_FORM"] = {
		[24858] = {minspellid=24858,level=40, slot="SHAPESHIFT"}, -- Owl Form
	},

	["TREE_FORM"] = {
		[33891] = {minspellid=33891,level=50, slot="SHAPESHIFT"}, -- Tree Form
	},
	["PRIEST_INNER"] = {
		[588] = {minspellid=588,level=12, slot="PRIEST_INNER"}, -- Inner Fire 1
		[7128] = {minspellid=588,level=20, slot="PRIEST_INNER"}, -- Inner Fire 2
		[602] = {minspellid=588,level=30, slot="PRIEST_INNER"}, -- Inner Fire 3
		[1006] = {minspellid=588,level=40, slot="PRIEST_INNER"}, -- Inner Fire 4
		[10951] = {minspellid=588,level=50, slot="PRIEST_INNER"}, -- Inner Fire 5
		[10952] = {minspellid=588,level=60, slot="PRIEST_INNER"}, -- Inner Fire 6
		[25431] = {minspellid=588,level=69, slot="PRIEST_INNER"}, -- Inner Fire 7
		[48040] = {minspellid=588,level=71, slot="PRIEST_INNER"}, -- Inner Fire 8
		[48168] = {minspellid=588,level=77, slot="PRIEST_INNER"}, -- Inner Fire 9
	},
	["EMBRACE"] = {
		[15286] = {minspellid=15286,level=30, slot="EMBRACE"}, -- Vampiric Embrace
	},
}


BBConstants.base.BuffPriorities = {
	[BBConstants.base.Roles.None] = {},
	[BBConstants.base.Roles.Unknown] = {},
	[BBConstants.base.Roles.ManaUser] = {
		["STAMINA"] = 4,
		["WILD"] = 3,
		["SPIRIT"] = 2,
		["INTELLECT"] = 1,
	},
	[BBConstants.base.Roles.NoMana] = {
		["STAMINA"] = 2,
		["WILD"] = 1,
	},
	[BBConstants.base.Roles.Tank] = {
		["PALADIN_SEAL"] = 11,
		["TANK"] = 10,
		["HP"] = 9,
		["STATS"] = 8,
		["STAMINA"] = 7,
		["WILD"] = 6,
		["AP"] = 5,
		["THORNS"] = 4,
		["STRENGTH_AGILITY"] = 3,
		["MELEE_HASTE"] = 2,
		["ARMOR"] = 1,
		["SHADOW_RESIST"] = 0
	},
	[BBConstants.base.Roles.PureMelee] = {
		["AP"] = 7,
		["STATS"] = 6,
		["HP"] = 5,
		["WILD"] = 4,
		["STAMINA"] = 3,
		["STRENGTH_AGILITY"] = 2,
		["MELEE_HASTE"] = 1,
		["SHADOW_RESIST"] = 0
	},
	[BBConstants.base.Roles.MeleeMana] = {
		["PALADIN_SEAL"] = 13,
		["AP"] = 12,
		["STATS"] = 11,
		["MP5"] = 10,
		["HP"] = 9,
		["WILD"] = 8,
		["INTELLECT"] = 7,
		["STAMINA"] = 6,
		["STRENGTH_AGILITY"] = 5,
		["MELEE_HASTE"] = 4,
		["FLAT_SPELL_CRIT"] = 3,
		["FLAT_SPELL"] = 2,
		["SPELL_HASTE"] = 1,
		["SHADOW_RESIST"] = 0},
	[BBConstants.base.Roles.Caster] = {
		["EMBRACE"] = 13,
		["PALADIN_SEAL"] = 12,
		["STATS"] = 11,
		["MP5"] = 10,
		["HP"] = 9,
		["WILD"] = 8,
		["INTELLECT"] = 7,
		["SPIRIT"] = 6,
		["STAMINA"] = 5,
		["FLAT_SPELL_CRIT"] = 4,
		["FLAT_SPELL"] = 3,
		["SPELL_HASTE"] = 2,
		["SHADOW_RESIST"] = 1,
	},
	[BBConstants.base.Roles.MeleeMana_Low] = {
		["PALADIN_SEAL"] = 13,
		["MP5"] = 12,
		["AP"] = 11,
		["STATS"] = 10,
		["HP"] = 9,
		["WILD"] = 8,
		["INTELLECT"] = 7,
		["STAMINA"] = 6,
		["STRENGTH_AGILITY"] = 5,
		["MELEE_HASTE"] = 4,
		["FLAT_SPELL_CRIT"] = 3,
		["FLAT_SPELL"] = 2,
		["SPELL_HASTE"] = 1,
		["SHADOW_RESIST"] = 0
	},
	[BBConstants.base.Roles.Healer] = {
		["EMBRACE"] = 12,
		["PALADIN_SEAL"] = 11,
		["MP5"] = 10,
		["STATS"] = 9,
		["HP"] = 8,
		["WILD"] = 7,
		["INTELLECT"] = 6,
		["SPIRIT"] = 5,
		["STAMINA"] = 4,
		["FLAT_SPELL_CRIT"] = 3,
		["FLAT_SPELL"] = 2,
		["SPELL_HASTE"] = 1,
		["SHADOW_RESIST"] = 0
	},
}

BBConstants.base.classDefaults = {
	[BBConstants.base.Classes.Warrior] = {
		profile = {
			slots = {
				[1] = {
					["SHOUTS"] = true,
				},
				[2] = {
					["SHOUTS"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Deathknight] = {
		profile = {
			slots = {
				[1] = {
					["HORNS"] = true,
				},
				[2] = {
					["HORNS"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Paladin] = {
		profile = {
			refreshAtDuration = 300,
			raidBuffAttendThreshold = 90,
			friendly = true,
			slots = {
				[1] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
					--["AURAS"] = true,
				},
				[2] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
					--["AURAS"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Shaman] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					["WATER_TOTEMS"] = true,
					["EARTH_TOTEMS"] = true,
					["FIRE_TOTEMS"] = true,
					["AIR_TOTEMS"] = true,
					-- ["SHAMAN_WEAPONS"] = true,
				},
				[2] = {
					["WATER_TOTEMS"] = true,
					["EARTH_TOTEMS"] = true,
					["FIRE_TOTEMS"] = true,
					["AIR_TOTEMS"] = true,
					-- ["SHAMAN_WEAPONS"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Hunter] = {
		profile = {
			slots = {
				[1] = {
				},
				[2] = {
				},
			},
		},
	},
	[BBConstants.base.Classes.Rogue] = {
		profile = {
			slots = {
				[1] = {
					-- ["ROGUE_POISONS"] = true,
				},
				[2] = {
					-- ["ROGUE_POISONS"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Druid] = {
		profile = {
			refreshAtDuration = 300,
			raidBuffAttendThreshold = 90,
			raidBuffHeadCountThreshold = 2,
			slots = {
				[1] = {
					["THORNS"] = true,
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
				[2] = {
					["THORNS"] = true,
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
			},
		},
	},
	[BBConstants.base.Classes.Warlock] = {
		profile = {
			slots = {
				[1] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
				[2] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Priest] = {
		profile = {
			refreshAtDuration = 300,
			raidBuffAttendThreshold = 90,
			raidBuffHeadCountThreshold = 2,
			slots = {
				[1] = {
					["FORTITUDE"] = true,
					["SPIRIT"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
				[2] = {
					["FORTITUDE"] = true,
					["SPIRIT"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
			},
		},
	},
	[BBConstants.base.Classes.Mage] = {
		profile = {
			refreshAtDuration = 300,
			raidBuffAttendThreshold = 90,
			raidBuffHeadCountThreshold = 2,
			slots = {
				[1] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
				[2] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
			},
		},
	},
}

function BBConstants.base:RoleFromTalents(Role1, Role2, Role3, DefaultRole)
	local spentPoints1, spentPoints2, spentPoints3
	local probableRole = DefaultRole
	local version = select(4, GetBuildInfo())
	
	-- determine role, based on deepest talent tree investment

	spentPoints1 = select(3, GetTalentTabInfo(1, true, false, self:GetActiveSpec(true, false)))
	spentPoints2 = select(3, GetTalentTabInfo(2, true, false, self:GetActiveSpec(true, false)))
	spentPoints3 = select(3, GetTalentTabInfo(3, true, false, self:GetActiveSpec(true, false)))

	if (spentPoints1 > spentPoints2) and (spentPoints1 > spentPoints3) then
		probableRole = Role1
	elseif (spentPoints2 > spentPoints1) and (spentPoints2 > spentPoints3) then
		probableRole = Role2
	elseif (spentPoints3 > spentPoints1) and (spentPoints3 > spentPoints2) then
		probableRole = Role3
	end
				
			
	return probableRole
end

function BBConstants.base:CurrentTotemSpell(slot)
	local spellid = nil
	
	-- if: can deduce the action bar destination
	if slot and self.Totems[slot] then
	
		-- what totem are we using right meow?
		_, _, _, spellid = GetActionInfo(self.Totems[slot])
	end -- if: can deduce the action bar destination
	
	return spellid
end

--[[ CATACLYSM ]]

function BBConstants.cataclysm:GetActiveSpec()
    return GetActiveTalentGroup(true, false)
end

function BBConstants.cataclysm:GetNumSpecs()
	return GetNumTalentGroups()
end

function BBConstants.cataclysm:GetNumGroupMembers()
	local numMembers
	
	numMembers = GetNumRaidMembers()
	
	if 0 == numMembers then
		numMembers = GetNumPartyMembers()
	end
end

function BBConstants.cataclysm:SpellInfoFromID(spellid)
	local slotName
	local buffLabels
	local scope

	local slot
	local spellidTable
	
	-- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)
	for slot, spellidTable in pairs(self.BuffSlots) do
		
		-- if: spell exists in this application lookup table
		if spellidTable[spellid] then

			-- figure out the relevant label, and other cool info
			buffLabels = spellidTable[spellid].Types
			slotName = slot
			scope = spellidTable[spellid].Scope
			
			break
		end -- if: spell exists in this application lookup table
	end -- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)

	return buffLabels, slotName, scope
end


function BBConstants.cataclysm:CurrentTotemSpell(slot)
	local spellid = nil
	
	-- if: can deduce the action bar destination
	if slot and self.Totems[slot] then
	
		-- what totem are we using right meow?
		_, spellid = GetActionInfo(self.Totems[slot])
	end -- if: can deduce the action bar destination
	
	return spellid
end

function BBConstants.cataclysm:RoleFromTalents(Role1, Role2, Role3, DefaultRole)
	local spentPoints1, spentPoints2, spentPoints3
	local probableRole = DefaultRole
	local version = select(4, GetBuildInfo())
	
	-- determine role, based on deepest talent tree investment

	spentPoints1 = select(5, GetTalentTabInfo(1, true, false, self:GetActiveSpec(true, false)))
	spentPoints2 = select(5, GetTalentTabInfo(2, true, false, self:GetActiveSpec(true, false)))
	spentPoints3 = select(5, GetTalentTabInfo(3, true, false, self:GetActiveSpec(true, false)))

	if (spentPoints1 > spentPoints2) and (spentPoints1 > spentPoints3) then
		probableRole = Role1
	elseif (spentPoints2 > spentPoints1) and (spentPoints2 > spentPoints3) then
		probableRole = Role2
	elseif (spentPoints3 > spentPoints1) and (spentPoints3 > spentPoints2) then
		probableRole = Role3
	end

	--[[
	if select(8, GetTalentTabInfo(1, true, false, self:GetActiveSpec(true, false))) then
		probableRole = Role1
	elseif select(8, GetTalentTabInfo(2, true, false, self:GetActiveSpec(true, false))) then
		probableRole = Role2
	elseif select(8, GetTalentTabInfo(3, true, false, self:GetActiveSpec(true, false))) then
		probableRole = Role3
	end
	]]
	
	return probableRole
end

BBConstants.cataclysm.Buffs = {
		None = 1, -- can't provide
		ProfessionStats = 2, -- Leatherworking Kings
		Basic = 3, -- class inherent (shaman/warrior)
		BasicLong = 4, -- class inherent (paladin): wisdom, might, kings, sanctuary
		MinorTalented = 5, -- partial talent investment, warrior (1,2 /5), shaman (1/3)
		PartialTalented = 6, -- partial talent investment, druid (1/2), priest (1/2)
		PartialTalentedLong = 7, -- partial talent investment, paladin (1/2)
		MajorTalented = 8, -- partial talent investment, warrior (3,4 /5), shaman (2/3)
		FullTalented = 8, -- 3/3 shaman totems, 5/5 warrior shouts, druid (2/2), priest (2/2)
		FullTalentedLong = 9, -- 2/2 paladin wisdom, 2/2 Paladin might
		Level = 10, -- Scales with level of Player/Applicator
		Awesome = 11, -- way better than anything we could do
	}

BBConstants.cataclysm.Scope = {
		Individual = 1,
		Class = 2,
		Totem = 3,
		ShortRaid = 4,
		LongRaid = 5,
		PassiveRaid = 6,
		Pet = 7,
		Raid = 8,
		Self = 9,
	}

function BBConstants.cataclysm:IsRaidWide(scope)

	return scope and (
		scope == self.Scope.Raid
		or scope == self.Scope.Totem
		or scope == self.Scope.ShortRaid
		or scope == self.Scope.LongRaid
		or scope == self.Scope.PassiveRaid
		or scope == self.Scope.Pet)
end

BBConstants.cataclysm.Forms = { -- warrior stances are dum-dums for now, until blizzard makes them an aura, OR, forms are checked on spellcast instead of aura scan (which is cludgy)
		[71] = BBConstants.cataclysm.Roles.Tank, -- defensive stance
		[2457] = BBConstants.cataclysm.Roles.PureMelee, -- battle stance
		[2458] = BBConstants.cataclysm.Roles.PureMelee, -- Berserker stance
		[25780] = BBConstants.cataclysm.Roles.Tank, -- righteous fury
		[48263] = BBConstants.cataclysm.Roles.Tank, -- frost presence
		[48265] = BBConstants.cataclysm.Roles.PureMelee, -- unholy presence
		[48266] = BBConstants.cataclysm.Roles.PureMelee, -- blood presence
		[5487] = BBConstants.cataclysm.Roles.Tank, -- Bear Form
		[9634] = BBConstants.cataclysm.Roles.Tank, -- Dire Bear Form
		[768] = BBConstants.cataclysm.Roles.PureMelee, -- Cat Form
}

BBConstants.cataclysm.BuffTypes = {
	NONE = "NONE",
	STRENGTH_AGILITY = "STRENGTH_AGILITY",
	ARMOR = "ARMOR",
	HEALTH = "HEALTH",
	MANA_POOL = "MANA_POOL",
	MANA_REGEN = "MANA_REGEN",
	AP = "AP",
	FLAT_CRIT = "FLAT_CRIT",
	MELEE_HASTE = "MELEE_HASTE",
	SPELL_HASTE = "SPELL_HASTE",
	SPELL_POWER = "SPELL_POWER",
	STATS = "STATS",
	SHADOW_RESIST = "SHADOW_RESIST",
	HP5 = "HP5",
	SOLO_FIRE_TOTEM = "SOLO_FIRE_TOTEM",
	WARLOCK_ARMOR = "WARLOCK_ARMOR",
	MAGE_ARMOR = "MAGE_ARMOR",
	PALADIN_SEAL = "PALADIN_SEAL", -- done
	RIGHTEOUS_FURY = "RIGHTEOUS_FURY", -- done
	PRIEST_FORM = "PRIEST_FORM",
	OWL_FORM = "OWL_FORM",
	PRIEST_INNER = "PRIEST_INNER",
	EMBRACE = "EMBRACE",
	REFLECTION = "REFLECTION",
	NO_PUSHBACK = "NO_PUSHBACK",
	RESISTANCE = "RESISTANCE",
	MOUNT_SPEED = "MOUNT_SPEED",
}

BBConstants.cataclysm.BuffSlots = {
	--[[ Template:
	["BLESSINGS"] = { <- mutually exclusive grouping; caster can only have one of these on the target at once
		[79102] = { <- spellid of the applied aura
			Score = BBConstants.cataclysm.Buffs.BasicLong, <- potency of this buff;  if the buff scales with level, this the caster's level
			Scales = nil, <- nil, or true if the buff scales with the caster's level
			AppliedBy = nil, <- nil, or spellid of the application mechanism, if different than the applied spellid (aka spellid of "summon imp")
			Type = BBConstants.cataclysm.BuffTypes.AP, <- Type of raid buff;  players can only benefit from one of each "type"
			MinLevel = 56, <- players under this level will not receive the buff
			Scope = BBConstants.cataclysm.Scope.LongRaid}, <- how the buff is applied (cast? put on a totem slot?  hits the entire raid?  just the player?)
	]]
	["BLESSINGS"] = { -- Done
		[79102] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.MANA_REGEN,BBConstants.cataclysm.BuffTypes.AP,}, MinLevel = 56, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- might
		[79063] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- kings
	},
	["SEALS"] = { -- Done
		[20164] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PALADIN_SEAL,}, MinLevel = 64, Scope = BBConstants.cataclysm.Scope.Self}, -- seal of justice
		[20165] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PALADIN_SEAL,}, MinLevel = 30, Scope = BBConstants.cataclysm.Scope.Self}, -- seal of insight
		[20154] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PALADIN_SEAL,}, MinLevel = 3, Scope = BBConstants.cataclysm.Scope.Self}, -- seal of righteousness
		[31801] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PALADIN_SEAL,}, MinLevel = 44, Scope = BBConstants.cataclysm.Scope.Self}, -- seal of truth
	},
	["AURAS"] = { -- Done
		[465] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.ARMOR,}, MinLevel = 5, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Devotion
		[7294] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.REFLECTION,}, MinLevel = 26, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Retribution
		[19746] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NO_PUSHBACK,}, MinLevel = 42, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Concentration
		[19891] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.RESISTANCE,}, MinLevel = 76, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Resistance
		[32223] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.MOUNT_SPEED,}, MinLevel = 62, Mounted = true, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Crusader
	},
	["SHOUTS"] = { -- Done
		[469] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.HEALTH,}, MinLevel = 68, Scope = BBConstants.cataclysm.Scope.ShortRaid}, -- commanding
		[6673] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.STRENGTH_AGILITY,}, MinLevel = 32, Scope = BBConstants.cataclysm.Scope.ShortRaid}, -- battle
	},
	["ICY_TALONS"] = {
		[55610] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.MELEE_HASTE,}, MinLevel = 39, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- improved icy talons
	},
	["HORNS"] = {
		[57330] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.STRENGTH_AGILITY,}, MinLevel = 65, Scope = BBConstants.cataclysm.Scope.ShortRaid}, -- horn of winter
	},
	["WATER_TOTEMS"] = {
		[5677] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 5675, Types = {BBConstants.cataclysm.BuffTypes.MANA_REGEN,}, MinLevel = 26, Scope = BBConstants.cataclysm.Scope.Totem}, -- mana spring
		[8185] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 8184, Types = {BBConstants.cataclysm.BuffTypes.RESISTANCE,}, MinLevel = 62, Scope = BBConstants.cataclysm.Scope.Totem}, -- elemental resistance
		[87717] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 87718, Types = {BBConstants.cataclysm.BuffTypes.NO_PUSHBACK,}, MinLevel = 74, Scope = BBConstants.cataclysm.Scope.Totem}, -- Tranquil Mind
	},
	["EARTH_TOTEMS"] = {
		[8072] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 8071, Types = {BBConstants.cataclysm.BuffTypes.ARMOR,}, MinLevel = 4, Scope = BBConstants.cataclysm.Scope.Totem}, -- stoneskin
		[8076] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 8075, Types = {BBConstants.cataclysm.BuffTypes.STRENGTH_AGILITY,}, MinLevel = 10, Scope = BBConstants.cataclysm.Scope.Totem}, -- strength of earth
	},
	["FIRE_TOTEMS"] = {
		[52109] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 8227, Types = {BBConstants.cataclysm.BuffTypes.SPELL_POWER,}, MinLevel = 28, Scope = BBConstants.cataclysm.Scope.Totem}, -- flametongue
		[3599] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 3599, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 10, Scope = BBConstants.cataclysm.Scope.Totem}, -- searing totem
	},
	["AIR_TOTEMS"] = {
		[8515] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 8512, Types = {BBConstants.cataclysm.BuffTypes.MELEE_HASTE,}, MinLevel = 32, Scope = BBConstants.cataclysm.Scope.Totem}, -- windfury
		[2895] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = 3738, Types = {BBConstants.cataclysm.BuffTypes.SPELL_HASTE,}, MinLevel = 64, Scope = BBConstants.cataclysm.Scope.Totem}, -- wrath of air
	},
	["FORTITUDE"] = { -- Done
		[79105] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.HEALTH,}, MinLevel = 1, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- Power Word: Fortitude
	},
	["BRILLIANCE"] = { -- Done, pending Brilliance
		[79038] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.MANA_POOL,BBConstants.cataclysm.BuffTypes.SPELL_POWER,}, MinLevel = 80, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- Dalaran Brilliance (confirm spellid)
		[79058] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.MANA_POOL,BBConstants.cataclysm.BuffTypes.SPELL_POWER,}, MinLevel = 48, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- Arcane Brilliance
	},
	["WILD"] = { -- Done
		-- 79060 is ALSO considered "mark of the wild" on wowhead & in game;  what's the diff??
		[79061] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.STATS,}, MinLevel = 1, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- Mark of the Wild
	},
	["WILD_NPC"] = {
		[46119] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.STATS,}, MinLevel = 70, Scope = BBConstants.cataclysm.Scope.Individual}, -- Blessing of D E H T A
	},
	["PRIEST_INNER"] = { -- Done
		[588] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PRIEST_INNER,}, MinLevel = 12, Scope = BBConstants.cataclysm.Scope.Self}, -- Inner Fire
		[73413] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PRIEST_INNER,}, MinLevel = 83, Scope = BBConstants.cataclysm.Scope.Self}, -- Inner Will
	},
	["PRIEST_PROTECTION"] = { -- Done
		[79107] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.SHADOW_RESIST,}, MinLevel = 52, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- Shadow Protection
	},
	["EMBRACE"] = {
		[15286] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.EMBRACE,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.Self}, -- Vampiric Embrace
	},
	["MAGE_ARMOR"] = {
		[6117] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 68, Scope = BBConstants.cataclysm.Scope.Self}, -- Mage Armor
		[7302] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 54, Scope = BBConstants.cataclysm.Scope.Self}, -- Frost Armor
		[30482] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 34, Scope = BBConstants.cataclysm.Scope.Self}, -- Molten Armor
	},
	["WARLOCK_ARMOR"] = {
		[687] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 1, Scope = BBConstants.cataclysm.Scope.Self}, -- Demon Skin
		[28176] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 62, Scope = BBConstants.cataclysm.Scope.Self}, -- Fel Armor
	},
	["RIGHTEOUS_FURY"] = {
		[25780] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.RIGHTEOUS_FURY,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.Self}, -- Righteous Fury
	},
	["PRIEST_FORM"] = {
		[15473] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.PRIEST_FORM,}, MinLevel = 40, Scope = BBConstants.cataclysm.Scope.Self}, -- Shadow Form
	},

	["SHAPESHIFT"] = { -- done
		[24858] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.NONE,}, MinLevel = 40, Scope = BBConstants.cataclysm.Scope.Self}, -- Owl Form
	},

	["MOONKIN_AURA"] = {
		[24907] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.SPELL_HASTE,}, MinLevel = 40, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Moonkin Aura
	},
	
	["OATHS"] = { -- done
		[51466] = {Score = BBConstants.cataclysm.Buffs.PartialTalented, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Elemental Oath [1/1]
		[51470] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 26, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Elemental Oath [2/2]
	},
	
	["WRATHFUL"] = { -- done
		[77746] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.SPELL_POWER,}, MinLevel = 30, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Totemic Wrath
	},

	["ABOMINATION"] = { -- done
		[53137] = {Score = BBConstants.cataclysm.Buffs.PartialTalented, Types = {BBConstants.cataclysm.BuffTypes.AP,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Abomination's Might [1/2]
		[53138] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.AP,}, MinLevel = 21, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Abomination's Might [2/2]
	},

	["RAMPAGE"] = { -- done
		[29801] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Rampage
	},

	["PACK"] = { -- done
		[17007] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Leader of the Pack
	},
	
	["PACT"] = { -- done
		[47236] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.SPELL_POWER}, MinLevel = 35, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Demonic Pact (Demonology)
	},	

	["PROFESSION_STATS"] = {
		[69378] = {Score = BBConstants.cataclysm.Buffs.ProfessionStats, Types = {BBConstants.cataclysm.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.cataclysm.Scope.LongRaid}, -- forgotten kings
	},
	
	["QUICKENING"] = { -- done
		[49868] = {Score = BBConstants.cataclysm.Buffs.Basic, Types = {BBConstants.cataclysm.BuffTypes.SPELL_HASTE,}, MinLevel = 40, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Shadow Form/Mind Quickening
	},

	["PET"] = { -- done
		[6307] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = {L["Imp"],}, Types = {BBConstants.cataclysm.BuffTypes.HEALTH,}, MinLevel = 4, Scope = BBConstants.cataclysm.Scope.Pet}, -- Blood Pact (Imp)
		[54424] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = {L["Felhunter"],}, Types = {BBConstants.cataclysm.BuffTypes.MANA_REGEN,BBConstants.cataclysm.BuffTypes.MANA_POOL}, MinLevel = 32, Scope = BBConstants.cataclysm.Scope.Pet}, -- Fel Intelligence (Felhunter)
		[93435] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = {L["Cat"],L["Spirit Beast"],}, Types = {BBConstants.cataclysm.BuffTypes.STRENGTH_AGILITY,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.Pet}, -- Roar of Courage (Cats, Spirit Beasts)
		[90309] = {Score = BBConstants.cataclysm.Buffs.FullTalented, AppliedBy = {L["Devilsaur"],}, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.Pet}, -- Terrifying Roar (Devilsaurs)
		[24604] = {Score = BBConstants.cataclysm.Buffs.FullTalented, AppliedBy = {L["Wolf"],}, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.Pet}, -- Furious Howl (Wolves)
		[90363] = {Score = BBConstants.cataclysm.Buffs.Basic, AppliedBy = {L["Shale Spider"],}, Types = {BBConstants.cataclysm.BuffTypes.STATS,}, MinLevel = 20, Scope = BBConstants.cataclysm.Scope.Pet}, -- Embrace of the Shale Spider (Shale Spiders)
	},
	
	-- Auras
	["TRUESHOT"] = {
		[19506] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.AP,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Trueshot Aura
	},
	
	-- Subtlety Rogue: FLAT_CRIT
	["THIEVES"] = {
		[51699] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Honor among Thieves
	},
		
	-- Survival Hunter: MELEE_HASTE
	["HUNTING"] = {
		[53290] = {Score = BBConstants.cataclysm.Buffs.FullTalented, Types = {BBConstants.cataclysm.BuffTypes.MELEE_HASTE,}, MinLevel = 30, Scope = BBConstants.cataclysm.Scope.PassiveRaid}, -- Hunting Party
	},
}

BBConstants.cataclysm.PetBuff = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	[L["Imp"] ] = 6307,
	]]
}

BBConstants.cataclysm.DownRankLookup = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	["SHADOW_RESIST"] = {
		[976] = {minspellid=976, worstSpellID,level=30, slot="PRIEST_PROTECTION"},
	},
	]]
}

BBConstants.cataclysm.Pets = {
	[L["Bat"]] = L["Bat"],
	[L["Bear"]] = L["Bear"],
	[L["Bird of Prey"]] = L["Bird of Prey"],
	[L["Boar"]] = L["Boar"],
	[L["Carrion Bird"]] = L["Carrion Bird"],
	[L["Cat"]] = L["Cat"],
	[L["Chimaera"]] = L["Chimaera"],
	[L["Core Hound"]] = L["Core Hound"],
	[L["Crab"]] = L["Crab"],
	[L["Crocolisk"]] = L["Crocolisk"],
	[L["Devilsaur"]] = L["Devilsaur"],
	[L["Doomguard"]] = L["Doomguard"],
	[L["Dragonhawk"]] = L["Dragonhawk"],
	[L["Felguard"]] = L["Felguard"],
	[L["Felhunter"]] = L["Felhunter"],
	[L["Ghoul"]] = L["Ghoul"],
	[L["Gorilla"]] = L["Gorilla"],
	[L["Hyena"]] = L["Hyena"],
	[L["Imp"]] = L["Imp"],
	[L["Moth"]] = L["Moth"],
	[L["Nether Ray"]] = L["Nether Ray"],
	[L["Raptor"]] = L["Raptor"],
	[L["Ravager"]] = L["Ravager"],
	[L["Remote Control"]] = L["Remote Control"],
	[L["Rhino"]] = L["Rhino"],
	[L["Scorpid"]] = L["Scorpid"],
	[L["Serpent"]] = L["Serpent"],
	[L["Silithid"]] = L["Silithid"],
	[L["Spider"]] = L["Spider"],
	[L["Spirit Beast"]] = L["Spirit Beast"],
	[L["Sporebat"]] = L["Sporebat"],
	[L["Succubus"]] = L["Succubus"],
	[L["Tallstrider"]] = L["Tallstrider"],
	[L["Turtle"]] = L["Turtle"],
	[L["Voidwalker"]] = L["Voidwalker"],
	[L["Warp Stalker"]] = L["Warp Stalker"],
	[L["Wasp"]] = L["Wasp"],
	[L["Wind Serpent"]] = L["Wind Serpent"],
	[L["Wolf"]] = L["Wolf"],
	[L["Worm"]] = L["Worm"],
}

BBConstants.cataclysm.BuffPriorities = {
	[BBConstants.cataclysm.Roles.None] = {},
	[BBConstants.cataclysm.Roles.Unknown] = {},
	[BBConstants.cataclysm.Roles.ManaUser] = {
		["STATS"] = 8,
		["HEALTH"] = 7,
		["SPELL_HASTE"] = 6,
		["FLAT_CRIT"] = 5,
		["SPELL_POWER"] = 4,
		["MANA_POOL"] = 3,
		["SHADOW_RESIST"] = 2,
		["MANA_REGEN"] = 1,
	},
	[BBConstants.cataclysm.Roles.NoMana] = {
		["STATS"] = 8,
		["MELEE_HASTE"] = 7,
		["AP"] = 6,
		["FLAT_CRIT"] = 5,
		["STATS"] = 4,
		["STRENGTH_AGILITY"] = 3,
		["HEALTH"] = 2,
		["SHADOW_RESIST"] = 1,
	},
	[BBConstants.cataclysm.Roles.Tank] = {
		["MOUNT_SPEED"] = 12,
		["HEALTH"] = 11,
		["STATS"] = 10,
		["STRENGTH_AGILITY"] = 9,
		["MELEE_HASTE"] = 8,
		["AP"] = 7,
		["FLAT_CRIT"] = 6,
		["SHADOW_RESIST"] = 5,
		["MANA_REGEN"] = 4,
		["ARMOR"] = 3,
		["RESISTANCE"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.cataclysm.Roles.PureMelee] = {
		["MELEE_HASTE"] = 9,
		["AP"] = 8,
		["FLAT_CRIT"] = 7,
		["STATS"] = 6,
		["STRENGTH_AGILITY"] = 5,
		["HEALTH"] = 4,
		["SHADOW_RESIST"] = 3,
		["MANA_REGEN"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.cataclysm.Roles.MeleeMana] = {
		["MOUNT_SPEED"] = 14,
		["MELEE_HASTE"] = 13,
		["AP"] = 12,
		["FLAT_CRIT"] = 11,
		["STATS"] = 10,
		["STRENGTH_AGILITY"] = 9,
		["HEALTH"] = 8,
		["SPELL_POWER"] = 7,
		["MANA_POOL"] = 6,
		["MANA_REGEN"] = 5,
		["SPELL_HASTE"] = 4,
		["SHADOW_RESIST"] = 3,
		["MANA_REGEN"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.cataclysm.Roles.Caster] = {
		["MOUNT_SPEED"] = 10,
		["STATS"] = 9,
		["SPELL_HASTE"] = 8,
		["FLAT_CRIT"] = 7,
		["SPELL_POWER"] = 6,
		["MANA_POOL"] = 5,
		["MANA_REGEN"] = 4,
		["HEALTH"] = 3,
		["SHADOW_RESIST"] = 2,
		["NO_PUSHBACK"] = 1,
	},
	[BBConstants.cataclysm.Roles.Healer] = {
		["MOUNT_SPEED"] = 10,
		["MANA_REGEN"] = 9,
		["STATS"] = 8,
		["SPELL_POWER"] = 7,
		["MANA_POOL"] = 6,
		["SPELL_HASTE"] = 5,
		["FLAT_CRIT"] = 4,
		["HEALTH"] = 3,
		["SHADOW_RESIST"] = 2,
		["NO_PUSHBACK"] = 1,
	},
}

BBConstants.cataclysm.classDefaults = {
	[BBConstants.cataclysm.Classes.Warrior] = {
		profile = {
			slots = {
				[1] = {
					["SHOUTS"] = true,
				},
				[2] = {
					["SHOUTS"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Deathknight] = {
		profile = {
			slots = {
				[1] = {
					["HORNS"] = true,
				},
				[2] = {
					["HORNS"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Paladin] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
					["AURAS"] = true,
				},
				[2] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
					["AURAS"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Shaman] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					["WATER_TOTEMS"] = true,
					["EARTH_TOTEMS"] = true,
					["FIRE_TOTEMS"] = true,
					["AIR_TOTEMS"] = true,
					-- ["SHAMAN_WEAPONS"] = true,
				},
				[2] = {
					["WATER_TOTEMS"] = true,
					["EARTH_TOTEMS"] = true,
					["FIRE_TOTEMS"] = true,
					["AIR_TOTEMS"] = true,
					-- ["SHAMAN_WEAPONS"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Hunter] = {
		profile = {
			slots = {
				[1] = {
				},
				[2] = {
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Rogue] = {
		profile = {
			slots = {
				[1] = {
					-- ["ROGUE_POISONS"] = true,
				},
				[2] = {
					-- ["ROGUE_POISONS"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Druid] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
				[2] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Warlock] = {
		profile = {
			slots = {
				[1] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
				[2] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Priest] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["FORTITUDE"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
				[2] = {
					["FORTITUDE"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
			},
		},
	},
	[BBConstants.cataclysm.Classes.Mage] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
				[2] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
			},
		},
	},
}

--[[ PANDAS ]]

function BBConstants.pandas:GetActiveSpec()
    return GetActiveSpecGroup()
end

function BBConstants.pandas:GetNumSpecs()
	return GetNumSpecGroups()
end

function BBConstants.pandas:GetNumGroupMembers()
	return GetNumGroupMembers()
end

function BBConstants.pandas:SpellInfoFromID(spellid)
	local slotName
	local buffLabels
	local scope

	local slot
	local spellidTable
	
	-- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)
	for slot, spellidTable in pairs(self.BuffSlots) do
		
		-- if: spell exists in this application lookup table
		if spellidTable[spellid] then

			-- figure out the relevant label, and other cool info
			buffLabels = spellidTable[spellid].Types
			slotName = slot
			scope = spellidTable[spellid].Scope
			
			break
		end -- if: spell exists in this application lookup table
	end -- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)

	return buffLabels, slotName, scope
end


function BBConstants.pandas:CurrentTotemSpell(slot)
	local spellid = nil
	
	-- if: can deduce the action bar destination
	if slot and self.Totems[slot] then
	
		-- what totem are we using right meow?
		_, spellid = GetActionInfo(self.Totems[slot])
	end -- if: can deduce the action bar destination
	
	return spellid
end

function BBConstants.pandas:RoleFromTalents(Role1, Role2, Role3, DefaultRole)
	local SpecializationIndex
	local probableRole = DefaultRole
	
	-- determine role, based on deepest talent tree investment

	SpecializationIndex = GetInspectSpecialization("unit")

	-- TODO:  decode specializationIndex into a Role
	-- a lookup table would probably work great for this;  11 classes x 3 roles per class + 1 guardian druid
	
	return probableRole
end

BBConstants.pandas.Buffs = {
		None = 1, -- can't provide
		ProfessionStats = 2, -- Leatherworking Kings
		Basic = 3, -- class inherent (shaman/warrior)
		BasicLong = 4, -- class inherent (paladin): wisdom, might, kings, sanctuary
		MinorTalented = 5, -- partial talent investment, warrior (1,2 /5), shaman (1/3)
		PartialTalented = 6, -- partial talent investment, druid (1/2), priest (1/2)
		PartialTalentedLong = 7, -- partial talent investment, paladin (1/2)
		MajorTalented = 8, -- partial talent investment, warrior (3,4 /5), shaman (2/3)
		FullTalented = 8, -- 3/3 shaman totems, 5/5 warrior shouts, druid (2/2), priest (2/2)
		FullTalentedLong = 9, -- 2/2 paladin wisdom, 2/2 Paladin might
		Level = 10, -- Scales with level of Player/Applicator
		Awesome = 11, -- way better than anything we could do
	}

BBConstants.pandas.Scope = {
		Individual = 1,
		Class = 2,
		Totem = 3,
		ShortRaid = 4,
		LongRaid = 5,
		PassiveRaid = 6,
		Pet = 7,
		Raid = 8,
		Self = 9,
	}

function BBConstants.pandas:IsRaidWide(scope)

	return scope and (
		scope == self.Scope.Raid
		or scope == self.Scope.Totem
		or scope == self.Scope.ShortRaid
		or scope == self.Scope.LongRaid
		or scope == self.Scope.PassiveRaid
		or scope == self.Scope.Pet)
end

BBConstants.pandas.Forms = { -- warrior stances are dum-dums for now, until blizzard makes them an aura, OR, forms are checked on spellcast instead of aura scan (which is cludgy)
		[71] = BBConstants.pandas.Roles.Tank, -- defensive stance
		[2457] = BBConstants.pandas.Roles.PureMelee, -- battle stance
		[2458] = BBConstants.pandas.Roles.PureMelee, -- Berserker stance
		[25780] = BBConstants.pandas.Roles.Tank, -- righteous fury
		[48263] = BBConstants.pandas.Roles.Tank, -- frost presence
		[48265] = BBConstants.pandas.Roles.PureMelee, -- unholy presence
		[48266] = BBConstants.pandas.Roles.PureMelee, -- blood presence
		[5487] = BBConstants.pandas.Roles.Tank, -- Bear Form
		[9634] = BBConstants.pandas.Roles.Tank, -- Dire Bear Form
		[768] = BBConstants.pandas.Roles.PureMelee, -- Cat Form
}

BBConstants.pandas.BuffTypes = {
	NONE = "NONE",
	STRENGTH_AGILITY = "STRENGTH_AGILITY",
	ARMOR = "ARMOR",
	HEALTH = "HEALTH", -- 10% Stamina
	MANA_POOL = "MANA_POOL",
	MANA_REGEN = "MANA_REGEN",
	AP = "AP", -- 10% Attack Power
	FLAT_CRIT = "FLAT_CRIT", -- 5% Critical Strike
	MELEE_HASTE = "MELEE_HASTE",
	SPELL_HASTE = "SPELL_HASTE",
	SPELL_POWER = "SPELL_POWER", -- 10% Spell Power
	STATS = "STATS", -- 5% Strength, Agility, & Intellect
	SHADOW_RESIST = "SHADOW_RESIST",
	HP5 = "HP5",
	SOLO_FIRE_TOTEM = "SOLO_FIRE_TOTEM",
	WARLOCK_ARMOR = "WARLOCK_ARMOR",
	MAGE_ARMOR = "MAGE_ARMOR",
	PALADIN_SEAL = "PALADIN_SEAL",
	RIGHTEOUS_FURY = "RIGHTEOUS_FURY",
	PRIEST_FORM = "PRIEST_FORM",
	OWL_FORM = "OWL_FORM",
	PRIEST_INNER = "PRIEST_INNER",
	EMBRACE = "EMBRACE",
	REFLECTION = "REFLECTION",
	NO_PUSHBACK = "NO_PUSHBACK",
	RESISTANCE = "RESISTANCE",
	MOUNT_SPEED = "MOUNT_SPEED",
	MASTERY = "MASTERY", -- 3000 Mastery
}

BBConstants.pandas.BuffSlots = {
	--[[ Template:
	["BLESSINGS"] = { <- mutually exclusive grouping; caster can only have one of these on the target at once
		[79102] = { <- spellid of the applied aura
			Score = BBConstants.pandas.Buffs.BasicLong, <- potency of this buff;  if the buff scales with level, this the caster's level
			Scales = nil, <- nil, or true if the buff scales with the caster's level
			AppliedBy = nil, <- nil, or spellid of the application mechanism, if different than the applied spellid (aka spellid of "summon imp")
			Type = BBConstants.pandas.BuffTypes.AP, <- Type of raid buff;  players can only benefit from one of each "type"
			MinLevel = 56, <- players under this level will not receive the buff
			Scope = BBConstants.pandas.Scope.LongRaid}, <- how the buff is applied (cast? put on a totem slot?  hits the entire raid?  just the player?)
	]]
	["BLESSINGS"] = {
		[19740] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.pandas.Scope.LongRaid}, -- Blessing of Might
		[20217] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 30, Scope = BBConstants.pandas.Scope.LongRaid}, -- Blessing of Kings
	},
	["SEALS"] = {
		[105361] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PALADIN_SEAL,}, MinLevel = 3, Scope = BBConstants.pandas.Scope.Self}, -- Seal of Command
		[20165] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PALADIN_SEAL,}, MinLevel = 32, Scope = BBConstants.pandas.Scope.Self}, -- Seal of Insight
		[20154] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PALADIN_SEAL,}, MinLevel = 42, Scope = BBConstants.pandas.Scope.Self}, -- Seal of Righteousness
		[31801] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PALADIN_SEAL,}, MinLevel = 24, Scope = BBConstants.pandas.Scope.Self}, -- Seal of Truth
	},
	["SHOUTS"] = {
		[469] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.HEALTH,}, MinLevel = 68, Scope = BBConstants.pandas.Scope.ShortRaid}, -- Commanding Shout
		[6673] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.AP,}, MinLevel = 42, Scope = BBConstants.pandas.Scope.ShortRaid}, -- Battle Shout
	},
	["UNHOLY"] = {
		[55610] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.MELEE_HASTE,}, MinLevel = 60, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Unholy Aura
	},
	["HORNS"] = {
		[57330] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.AP,}, MinLevel = 65, Scope = BBConstants.pandas.Scope.ShortRaid}, -- Horn of Winter
	},
	["LEGACIES"] = {
		[116781] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 81, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Legacy of the White Tiger
		[115921] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Legacy of the Emperor
	},
	["FORTITUDE"] = {
		[21562] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.HEALTH,}, MinLevel = 22, Scope = BBConstants.pandas.Scope.LongRaid}, -- Power Word: Fortitude
	},
	["BRILLIANCE"] = {
		[61316] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,BBConstants.pandas.BuffTypes.SPELL_POWER,}, MinLevel = 80, Scope = BBConstants.pandas.Scope.LongRaid}, -- Dalaran Brilliance
		[1459] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,BBConstants.pandas.BuffTypes.SPELL_POWER,}, MinLevel = 58, Scope = BBConstants.pandas.Scope.LongRaid}, -- Arcane Brilliance
	},
	["WILD"] = {
		-- 79060 is ALSO considered "mark of the wild" on wowhead & in game;  what's the diff??
		[1126] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 62, Scope = BBConstants.pandas.Scope.LongRaid}, -- Mark of the Wild
	},
	["WILD_NPC"] = {
		[46119] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 70, Scope = BBConstants.pandas.Scope.Individual}, -- Blessing of D E H T A
	},
	["RIGHTEOUS_FURY"] = {
		[25780] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.RIGHTEOUS_FURY,}, MinLevel = 12, Scope = BBConstants.pandas.Scope.Self}, -- Righteous Fury
	},
	["PRIEST_INNER"] = { -- THN TODO:  Left off here updating spellids etc
		[588] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PRIEST_INNER,}, MinLevel = 12, Scope = BBConstants.pandas.Scope.Self}, -- Inner Fire
		[73413] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PRIEST_INNER,}, MinLevel = 83, Scope = BBConstants.pandas.Scope.Self}, -- Inner Will
	},
	["PRIEST_PROTECTION"] = {
		[79107] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.SHADOW_RESIST,}, MinLevel = 52, Scope = BBConstants.pandas.Scope.LongRaid}, -- Shadow Protection
	},
	["EMBRACE"] = {
		[15286] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.EMBRACE,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.Self}, -- Vampiric Embrace
	},
	["MAGE_ARMOR"] = {
		[6117] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 68, Scope = BBConstants.pandas.Scope.Self}, -- Mage Armor
		[7302] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 54, Scope = BBConstants.pandas.Scope.Self}, -- Frost Armor
		[30482] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 34, Scope = BBConstants.pandas.Scope.Self}, -- Molten Armor
	},
	["WARLOCK_ARMOR"] = {
		[687] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 1, Scope = BBConstants.pandas.Scope.Self}, -- Demon Skin
		[28176] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 62, Scope = BBConstants.pandas.Scope.Self}, -- Fel Armor
	},
	["PRIEST_FORM"] = {
		[15473] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.PRIEST_FORM,}, MinLevel = 40, Scope = BBConstants.pandas.Scope.Self}, -- Shadow Form
	},

	["SHAPESHIFT"] = { -- done
		[24858] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.NONE,}, MinLevel = 40, Scope = BBConstants.pandas.Scope.Self}, -- Owl Form
	},

	["MOONKIN_AURA"] = {
		[24907] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.SPELL_HASTE,}, MinLevel = 40, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Moonkin Aura
	},
	
	["OATHS"] = { -- done
		[51466] = {Score = BBConstants.pandas.Buffs.PartialTalented, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Elemental Oath [1/1]
		[51470] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 26, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Elemental Oath [2/2]
	},
	
	["WRATHFUL"] = { -- done
		[77746] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.SPELL_POWER,}, MinLevel = 30, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Totemic Wrath
	},

	["ABOMINATION"] = { -- done
		[53137] = {Score = BBConstants.pandas.Buffs.PartialTalented, Types = {BBConstants.pandas.BuffTypes.AP,}, MinLevel = 20, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Abomination's Might [1/2]
		[53138] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.AP,}, MinLevel = 21, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Abomination's Might [2/2]
	},

	["RAMPAGE"] = { -- done
		[29801] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Rampage
	},

	["PACK"] = { -- done
		[17007] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Leader of the Pack
	},
	
	["PACT"] = { -- done
		[47236] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.SPELL_POWER}, MinLevel = 35, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Demonic Pact (Demonology)
	},	

	["PROFESSION_STATS"] = {
		[69378] = {Score = BBConstants.pandas.Buffs.ProfessionStats, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.pandas.Scope.LongRaid}, -- forgotten kings
	},
	
	["QUICKENING"] = { -- done
		[49868] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.pandas.BuffTypes.SPELL_HASTE,}, MinLevel = 40, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Shadow Form/Mind Quickening
	},

	["PET"] = { -- done
		[6307] = {Score = BBConstants.pandas.Buffs.Basic, AppliedBy = {L["Imp"],}, Types = {BBConstants.pandas.BuffTypes.HEALTH,}, MinLevel = 4, Scope = BBConstants.pandas.Scope.Pet}, -- Blood Pact (Imp)
		[54424] = {Score = BBConstants.pandas.Buffs.Basic, AppliedBy = {L["Felhunter"],}, Types = {BBConstants.pandas.BuffTypes.MANA_REGEN,BBConstants.pandas.BuffTypes.MANA_POOL}, MinLevel = 32, Scope = BBConstants.pandas.Scope.Pet}, -- Fel Intelligence (Felhunter)
		[93435] = {Score = BBConstants.pandas.Buffs.Basic, AppliedBy = {L["Cat"],L["Spirit Beast"],}, Types = {BBConstants.pandas.BuffTypes.STRENGTH_AGILITY,}, MinLevel = 20, Scope = BBConstants.pandas.Scope.Pet}, -- Roar of Courage (Cats, Spirit Beasts)
		[90309] = {Score = BBConstants.pandas.Buffs.FullTalented, AppliedBy = {L["Devilsaur"],}, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 20, Scope = BBConstants.pandas.Scope.Pet}, -- Terrifying Roar (Devilsaurs)
		[24604] = {Score = BBConstants.pandas.Buffs.FullTalented, AppliedBy = {L["Wolf"],}, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 20, Scope = BBConstants.pandas.Scope.Pet}, -- Furious Howl (Wolves)
		[90363] = {Score = BBConstants.pandas.Buffs.Basic, AppliedBy = {L["Shale Spider"],}, Types = {BBConstants.pandas.BuffTypes.STATS,}, MinLevel = 20, Scope = BBConstants.pandas.Scope.Pet}, -- Embrace of the Shale Spider (Shale Spiders)
	},
	
	-- Auras
	["TRUESHOT"] = {
		[19506] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.AP,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Trueshot Aura
	},
	
	-- Subtlety Rogue: FLAT_CRIT
	["THIEVES"] = {
		[51699] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.FLAT_CRIT,}, MinLevel = 25, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Honor among Thieves
	},
		
	-- Survival Hunter: MELEE_HASTE
	["HUNTING"] = {
		[53290] = {Score = BBConstants.pandas.Buffs.FullTalented, Types = {BBConstants.pandas.BuffTypes.MELEE_HASTE,}, MinLevel = 30, Scope = BBConstants.pandas.Scope.PassiveRaid}, -- Hunting Party
	},
}

BBConstants.pandas.PetBuff = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	[L["Imp"] ] = 6307,
	]]
}

BBConstants.pandas.DownRankLookup = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	["SHADOW_RESIST"] = {
		[976] = {minspellid=976, worstSpellID,level=30, slot="PRIEST_PROTECTION"},
	},
	]]
}

BBConstants.pandas.Pets = {
	[L["Bat"]] = L["Bat"],
	[L["Bear"]] = L["Bear"],
	[L["Bird of Prey"]] = L["Bird of Prey"],
	[L["Boar"]] = L["Boar"],
	[L["Carrion Bird"]] = L["Carrion Bird"],
	[L["Cat"]] = L["Cat"],
	[L["Chimaera"]] = L["Chimaera"],
	[L["Core Hound"]] = L["Core Hound"],
	[L["Crab"]] = L["Crab"],
	[L["Crocolisk"]] = L["Crocolisk"],
	[L["Devilsaur"]] = L["Devilsaur"],
	[L["Doomguard"]] = L["Doomguard"],
	[L["Dragonhawk"]] = L["Dragonhawk"],
	[L["Felguard"]] = L["Felguard"],
	[L["Felhunter"]] = L["Felhunter"],
	[L["Ghoul"]] = L["Ghoul"],
	[L["Gorilla"]] = L["Gorilla"],
	[L["Hyena"]] = L["Hyena"],
	[L["Imp"]] = L["Imp"],
	[L["Moth"]] = L["Moth"],
	[L["Nether Ray"]] = L["Nether Ray"],
	[L["Raptor"]] = L["Raptor"],
	[L["Ravager"]] = L["Ravager"],
	[L["Remote Control"]] = L["Remote Control"],
	[L["Rhino"]] = L["Rhino"],
	[L["Scorpid"]] = L["Scorpid"],
	[L["Serpent"]] = L["Serpent"],
	[L["Silithid"]] = L["Silithid"],
	[L["Spider"]] = L["Spider"],
	[L["Spirit Beast"]] = L["Spirit Beast"],
	[L["Sporebat"]] = L["Sporebat"],
	[L["Succubus"]] = L["Succubus"],
	[L["Tallstrider"]] = L["Tallstrider"],
	[L["Turtle"]] = L["Turtle"],
	[L["Voidwalker"]] = L["Voidwalker"],
	[L["Warp Stalker"]] = L["Warp Stalker"],
	[L["Wasp"]] = L["Wasp"],
	[L["Wind Serpent"]] = L["Wind Serpent"],
	[L["Wolf"]] = L["Wolf"],
	[L["Worm"]] = L["Worm"],
}

BBConstants.pandas.BuffPriorities = {
	[BBConstants.pandas.Roles.None] = {},
	[BBConstants.pandas.Roles.Unknown] = {},
	[BBConstants.pandas.Roles.ManaUser] = {
		["STATS"] = 8,
		["HEALTH"] = 7,
		["SPELL_HASTE"] = 6,
		["FLAT_CRIT"] = 5,
		["SPELL_POWER"] = 4,
		["MANA_POOL"] = 3,
		["SHADOW_RESIST"] = 2,
		["MANA_REGEN"] = 1,
	},
	[BBConstants.pandas.Roles.NoMana] = {
		["STATS"] = 8,
		["MELEE_HASTE"] = 7,
		["AP"] = 6,
		["FLAT_CRIT"] = 5,
		["STATS"] = 4,
		["STRENGTH_AGILITY"] = 3,
		["HEALTH"] = 2,
		["SHADOW_RESIST"] = 1,
	},
	[BBConstants.pandas.Roles.Tank] = {
		["MOUNT_SPEED"] = 12,
		["HEALTH"] = 11,
		["STATS"] = 10,
		["STRENGTH_AGILITY"] = 9,
		["MELEE_HASTE"] = 8,
		["AP"] = 7,
		["FLAT_CRIT"] = 6,
		["SHADOW_RESIST"] = 5,
		["MANA_REGEN"] = 4,
		["ARMOR"] = 3,
		["RESISTANCE"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.pandas.Roles.PureMelee] = {
		["MELEE_HASTE"] = 9,
		["AP"] = 8,
		["FLAT_CRIT"] = 7,
		["STATS"] = 6,
		["STRENGTH_AGILITY"] = 5,
		["HEALTH"] = 4,
		["SHADOW_RESIST"] = 3,
		["MANA_REGEN"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.pandas.Roles.MeleeMana] = {
		["MOUNT_SPEED"] = 14,
		["MELEE_HASTE"] = 13,
		["AP"] = 12,
		["FLAT_CRIT"] = 11,
		["STATS"] = 10,
		["STRENGTH_AGILITY"] = 9,
		["HEALTH"] = 8,
		["SPELL_POWER"] = 7,
		["MANA_POOL"] = 6,
		["MANA_REGEN"] = 5,
		["SPELL_HASTE"] = 4,
		["SHADOW_RESIST"] = 3,
		["MANA_REGEN"] = 2,
		["REFLECTION"] = 1,
	},
	[BBConstants.pandas.Roles.Caster] = {
		["MOUNT_SPEED"] = 10,
		["STATS"] = 9,
		["SPELL_HASTE"] = 8,
		["FLAT_CRIT"] = 7,
		["SPELL_POWER"] = 6,
		["MANA_POOL"] = 5,
		["MANA_REGEN"] = 4,
		["HEALTH"] = 3,
		["SHADOW_RESIST"] = 2,
		["NO_PUSHBACK"] = 1,
	},
	[BBConstants.pandas.Roles.Healer] = {
		["MOUNT_SPEED"] = 10,
		["MANA_REGEN"] = 9,
		["STATS"] = 8,
		["SPELL_POWER"] = 7,
		["MANA_POOL"] = 6,
		["SPELL_HASTE"] = 5,
		["FLAT_CRIT"] = 4,
		["HEALTH"] = 3,
		["SHADOW_RESIST"] = 2,
		["NO_PUSHBACK"] = 1,
	},
}

BBConstants.pandas.classDefaults = {
	[BBConstants.pandas.Classes.Monk] = {
		profile = {
			slots = {
				[1] = {
					["LEGACIES"] = true,
				},
				[2] = {
					["LEGACIES"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Warrior] = {
		profile = {
			slots = {
				[1] = {
					["SHOUTS"] = true,
				},
				[2] = {
					["SHOUTS"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Deathknight] = {
		profile = {
			slots = {
				[1] = {
					["HORNS"] = true,
				},
				[2] = {
					["HORNS"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Paladin] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
				},
				[2] = {
					["BLESSINGS"] = true,
					["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false, -- not quite working yet
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Shaman] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					-- ["SHAMAN_WEAPONS"] = true,
				},
				[2] = {
					-- ["SHAMAN_WEAPONS"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Hunter] = {
		profile = {
			slots = {
				[1] = {
				},
				[2] = {
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Rogue] = {
		profile = {
			slots = {
				[1] = {
					-- ["ROGUE_POISONS"] = true,
				},
				[2] = {
					-- ["ROGUE_POISONS"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Druid] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
				[2] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Warlock] = {
		profile = {
			slots = {
				[1] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
				[2] = {
					["WARLOCK_ARMOR"] = true,
					--["WARLOCK_WEAPON"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Priest] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["FORTITUDE"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
				[2] = {
					["FORTITUDE"] = true,
					["PRIEST_INNER"] = true,
					["PRIEST_PROTECTION"] = true,
					["EMBRACE"] = true,
					["PRIEST_FORM"] = true,
				},
			},
		},
	},
	[BBConstants.pandas.Classes.Mage] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
				[2] = {
					["BRILLIANCE"] = true,
					["MAGE_ARMOR"] = true,
					--["MAGE_STONE"] = true,
				},
			},
		},
	},
}

--[[ DRAENOR ]]

function BBConstants.draenor:GetActiveSpec()
    return GetActiveSpecGroup()
end

function BBConstants.draenor:GetNumSpecs()
	return GetNumSpecGroups()
end

function BBConstants.draenor:GetNumGroupMembers()
	return GetNumGroupMembers()
end

function BBConstants.draenor:SpellInfoFromID(spellid)
	local slotName
	local buffLabels
	local scope

	local slot
	local spellidTable
	
	-- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)
	for slot, spellidTable in pairs(self.BuffSlots) do
		
		-- if: spell exists in this application lookup table
		if spellidTable[spellid] then

			-- figure out the relevant label, and other cool info
			buffLabels = spellidTable[spellid].Types
			slotName = slot
			scope = spellidTable[spellid].Scope
			
			break
		end -- if: spell exists in this application lookup table
	end -- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)

	return buffLabels, slotName, scope
end

function BBConstants.draenor:LookupForm(spellid)
	local formNumber

	local slot
	local spellidTable
	
	-- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)
	for slot, spellidTable in pairs(self.BuffSlots) do
		
		-- if: spell exists in this application lookup table
		if spellidTable[spellid] then

			formNumber = spellidTable[spellid].Form
			break
		end -- if: spell exists in this application lookup table
	end -- for: each slot lookup map (HORNS, SEALS, WATER_TOTEMS, etc)

	return formNumber
end

function BBConstants.draenor:CurrentTotemSpell(slot)
	local spellid = nil
	
	-- if: can deduce the action bar destination
	if slot and self.Totems[slot] then
	
		-- what totem are we using right meow?
		_, spellid = GetActionInfo(self.Totems[slot])
	end -- if: can deduce the action bar destination
	
	return spellid
end

function BBConstants.draenor:RoleFromTalents(Role1, Role2, Role3, DefaultRole)
	local SpecializationIndex
	local probableRole = DefaultRole
	
	-- determine role, based on deepest talent tree investment

	SpecializationIndex = GetInspectSpecialization("unit")

	return probableRole
end

BBConstants.draenor.Buffs = {
		None = 1, -- can't provide
		ProfessionStats = 2, -- Leatherworking Kings
		Basic = 3, -- class inherent (shaman/warrior)
		Level = 10, -- Scales with level of Player/Applicator
		Awesome = 11, -- way better than anything we could do
	}

BBConstants.draenor.Scope = {
		Individual = 1,
		Class = 2,
		Totem = 3,
		ShortRaid = 4,
		LongRaid = 5,
		PassiveRaid = 6,
		Pet = 7,
		Raid = 8,
		Self = 9,
	}

function BBConstants.draenor:IsRaidWide(scope)

	return scope and (
		scope == self.Scope.Raid
		or scope == self.Scope.Totem
		or scope == self.Scope.ShortRaid
		or scope == self.Scope.LongRaid
		or scope == self.Scope.PassiveRaid
		or scope == self.Scope.Pet)
end

BBConstants.draenor.Forms = { -- warrior stances are dum-dums for now, until blizzard makes them an aura, OR, forms are checked on spellcast instead of aura scan (which is cludgy)
		[71] = BBConstants.draenor.Roles.Tank, -- defensive stance
		[2457] = BBConstants.draenor.Roles.PureMelee, -- battle stance
		[122989] = BBConstants.draenor.Roles.PureMelee, -- Berserker stance
		[25780] = BBConstants.draenor.Roles.Tank, -- righteous fury
		[48263] = BBConstants.draenor.Roles.Tank, -- blood presence
		[50371] = BBConstants.draenor.Roles.Tank, -- improved blood presence
		[48265] = BBConstants.draenor.Roles.PureMelee, -- unholy presence
		[50392] = BBConstants.draenor.Roles.PureMelee, -- improved unholy presence
		[48266] = BBConstants.draenor.Roles.PureMelee, -- frost presence
		[50385] = BBConstants.draenor.Roles.PureMelee, -- improved frost presence
		[5487] = BBConstants.draenor.Roles.Tank, -- Bear Form
		[768] = BBConstants.draenor.Roles.PureMelee, -- Cat Form
}

BBConstants.draenor.BuffTypes = {
	NONE = "NONE",
	HEALTH = "HEALTH", -- 10% Stamina
	AP = "AP", -- 10% Attack Power
	CRIT = "CRIT", -- 5% Critical Strike
	HASTE = "HASTE",
	SPELL_POWER = "SPELL_POWER", -- 10% Spell Power
	STATS = "STATS", -- 5% Strength, Agility, & Intellect
	MASTERY = "MASTERY", -- 3000 Mastery
	MULTISTRIKE = "MULTISTRIKE", -- 5% multistrike
	VERSATILITY = "VERSATILITY", -- 3% Versatility
	HP5 = "HP5",
	SOLO_FIRE_TOTEM = "SOLO_FIRE_TOTEM",
	PALADIN_SEAL = "PALADIN_SEAL",
	RIGHTEOUS_FURY = "RIGHTEOUS_FURY",
	PRIEST_FORM = "PRIEST_FORM",
	OWL_FORM = "OWL_FORM",
}

BBConstants.draenor.BuffSlots = {
	--[[ Template:
	["BLESSINGS"] = { <- mutually exclusive grouping; caster can only have one of these on the target at once
		[79102] = { <- spellid of the applied aura
			Score = BBConstants.draenor.Buffs.Basic, <- potency of this buff;  if the buff scales with level, this the caster's level
			Scales = nil, <- nil, or true if the buff scales with the caster's level
			AppliedBy = nil, <- nil, or spellid of the application mechanism, if different than the applied spellid (aka spellid of "summon imp")
			Type = BBConstants.draenor.BuffTypes.AP, <- Type of raid buff;  players can only benefit from one of each "type"
			MinLevel = 56, <- players under this level will not receive the buff
			Scope = BBConstants.draenor.Scope.LongRaid}, <- how the buff is applied (cast? put on a totem slot?  hits the entire raid?  just the player?)
	]]
	-- Paladin
	["BLESSINGS"] = {
		[19740] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.LongRaid, Spec={65,66,70}}, -- Blessing of Might
		[20217] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 30, Scope = BBConstants.draenor.Scope.LongRaid, Spec={65,66,70}}, -- Blessing of Kings
	},
	["SEALS"] = {
		[105361] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PALADIN_SEAL,}, MinLevel = 3, Scope = BBConstants.draenor.Scope.Self, Form = 1, Spec={65,66,70}}, -- Seal of Command
		[20165] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PALADIN_SEAL,}, MinLevel = 32, Scope = BBConstants.draenor.Scope.Self, Form = 4, Spec={65,66,70}}, -- Seal of Insight
		[20154] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PALADIN_SEAL,}, MinLevel = 42, Scope = BBConstants.draenor.Scope.Self, Form = 2, Spec={65,66,70}}, -- Seal of Righteousness
		[31801] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PALADIN_SEAL,}, MinLevel = 24, Scope = BBConstants.draenor.Scope.Self, Form = 1, Spec={65,66,70}}, -- Seal of Truth
		[20164] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PALADIN_SEAL,}, MinLevel = 70, Scope = BBConstants.draenor.Scope.Self, Form = 3, Spec={65,66,70}}, -- Seal of Justice
	},
	["SANCTITY"] = {
		[167187] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={70}}, -- Sanctity Aura
	},
	["RIGHTEOUS_FURY"] = {
		[25780] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.RIGHTEOUS_FURY,}, MinLevel = 12, Scope = BBConstants.draenor.Scope.Self, Spec={65,66,70}}, -- Righteous Fury
	},
	-- Warrior
	["SHOUTS"] = {
		[469] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HEALTH,}, MinLevel = 68, Scope = BBConstants.draenor.Scope.LongRaid, Spec={71,72,73}}, -- Commanding Shout
		[6673] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.AP,}, MinLevel = 42, Scope = BBConstants.draenor.Scope.LongRaid, Spec={71,72,73}}, -- Battle Shout
	},
	["PRESENCE"] = {
		[167188] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={71,72}}, -- Inspiring Presence
	},
	-- Death Knight
	["GRAVE"] = {
		[155522] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={250}}, -- Power of the Grave
	},
	["HORNS"] = {
		[57330] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.AP,}, MinLevel = 65, Scope = BBConstants.draenor.Scope.LongRaid, Spec={250,251,252}}, -- Horn of Winter
	},
	["UNHOLY"] = {
		[55610] = {Score = BBConstants.pandas.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MELEE_HASTE,BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 60, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={251,252}}, -- Unholy Aura
	},
	-- Monk
	["LEGACIES"] = {
		[116781] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.CRIT,BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.LongRaid, Spec={268,269}}, -- Legacy of the White Tiger
		[115921] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.LongRaid, Spec={270}}, -- Legacy of the Emperor
	},
	["FLURRY"] = {
		[166916] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={269}}, -- Windflurry
	},	
	-- Priest
	["QUICKENING"] = { 
		[49868] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HASTE,}, MinLevel = 26, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={258}}, -- Mind Quickening
	},
	["FORTITUDE"] = {
		[21562] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HEALTH,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.LongRaid, Spec={256,257,258}}, -- Power Word: Fortitude
	},
	["PRIEST_FORM"] = {
		[15473] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.PRIEST_FORM,}, MinLevel = 40, Scope = BBConstants.draenor.Scope.Self, Form = 1, Spec={258}}, -- Shadow Form
	},
	-- Mage
	["BRILLIANCE"] = {
		[61316] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.CRIT,BBConstants.draenor.BuffTypes.SPELL_POWER,}, MinLevel = 80, Scope = BBConstants.draenor.Scope.LongRaid, Spec={62,63,64}}, -- Dalaran Brilliance
		[1459] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.CRIT,BBConstants.draenor.BuffTypes.SPELL_POWER,}, MinLevel = 58, Scope = BBConstants.draenor.Scope.LongRaid, Spec={62,63,64}}, -- Arcane Brilliance
	},
	-- Druid
	["WILD"] = {
		-- 79060 is ALSO considered "mark of the wild" on wowhead & in game;  what's the diff??
		[1126] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 62, Scope = BBConstants.draenor.Scope.LongRaid, Spec={102,103,104,105}}, -- Mark of the Wild
	},
	["SHAPESHIFT"] = {
		[24858] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.NONE,}, MinLevel = 40, Scope = BBConstants.draenor.Scope.Self, Form = 5, Spec={102}}, -- Owl Form; form 5 ONLY if owl known.
	},
	["MOONKIN_AURA"] = {
		[24907] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 16, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={102}}, -- Moonkin Aura
	},
	["PACK"] = { 
		[17007] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 25, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={103}}, -- Leader of the Pack
	},
	-- Shaman
	["GRACE"] = {
		[116956] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HASTE,BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={262,263,264}}, -- Grace of Air
	},
	-- Warlock
	["INTENT"] = {
		[109733] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.SPELL_POWER,BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 82, Scope = BBConstants.draenor.Scope.LongRaid, Spec={265,266,267}}, -- Dark Intent
	},	
	["PACT"] = {
		[166928] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HEALTH}, MinLevel = 80, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={265,266,267}}, -- Blood Pact
	},	
	-- Rogue
	["CUNNING"] = {
		[113742] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HASTE,BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 30, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={259,260,261}}, -- Swiftblade's Cunning
	},	
	-- Hunter
	["TRUESHOT"] = {
		[19506] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.AP,}, MinLevel = 39, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={253,254,255}}, -- Trueshot Aura
	},
	["LONE_WOLF"] = {
		[160198] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Grace of the Cat
		[160203] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HASTE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Haste of the Hyena
		[160200] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Ferocity of the Raptor
		[172968] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Quickness of the Dragonhawk
		[172967] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Versatility of the Ravager
		[160205] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.SPELL_POWER,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Wisdom of the Serpent
		[160199] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.HEALTH,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Fortitude of the Bear
		[160206] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.PassiveRaid, Spec={254,255}}, -- Power of the Primates
	},

	-- NPC
	["WILD_NPC"] = {
		[46119] = {Score = BBConstants.draenor.Buffs.Basic, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 70, Scope = BBConstants.draenor.Scope.Individual}, -- Blessing of D E H T A
	},

	["PET"] = {
		[159988] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Dog"],}, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Bark of the Wild
		[160017] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Gorilla"],}, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Blessing of Kongs
		[90363] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Shale Spider"],}, Types = {BBConstants.draenor.BuffTypes.STATS,BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Embrace of the Shale Spider (Shale Spiders)
		[160077] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Worm"],}, Types = {BBConstants.draenor.BuffTypes.STATS,BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Strength of the Earth

		[50256] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Bear"],}, Types = {BBConstants.draenor.BuffTypes.HEALTH,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Invigorating Roar
		[160014] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Goat"],}, Types = {BBConstants.draenor.BuffTypes.HEALTH,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness
		[160003] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Rylak"],}, Types = {BBConstants.draenor.BuffTypes.HEALTH,BBConstants.draenor.BuffTypes.HASTE}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Savage Vigor
		[90364] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Silithid"],}, Types = {BBConstants.draenor.BuffTypes.HEALTH,BBConstants.draenor.BuffTypes.SPELL_POWER}, MinLevel = 4, Scope = BBConstants.draenor.Scope.Pet}, -- Qiraji Fortitude

		[128433] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Serpent"],}, Types = {BBConstants.draenor.BuffTypes.SPELL_POWER,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Serpent's Cunning
		[126309] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Waterstrider"],}, Types = {BBConstants.draenor.BuffTypes.SPELL_POWER,BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Still Water

		[93435] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Cat"]}, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.Pet}, -- Roar of Courage
		[160039] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Hydra"]}, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.Pet}, -- Keen Senses
		[128997] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Spirit Beast"]}, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.Pet}, -- Spirit Beast Blessing
		[160073] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Tallstrider"]}, Types = {BBConstants.draenor.BuffTypes.MASTERY,}, MinLevel = 81, Scope = BBConstants.draenor.Scope.Pet}, -- Plainswalking

		[128432] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Hyena"],}, Types = {BBConstants.draenor.BuffTypes.HASTE,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Cackling Howl
		[135678] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Sporebat"],}, Types = {BBConstants.draenor.BuffTypes.HASTE,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Energizing Spores
		[160074] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Wasp"],}, Types = {BBConstants.draenor.BuffTypes.HASTE,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.Pet}, -- Speed of the Swarm

		[90309] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Devilsaur"],}, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Terrifying Roar
		[126373] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Quilen"],}, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Fearless Roar
		[160052] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Raptor"],}, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Strength of the Pack
		[24604] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Wolf"],}, Types = {BBConstants.draenor.BuffTypes.CRIT,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Furious Howl

		[50519] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Bat"],}, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sonic Focus
		[57386] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Clefthoof"],}, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Wild Strength
		[58604] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Core Hound"],}, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Double Bite
		[34889] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Dragonhawk"],}, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Spry Attacks
		[24844] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Wind Serpent"],}, Types = {BBConstants.draenor.BuffTypes.MULTISTRIKE,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Breath of the Winds

		[159735] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Bird of Prey"],}, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness
		[35290] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Boar"],}, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness
		[160045] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Porcupine"],}, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness
		[160014] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Ravager"],}, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness
		[173035] = {Score = BBConstants.draenor.Buffs.Basic, AppliedBy = {L["Stag"],}, Types = {BBConstants.draenor.BuffTypes.VERSATILITY,}, MinLevel = 20, Scope = BBConstants.draenor.Scope.Pet}, -- Sturdiness

	},
	-- crafted items
	["PROFESSION_STATS"] = {
		[69378] = {Score = BBConstants.draenor.Buffs.ProfessionStats, Types = {BBConstants.draenor.BuffTypes.STATS,}, MinLevel = 22, Scope = BBConstants.draenor.Scope.LongRaid}, -- forgotten kings
	},
}

BBConstants.draenor.PetBuff = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	[L["Imp"] ] = 6307,
	]]
}

BBConstants.draenor.DownRankLookup = {
	-- Automatically generated at startup, from available BuffSlots
	--[[
	["SHADOW_RESIST"] = {
		[976] = {minspellid=976, worstSpellID,level=30, slot="PRIEST_PROTECTION"},
	},
	]]
}

BBConstants.draenor.Pets = {
	[L["Bat"]] = L["Bat"],
	[L["Bear"]] = L["Bear"],
	[L["Bird of Prey"]] = L["Bird of Prey"],
	[L["Boar"]] = L["Boar"],
	[L["Carrion Bird"]] = L["Carrion Bird"],
	[L["Cat"]] = L["Cat"],
	[L["Chimaera"]] = L["Chimaera"],
	[L["Clefthoof"]] = L["Clefthoof"],
	[L["Core Hound"]] = L["Core Hound"],
	[L["Crab"]] = L["Crab"],
	[L["Crocolisk"]] = L["Crocolisk"],
	[L["Devilsaur"]] = L["Devilsaur"],
	[L["Dog"]] = L["Dog"],
	[L["Doomguard"]] = L["Doomguard"],
	[L["Dragonhawk"]] = L["Dragonhawk"],
	[L["Felguard"]] = L["Felguard"],
	[L["Felhunter"]] = L["Felhunter"],
	[L["Ghoul"]] = L["Ghoul"],
	[L["Goat"]] = L["Goat"],
	[L["Gorilla"]] = L["Gorilla"],
	[L["Hydra"]] = L["Hydra"],
	[L["Hyena"]] = L["Hyena"],
	[L["Imp"]] = L["Imp"],
	[L["Moth"]] = L["Moth"],
	[L["Nether Ray"]] = L["Nether Ray"],
	[L["Porcupine"]] = L["Porcupine"],
	[L["Quilen"]] = L["Quilen"],
	[L["Raptor"]] = L["Raptor"],
	[L["Ravager"]] = L["Ravager"],
	[L["Remote Control"]] = L["Remote Control"],
	[L["Rhino"]] = L["Rhino"],
	[L["Rylak"]] = L["Rylak"],
	[L["Scorpid"]] = L["Scorpid"],
	[L["Serpent"]] = L["Serpent"],
	[L["Shale Spider"]] = L["Shale Spider"],
	[L["Silithid"]] = L["Silithid"],
	[L["Spider"]] = L["Spider"],
	[L["Spirit Beast"]] = L["Spirit Beast"],
	[L["Sporebat"]] = L["Sporebat"],
	[L["Stag"]] = L["Stag"],
	[L["Succubus"]] = L["Succubus"],
	[L["Tallstrider"]] = L["Tallstrider"],
	[L["Turtle"]] = L["Turtle"],
	[L["Voidwalker"]] = L["Voidwalker"],
	[L["Warp Stalker"]] = L["Warp Stalker"],
	[L["Wasp"]] = L["Wasp"],
	[L["Waterstrider"]] = L["Waterstrider"],
	[L["Wind Serpent"]] = L["Wind Serpent"],
	[L["Wolf"]] = L["Wolf"],
	[L["Worm"]] = L["Worm"],
}

BBConstants.draenor.BuffPriorities = {
	[BBConstants.draenor.Roles.None] = {},
	[BBConstants.draenor.Roles.Unknown] = {
		["AP"] = 9,
		["SPELL_POWER"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["STATS"] = 2,
		["HEALTH"] = 1,
	},
	[BBConstants.draenor.Roles.ManaUser] = {
		["SPELL_POWER"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
		["AP"] = 1,
	},
	[BBConstants.draenor.Roles.NoMana] = {
		["AP"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
	},
	[BBConstants.draenor.Roles.Tank] = {
		["HEALTH"] = 10,
		["AP"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["SPELL_POWER"] = 1,
	},
	[BBConstants.draenor.Roles.PureMelee] = {
		["AP"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
	},
	[BBConstants.draenor.Roles.MeleeMana] = {
		["AP"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
		["SPELL_POWER"] = 1,

	},
	[BBConstants.draenor.Roles.Caster] = {
		["SPELL_POWER"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
		["AP"] = 1,

	},
	[BBConstants.draenor.Roles.Healer] = {
		["SPELL_POWER"] = 9,
		["STATS"] = 8,
		["HASTE"] = 7,
		["CRIT"] = 6,
		["MASTERY"] = 5,
		["MULTISTRIKE"] = 4,
		["VERSATILITY"] = 3,
		["HEALTH"] = 2,
		["AP"] = 1,
	},
}

BBConstants.draenor.classDefaults = {
	[BBConstants.draenor.Classes.Monk] = {
		profile = {
			slots = {
				[1] = {
					["LEGACIES"] = true,
				},
				[2] = {
					["LEGACIES"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Warrior] = {
		profile = {
			slots = {
				[1] = {
					["SHOUTS"] = true,
				},
				[2] = {
					["SHOUTS"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Deathknight] = {
		profile = {
			slots = {
				[1] = {
					["HORNS"] = true,
				},
				[2] = {
					["HORNS"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Paladin] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					["BLESSINGS"] = true,
					--["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false,
				},
				[2] = {
					["BLESSINGS"] = true,
					--["SEALS"] = true,
					["RIGHTEOUS_FURY"] = false,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Shaman] = {
		profile = {
			refreshAtDuration = 300,
			friendly = true,
			slots = {
				[1] = {
					-- ["SHAMAN_WEAPONS"] = true,
				},
				[2] = {
					-- ["SHAMAN_WEAPONS"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Hunter] = {
		profile = {
			slots = {
				[1] = {
				},
				[2] = {
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Rogue] = {
		profile = {
			slots = {
				[1] = {
					-- ["ROGUE_POISONS"] = true,
				},
				[2] = {
					-- ["ROGUE_POISONS"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Druid] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
				[2] = {
					["WILD"] = true,
					["SHAPESHIFT"] = false,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Warlock] = {
		profile = {
			slots = {
				[1] = {
				},
				[2] = {
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Priest] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["FORTITUDE"] = true,
					["PRIEST_FORM"] = true,
				},
				[2] = {
					["FORTITUDE"] = true,
					["PRIEST_FORM"] = true,
				},
			},
		},
	},
	[BBConstants.draenor.Classes.Mage] = {
		profile = {
			refreshAtDuration = 300,
			slots = {
				[1] = {
					["BRILLIANCE"] = true,
				},
				[2] = {
					["BRILLIANCE"] = true,
				},
			},
		},
	},
}