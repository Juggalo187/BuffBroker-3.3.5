--[[ PlayerState.Lua

This file (should eventually) contain logic for player, party, and raid state.  This includes:

Responsibilities:
-Record the current solo/party/raid roster
-Record the current auras on each group member (filtered to auras of interest)
-Record aura choices/decisions/commitments of group members (aka pally1 cast kings on everyone)
-Track events related to roster changes
-Track events related to aura changes
-

Dependencies:
A reference to a watcher object, to which notifications will be sent
A reference to a constants object, which describes what auras should be monitored
A reference to a proxy object, which will forward wow events, and provide access to wow API calls

Architecture:
Built as a Lua list, with a custom metatable, ala "setmetatable(instance_of, {__index = master_object})"
Group members will probably be implemented each as a list, with a custom metatable for "GroupMemberType"
The master list will use the proxy for access to wow stuff (UnitAuras, AURA_CHANGE_EVENT, stuff like that)
the frame will notify the watcher, if significant states change
]]

-- load localization strings
local L = LibStub('AceLocale-3.0'):GetLocale('BuffBroker')

-- Namespace
BBPlayerState = {}
BBPlayerState.base = {}

-- Constructors

-- create a new instance from the base "base class"
function BBPlayerState.base:new()
	local newInstance = {}
	setmetatable(newInstance,self)
	self.__index = self
	return newInstance
end

BBPlayerState.classic = BBPlayerState.base:new()
BBPlayerState.cataclysm = BBPlayerState.base:new()
BBPlayerState.draenor = BBPlayerState.base:new()

-- Create a new Player State based on the version
function BBPlayerState:new (clientVersion, constants)
	local newInstance = nil

	-- if: Wrath of the Lich King
	if 30300 == clientVersion then
		-- use base class
		newInstance = BBPlayerState.classic:new()
	elseif clientVersion < 6000 then
		-- use new hotness
		newInstance = BBPlayerState.cataclysm:new()
	else
		newInstance = BBPlayerState.draenor:new()
	end

	-- use provided constants object
	newInstance.Constants = constants

	return newInstance	
end

--[[ Wrath of the Lich King Functions ]]

BBPlayerState.base.PlayerGUID = nil
BBPlayerState.base.Players = {}
BBPlayerState.base.PlayerCount = 0
BBPlayerState.base.ProfiledBuffProviders = nil
BBPlayerState.base.StalePlayerGUID = nil
BBPlayerState.base.lastCast = {}

BBPlayerState.base.Classes = {}
BBPlayerState.base.Coverage = {}

function BBPlayerState.base:Initialize(parentFrame)

end

function BBPlayerState.base:Iterator()
	local lastID = nil
	local lastProfile = nil
	
	return function ()
		lastID, lastProfile = next(self.Players, lastID)

		return lastID, lastProfile
	end
end

function BBPlayerState.base:ClassIterator(theClass)
	local lastID = nil
	local lastProfile = nil
	local lastClass = theClass
	
	return function ()
		lastID, lastProfile = next(self.Players, lastID)
		while lastID and lastProfile.Class ~= lastClass and self.Constants.Classes.Raid ~= lastClass do
			lastID, lastProfile = next(self.Players, lastID)
		end
		
		return lastID, lastProfile
	end
end

function BBPlayerState.base:MyGUID()

	if nil == BBPlayerState.base.PlayerGUID then
		BBPlayerState.base.PlayerGUID = UnitGUID('player')
	end
		
	return BBPlayerState.base.PlayerGUID

end

function BBPlayerState.base:GetPlayerCount()

	return self.PlayerCount
end

function BBPlayerState.base:AddProfile(unitGUID, unitProfile)

	if unitGUID and unitProfile then
		if nil == self.Players[unitGUID] then
			self.PlayerCount = self.PlayerCount + 1
		end
		
		self.Players[unitGUID] = unitProfile
		
	end

end

function BBPlayerState.base:RemoveProfile(unitGUID)

	if unitGUID then
		if self.Players[unitGUID] then
			self.PlayerCount = self.PlayerCount - 1
		end
		
		self.Players[unitGUID] = nil
		
	end

end

function BBPlayerState.base:GetProfileByName(unitName)
	local unitProfile = nil

	if unitName then
		unitProfile = self:GetProfile(UnitGUID(unitName))
	end
	
	return unitProfile
end

function BBPlayerState.base:GetProfile(unitGUID)
	local unitProfile = nil
	
	if unitGUID then
		unitProfile = self.Players[unitGUID]
	end
	
	return unitProfile
end

function BBPlayerState.base:GetAttribute(unitGUID, attribute)
	local value = nil

	if self.Players[unitGUID] then
		value = self.Players[unitGUID][attribute]
	end
	
	return value
end

function BBPlayerState.base:SetAttribute(unitGUID, attribute, value)

	if self.Players and self.Players[unitGUID] then
		self.Players[unitGUID][attribute] = value
	end
	
end

function BBPlayerState.base:UpdateClassState()
	local targetGUID, targetProfile
	local totalNear = 0
	local totalObscured = 0
	
	for _, className in pairs(self.Constants.Classes) do
		self.Classes[className].Near = 0
		self.Classes[className].Obscured = 0
	end
	
	for targetGUID, targetProfile in self:Iterator() do
		if targetProfile.Near then
			self.Classes[targetProfile.Class].Near = self.Classes[targetProfile.Class].Near + 1
			totalNear = totalNear + 1
		end

		if targetProfile.Obscured then
			self.Classes[targetProfile.Class].Obscured = self.Classes[targetProfile.Class].Obscured + 1
			totalObscured = totalObscured + 1
		end
	end
	
	self.Classes[self.Constants.Classes.Raid].Near = totalNear
	self.Classes[self.Constants.Classes.Raid].Obscured = totalObscured
end


function BBPlayerState.base:SetCoverage(group, label, source, slot, spellid)

	local curLabel
	local curData
	local changed = nil
	
	if group and label and source and slot then
		if not self.Coverage then
			self.Coverage = {}
		end
		
		if not self.Coverage[group] then
			self.Coverage[group] = {}
		end

		-- if: i'm covering this now
		if spellid and source == self.PlayerGUID then
			-- record the last-cast spell
			-- print("setting last-cast spell of type "..slot.." on "..group.." to "..GetSpellInfo(spellid))
			
			if not self.lastCast[group] then
				self.lastCast[group] = {}
			end
			
			--[[
			if not self.lastCast[group][slot] then
				self.lastCast[group][slot] = {}
			end
			]]
			
			if not self.lastCast[group][slot] or (self.lastCast[group][slot] ~= spellid) then
				self.lastCast[group][slot] = spellid
				changed = true
			end
		end -- if: i'm covering this now

		-- if: no coverage, provider changed, or buffslot changed
		if not self.Coverage[group][label]
		or self.Coverage[group][label].Source ~= source
		or self.Coverage[group][label].Slot ~= slot then
			-- for: each coveraged buff label/type
			for curLabel, curData in pairs(self.Coverage[group]) do
				-- if: mutually exclusive with new coverage/provider
				if curData.Slot == slot and curData.Source == source then
					self.Coverage[group][curLabel] = nil
				end -- if: mutually exclusive with new coverage
			end -- for: each coveraged buff label/type


			-- if: i was coverin this, but i'm not anymore
			if self.Coverage[group][label]
			and self.PlayerGUID ~= source
			and self.PlayerGUID == self.Coverage[group][label].Source then

				self.lastCast[group][self.Coverage[group][label].Slot] = nil
			end -- if: i was coverin this, but i'm not anymore

			self.Coverage[group][label] = {Source = source, Slot = slot}
		
			changed = true
		end		
	end
	
	return changed
end

function BBPlayerState.base:GetLastCast(group, slotName)
	local lastCast = nil
	
	if group and slotName and self.lastCast[group] then
		lastCast = self.lastCast[group][slotName]
	end
	
	return lastCast
end

function BBPlayerState.base:ResetLastCast()
	for _, className in pairs(self.Constants.Classes) do
		self.lastCast[className] = {}
	end
end

function BBPlayerState.base:CheckCoverage(group, label)
	local coverageBy = nil
	
	if self.Coverage and label then
		if self.Coverage[self.Constants.Classes.Raid] and self.Coverage[self.Constants.Classes.Raid][label] then
			coverageBy = self.Coverage[self.Constants.Classes.Raid][label].Source
		elseif group and self.Coverage[group] and self.Coverage[group][label] then
			coverageBy = self.Coverage[group][label].Source
		end
	end
	
	return coverageBy
end


function BBPlayerState.base:UpdateCoverage()
	
	local buffSlotCount = {} -- ['SLOT_NAME'] = {Labels = {MP5, AP, etc}, LabelCount, ProviderCount = #, Covered = true/false}
	-- self.Coverage: {THORNS = class, FORT = class, SHOUT = player, etc}
	local coverageChanged = true
	local currentCoverageCount = 0
	local someProvider
	local mockLabelArray = {}
	
	local tooFar = 100
	local i = 0

	-- for: each group
	for _, className in pairs(self.Constants.Classes) do
		-- if: no container
		if not self.Coverage[className] then
			self.Coverage[className] = {}
		end -- if: no container
	
		-- for: reset each label covered for current group
		for labelName, labelCoveredBy in pairs(self.Coverage[className]) do
			-- if: covered by a slot
			if self.Constants.BuffSlots[labelCoveredBy.Source] then
				-- covered by a slot;  reset, will recalculate below
				self.Coverage[className][labelName] = nil
			
			elseif nil == self:GetProfile(labelCoveredBy.Source) then
				-- covered by player, who left the party
				self.Coverage[className][labelName] = nil
			end -- if: covered by a class
		end -- for: reset each label covered for current group
	end -- for: each group
	
	-- for: build slot coverage from players
	for playerName, playerProfile in self:Iterator() do
		-- for: each buffslot of the player
		for slotName, slotSpells in pairs(playerProfile.BuffSlots) do

			-- if: first time seeing this slot
			if not buffSlotCount[slotName] then
				-- seed slot data to 0
				buffSlotCount[slotName] = {Labels = {}, Providers = {}, ProviderCount = 0, LabelCount = 0, Covered = false}
			end

			-- count player as a provider (of their current buffslot)
			buffSlotCount[slotName].ProviderCount = buffSlotCount[slotName].ProviderCount + 1
			table.insert(buffSlotCount[slotName].Providers, playerName)

			-- for: each entry in buffslot
			for currentSlotID, currentSlotSpell in pairs(slotSpells) do
				buffLabel = self.Constants:SpellInfoFromID(currentSlotID)

				-- if: spell found
				if buffLabel then
				
					-- if: old style single-type returned
					if type(buffLabel) == "string" then
						-- convert to new multi-benefit result
						mockLabelArray[1] = buffLabel
						buffLabel = mockLabelArray
					end -- if: old style single-type returned

					-- for: each type of buff this spell provides
					for _, label in ipairs(buffLabel) do
					
						if not buffSlotCount[slotName].Labels[buffLabel]
						and currentSlotSpell.Scope ~= self.Constants.Scope.Self
						and not (currentSlotSpell.MinLevel > playerProfile.Level) then
							-- seed extra label
							buffSlotCount[slotName].LabelCount = buffSlotCount[slotName].LabelCount + 1
							buffSlotCount[slotName].Labels[buffLabel] = true
						end -- if: label new to the slot (and applies to friendlies)
					end -- for: each type of buff this spell provides
				end -- if: spell found
			end -- for: each entry in buffslot
		end -- for: each buffslot of the player
	end -- for: build slot coverage from players

	-- at this point we know:
	-- how many people know each buffslot (ie: 2 paladins know BLESSINGS)
	-- the unique labels of each buffslot (ie: AP, STATS, MP5)
	-- how many unique labels are in each buffslot (ie: 3 blessings)
	
	-- while: coverage changed
	while coverageChanged and i < tooFar do
		coverageChanged = false
		
		-- for: each player
		for playerName, playerProfile in self:Iterator() do
			-- for: each buffslot of the player
			for slotName, slotSpells in pairs(playerProfile.BuffSlots) do
				
				-- for: each class
				for _, className in pairs(self.Constants.Classes) do

					-- if: slot isn't fully covered yet
					if buffSlotCount[slotName].ProviderCount < buffSlotCount[slotName].LabelCount then

						currentCoverageCount = 0
						
						-- for: each label of the slot
						for currentLabel, _ in  pairs(buffSlotCount[slotName].Labels) do
							if self.Coverage
							and self.Coverage[className]
							and self.Coverage[className][currentLabel] then
								someProvider = self.Coverage[className][currentLabel].Source
							end
							
							-- if: label is covered by a not-provider (ie: if checking BLESSINGS, discount AP by somepaladin...but count AP by SHOUTS)
							if someProvider and not listContains(buffSlotCount[slotName].Providers, someProvider) then
								-- add to covered count
								currentCoverageCount = currentCoverageCount + 1
							end -- if: label is covered
						end -- for: each label of the slot
						
						-- if: slot wasn't covered, and now is
						if (currentCoverageCount < buffSlotCount[slotName].LabelCount)
						and not ( ( buffSlotCount[slotName].ProviderCount + currentCoverageCount ) < buffSlotCount[slotName].LabelCount) then
							-- for: each Label (of the slot)
							for currentLabel, _ in pairs(buffSlotCount[slotName].Labels) do
								--  if: no entry in self.Coverage for label
								if not self.Coverage[className][currentLabel] then
									-- mark label as covered by this buffslot
									-- TODO:  double-hitting shamans!
									self.Coverage[className][currentLabel] = {Source = slotName, Slot = slotName}
									coverageChanged = true
								end --  if: no entry in buffLabelCoverage for label
							end -- for: each buffSlotCount[N].Labels in named buffslot
						end -- if: slot wasn't covered, and now is
					else
						-- for: each Label (of the slot)
						for currentLabel, _ in pairs(buffSlotCount[slotName].Labels) do
							--  if: no entry in self.Coverage for label
							if not self.Coverage[className][currentLabel] then
								-- mark label as covered by this buffslot
								-- TODO:  double-hitting shamans!
								self.Coverage[className][currentLabel] = {Source = slotName, Slot = slotName}
								coverageChanged = true
							end --  if: no entry in buffLabelCoverage for label
						end -- for: each buffSlotCount[N].Labels in named buffslot
					end -- if: slot isn't fully covered yet
				end -- for: each class
			end -- for: each buffslot of the player
		end -- for: each player
		
		i = i + 1
	end -- while: coverage changed

	if (i == tooFar) then print(L["catastrophic mistake;  coverage not completing"]) end
	
	return self.Coverage
end

function BBPlayerState.base:UpdateRoleCount()
	local target, className, classNum, role
	local highestRole, highestCount
		
	-- for: each class
	for _, className in pairs(self.Constants.Classes) do
		if not self.Classes[className] then
			 -- seed initial class data
			self.Classes[className] = {
				HeadCount = 0,
				Near = 0,
				RoleCount = {},
				DominantRole = self.Constants.Roles.None,
			}
		else
			self.Classes[className].RoleCount = {}
			self.Classes[className].DominantRole = self.Constants.Roles.None
			self.Classes[className].HeadCount = 0
		end

		-- for: each role
		for _, role in pairs(self.Constants.Roles) do
			if not self.Classes[className].RoleCount then
				self.Classes[className].RoleCount = {}
			end
			
			-- reset the count
			self.Classes[className].RoleCount[role] = 0
		end -- for: each role

	end -- for: each class
	
	-- for: each player
	for _, target in self:Iterator() do
		-- add them to the class head/role count
		if target.Role then
			self.Classes[target.Class].RoleCount[target.Role] = self.Classes[target.Class].RoleCount[target.Role] + 1
			self.Classes[target.Class].HeadCount = self.Classes[target.Class].HeadCount + 1

			-- add to the total head/role count
			self.Classes[self.Constants.Classes.Raid].RoleCount[target.Role] = self.Classes[target.Class].RoleCount[target.Role] + 1
			self.Classes[self.Constants.Classes.Raid].HeadCount = self.Classes[self.Constants.Classes.Raid].HeadCount + 1
		end
	end

	-- for: each class
	for _, className in pairs(self.Constants.Classes) do

		-- if: only one person from the class
		if self.Classes[className].HeadCount == 1 then
			-- use their role as the dominant role
			highestCount = 0
		else
			-- start new count;  to be dominant, there have to be 2 of that role
			highestCount = 1
		end
		
		-- for: each role
		for _, role in pairs(self.Constants.Roles) do
			-- if: more of this role than the last dominant role
			if self.Classes[className].RoleCount[role] > highestCount then
				
				-- Assign as new dominant role:  preserve head-count
				self.Classes[className].DominantRole = role
				highestCount = self.Classes[className].RoleCount[role]
			end -- if: more of this role than the last dominant role
		end -- for: each role
		
	end -- for: each class
end

function BBPlayerState.base:Reset()
	self.PlayerGUID = nil
	self.Players = {}
	self.PlayerCount = 0
	self.StalePlayerGUID = nil
	self.ProfiledBuffProviders = nil
	self.lastCast = {}
	
	for _, className in pairs(self.Constants.Classes) do
		self.lastCast[className] = {}
	end

end

function BBPlayerState.base:IsInitialized(iDontCareIfImStale)
	local me = self:GetProfile(self:MyGUID())
	
	return me and (iDontCareIfImStale or (not me.Stale))
end

function BBPlayerState.base:AddBuffSlot(unitGUID, slotName, slotTemplate)

	if self.Players[unitGUID] then
		self.Players[unitGUID].BuffSlots[slotName] = slotTemplate
	end

end

function BBPlayerState.base:PromoteTankRole(unitGUID)

	if self.Players[unitGUID]
	and self.Players[unitGUID].Role ~= self.Constants.Roles.Tank then
		MyDebugPrint("promoting role of "..self.Players[unitGUID].Name.." to "..tostring(self.Constants.Roles.Tank))
		self.Players[unitGUID].OldRole = self.Players[unitGUID].Role
		self.Players[unitGUID].Role = self.Constants.Roles.Tank
	end

end

function BBPlayerState.base:DemoteTankRole(unitGUID)

	if self.Players[unitGUID]
	and self.Players[unitGUID].Role == self.Constants.Roles.Tank then
		MyDebugPrint("demoting role of "..self.Players[unitGUID].Name.." to "..tostring(self.Players[unitGUID].OldRole))
		self.Players[unitGUID].Role = self.Players[unitGUID].OldRole or self.Constants.Roles.Tank
	end

end

function BBPlayerState.base:GetPlayerBuffStrength(casterGUID, buffLabel)
	-- activeBuff: caster, spellid, expiration
	local buffStrength = self.Constants.Buffs.None
	local staleData
	local casterProfile

	if casterGUID then
		-- lookup Caster index
		casterProfile = self.Players[casterGUID]
		
		-- if: have caster data
		if casterProfile then
			if casterProfile.CastableBuffs[buffLabel] then
				buffStrength = casterProfile.CastableBuffs[buffLabel]
				staleData = casterProfile.Stale
			end
		end -- if: have caster data
	end
	
	return buffStrength, staleData
end

function BBPlayerState.base:GetCount()

	return self.PlayerCount
end

function BBPlayerState.base:NextStalePlayer()
	local iChecked = 0
	local currentGUID, currentProfile
	local lastStalePlayer = nil

	-- start at last marked stale player (or nil)
	currentGUID = self.StalePlayerGUID

	-- if: player left party
	if currentGUID and not self.Players[currentGUID] then
		-- start somewhere else
		currentGUID = nil
	end -- if: player left party
	
	-- while: haven't traversed entire player list
	while not (iChecked > self.PlayerCount) do

		-- advance to next
		currentGUID, currentProfile = next(self.Players, currentGUID)
		
		-- advance past end of list
		if nil == currentGUID then
			currentGUID, currentProfile = next(self.Players, nil)
		end

		-- if: someone to check, and they are stale
		if currentProfile and currentProfile.Stale then
			
			-- we found the "next stale player"
			self.StalePlayerGUID = currentGUID
			break
		end
		
		iChecked = iChecked + 1
	end
	
	return self.StalePlayerGUID
end

function BBPlayerState.base:UpdateBuff(targetGUID, casterGUID, spellid, expires)
	local targetProfile
	local buffLabel
	local buffLabels = self.Constants:SpellInfoFromID(spellid)
	local activeChanged = nil
	local mockLabelArray = {}

	if targetGUID and buffLabels then
		targetProfile = self.Players[targetGUID]
		
		if targetProfile then
			
			-- if: old style single-type returned
			if type(buffLabels) == "string" then
				-- convert to new multi-benefit result
				mockLabelArray[1] = buffLabels
				buffLabels = mockLabelArray
			end -- if: old style single-type returned

			-- for: each benefit this spell provides
			for _, buffLabel in pairs(buffLabels) do
			
				if not targetProfile.ActiveBuffs[buffLabel] then
					targetProfile.ActiveBuffs[buffLabel] = {
						CasterGUID = casterGUID,
						Spellid = spellid,
						Expires = expires,
						Strength = self:GetPlayerBuffStrength(casterGUID, buffLabel),
						activeChanged = true,
					}

					if self:GetProfile(casterGUID) then
						targetProfile.ActiveBuffs[buffLabel].StrengthStale = self:GetAttribute(casterGUID, 'Stale')
					end

					activeChanged = true

				-- else: already cached, check for updates
				else
					-- record if old state is "expired", and insert new expiration (for comparator)
					hasOldExpired = BuffBroker:HasExpired(targetProfile.ActiveBuffs[buffLabel], self:MyGUID())
					oldExpires = targetProfile.ActiveBuffs[buffLabel].Expires
					targetProfile.ActiveBuffs[buffLabel].Expires = expires

					if casterGUID ~= targetProfile.ActiveBuffs[buffLabel].CasterGUID
					or spellid ~= targetProfile.ActiveBuffs[buffLabel].Spellid
					or hasOldExpired ~= BuffBroker:HasExpired(targetProfile.ActiveBuffs[buffLabel], self:MyGUID()) then
						-- genuine new state!  finish updating aura info
						targetProfile.ActiveBuffs[buffLabel].Spellid = spellid
						targetProfile.ActiveBuffs[buffLabel].CasterGUID = casterGUID

						activeChanged = true
					else
						-- revert aura info to prior state
						targetProfile.ActiveBuffs[buffLabel].Expires = oldExpires
					end
				end
			end -- for: each benefit this spell provides
		end
	else
		-- print("target: "..tostring(targetGUID)..", spellid: "..tostring(spellid)..", label: "..tostring(buffLabel))
	end
	
	return activeChanged
end

function BBPlayerState.base:GroupHeadCount(groupName)
	local count = 0
	
	return count
end

function BBPlayerState.base:GroupNearCount(groupName)
	local count = 0
	
	if groupName and self.Classes[groupName] then
		count = self.Classes[groupName].Near
	end
	
	return count
end

function BBPlayerState.base:GroupHeadCount(groupName)
	local count = 0
	
	if groupName and self.Classes[groupName] then
		count = self.Classes[groupName].HeadCount
	end
	
	return count
end

function BBPlayerState.base:GroupObscuredCount(groupName)
	local count = 0
	
	if groupName and self.Classes[groupName] then
		count = self.Classes[groupName].Obscured
	end

	return count
end

function BBPlayerState.base:GroupDominantRole(groupName)
	local role = self.Constants.Roles.Unknown
	
	if groupName and self.Classes[groupName] then
		role = self.Classes[groupName].DominantRole
	end

	return role
end

function BBPlayerState.classic:RefreshPlayers()
	-- ensure cached names match current party/raid
	local i, iTooFar = 0, 0
	local partyMembers,isRaid
	local prefix, numMembers
	local targetGUID, targetProfile, petGUID, petProfile
	local oldTargetIndex
	local iterGUID, iterNext
	local rosterChanged = nil
	local labelName
	local spellID
	
	targetGUID = UnitGUID('player')
	-- if: never seen before

	if nil == self.Players[targetGUID] then
	
		-- if: player not yet cached in party
		targetGUID, targetProfile = self:ProfileUnit('player')
		petGUID, petProfile = self:ProfileUnit('playerpet')

		-- if: able to profile
		if targetProfile then

			-- if: new to the cache
			if nil == self.Players[targetGUID] then
			
				self.Players[targetGUID] = targetProfile
				self.PlayerCount = self.PlayerCount + 1
				self.PlayerGUID = targetGUID
				
				-- parse auras on unit
				-- self:ScanActive(targetGUID)

				-- if: target has pet
				if petGUID and not self.Players[petGUID] then
					-- Add pet, scan buffs, mark for inspection
					self.Players[targetGUID].PetGUID = petGUID
					self.Players[petGUID] = petProfile
					self.PlayerCount = self.PlayerCount + 1

					-- parse auras on unit
					-- self:ScanActive(petGUID)
				end -- if: target has pet

				rosterChanged = true
			end -- if: new to the cache
		end -- if: able to profile
	else
		-- check names
		targetGUID = UnitGUID('player')
		petGUID = UnitGUID('playerpet')

		-- update name, if it changed
		if self.Players[targetGUID]
		and self.Players[targetGUID].Name ~= UnitName('player') then

			self.Players[targetGUID].Name = UnitName('player')
		end -- update name, if it changed

		-- update pet name, if it changed
		if self.Players[petGUID]
		and self.Players[petGUID].Name ~= UnitName('playerpet') then

			self.Players[petGUID].Name = UnitName('playerpet')
		end -- update name, if it changed
		
	
	end -- if: never seen before

	--[[
	-- if: in group, not inspected, and not waiting for inspection
	if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
		table.insert(self.StalePlayers, targetGUID)
	end -- if: in group, not inspected, and not waiting for inspection
	]]
	
	-- Build the Bufflist.Players as 'potential buffers';  it will
	-- act as an L'inspect' list for a later mechanism
	numMembers = self.Constants:GetNumGroupMembers()
	prefix = self.Constants:GetGroupPrefix()
	
	-- for: each REAL party member
	for i=1,numMembers do
		
		targetGUID = UnitGUID(prefix..i)

		-- if: never seen before
		if not self.Players[targetGUID] then
		
			-- perform a shallow-profile (name, class, ...)
			targetGUID, targetProfile = self:ProfileUnit(prefix..i)
			petGUID, petProfile = self:ProfileUnit(prefix..'pet'..i)
			
			-- if: able to profile
			if targetProfile then
				
				-- if: new to cache
				if not self.Players[targetGUID] then
					-- Add player, scan buffs, mark for inspection
					self.Players[targetGUID] = targetProfile
					self.PlayerCount = self.PlayerCount + 1

					-- parse auras on unit
					-- self:ScanActive(targetGUID)

					-- if: target has pet
					if petGUID and not self.Players[petGUID] then
						-- Add pet, scan buffs, mark for inspection
						self.Players[targetGUID].PetGUID = petGUID
						self.Players[petGUID] = petProfile
						self.PlayerCount = self.PlayerCount + 1

						-- parse auras on unit
						-- self:ScanActive(petGUID)
					end -- if: target has pet
					
					rosterChanged = true
				end -- if: new to the cache
			end -- if: able to profile
		else
			-- check names
			targetGUID = UnitGUID(prefix..i)
			petGUID = UnitGUID(prefix..i..'pet')
			-- update name, if it changed
			if self.Players[targetGUID]
			and self.Players[targetGUID].Name ~= UnitName(prefix..i) then
				self.Players[targetGUID].Name = UnitName(prefix..i)
			end -- update name, if it changed

			-- update pet name, if it changed
			if self.Players[petGUID]
			and self.Players[petGUID].Name ~= UnitName(prefix..i..'pet') then
				self.Players[petGUID].Name = UnitName(prefix..i..'pet')
			end -- update name, if it changed
			
			-- check visibility (players only)
			if not UnitIsVisible(self.Players[targetGUID].Name) and self.Players[targetGUID].Type == self.Constants.Types.Player then
				-- outside area of interest/events:  mark for full scan when near us
				self.Players[targetGUID].Stale = true
			end -- check visibility
		end -- if: never seen before

		--[[
		-- if: in group, not inspected, and not waiting for inspection
		if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
			-- mark for talent scan
			table.insert(self.StalePlayers, targetGUID)
		end -- mark for talent scan
		]]
		
	end -- for: each REAL party member

	-- remove players who left
	iterGUID, currentProfile = next(self.Players, nil)
	
	-- for: each cached party member
	while iterGUID and not (iTooFar > self.Constants.MaxPlayers) do
		iterNext, nextProfile = next(self.Players, iterGUID)
		
		-- if: not in raid/party
		if currentProfile.Type == self.Constants.Types.Player
		and not UnitInParty(currentProfile.Name)
		and not UnitInRaid(currentProfile.Name) then
			-- stop tracking unit
			MyDebugPrint('removing %s; left party/raid', currentProfile.Name)
			if self.Players[iterGUID].PetGUID and self.Players[self.Players[iterGUID].PetGUID] then
				self.Players[self.Players[iterGUID].PetGUID] = nil
				self.PlayerCount = self.PlayerCount - 1
			end
			
			self.Players[iterGUID] = nil
			self.PlayerCount = self.PlayerCount - 1

			rosterChanged = true
		end -- if: not in raid/party
		
		-- next entry
		iterGUID = iterNext
		currentProfile = nextProfile
		
		iTooFar = iTooFar + 1
	end -- for: each cached party member
	
	return rosterChanged
end

function BBPlayerState.classic:ParseGUID(unitGUID)
	local typeID
	local unitID
	
	if unitGUID and string.len(unitGUID) > 15 then
		typeID = tonumber(string.sub(unitGUID, 5, 5)) % 8
		
		unitID = string.sub(unitGUID, 6, 12)
	end
	
	return typeID, unitID
end

function BBPlayerState.cataclysm:ParseGUID(unitGUID)
	local typeID
	local unitID
	
	if unitGUID and string.len(unitGUID) > 15 then
		typeID = tonumber(string.sub(unitGUID, 5, 5)) % 8
		
		unitID = string.sub(unitGUID, 6, 12)
	end
	
	return typeID, unitID
end

function BBPlayerState.classic:PetChanged(owner)
	local ownersGUID = UnitGUID(owner)
	local ownerProfile = self:GetProfile(ownersGUID)
	local petType
	local newPetID
	local petGUID
	local lastPetGUID
	local aurasChanged

	-- if: target is of interest to us
	if ownerProfile then
		petGUID = UnitGUID(targetName..'pet')
		petType, newPetID = self:ParseGUID(petGUID)
		
		-- if: player has a permanent pet out meow
		if petGUID and petType == self.Constants.Types.CombatPet then
			-- disect GUID:  determine pet's unique ID
			lastPetGUID = self:GetAttribute(ownersGUID, 'PetGUID')
			if lastPetGUID then
				_, lastPetID = self:ParseGUID(lastPetGUID)
			end

			-- if: different pet
			if newPetID and newPetID ~= lastPetID then
				aurasChanged = true
				
				--Remove last pet
				if self:GetAttribute(ownersGUID, 'PetGUID')
				and self:GetProfile(self:GetAttribute(ownersGUID, 'PetGUID')) then
					self:RemoveProfile(self:GetAttribute(ownersGUID, 'PetGUID'))
				end

				--Add new pet
				petGUID, petProfile = self:ProfileUnit(targetName..'pet')
				
				-- if: scanned pet successfully
				if petGUID and petProfile and not self:GetProfile(petGUID) then
					-- Add pet, scan buffs, mark for inspection
					self:SetAttribute(ownersGUID, 'PetGUID', petGUID)
					self:AddProfile(petGUID, petProfile)

					-- parse auras on unit
					self:ScanActive(petGUID)
					
					-- New Suggestions
					--self:RegenerateSuggestionDependencies()
					--self:AssignNextSuggestion()
				end -- if: scanned pet successfully
			elseif self:GetProfile(petGUID) and self:GetAttribute(petGUID, 'Name') ~= UnitName(targetName..'pet') then
				self:SetAttribute(petGUID, 'Name', UnitName(targetName..'pet'))
			end
		end -- if: player summoned a new pet, or changed pets

	end -- if: target is of interest to us
	
	return aurasChanged
end

function BBPlayerState.base:WantsBuff(role, buffLabel)
	local desirability = 0
	local label
	
	-- if: input data validates
	if role
	and buffLabel
	and self.Constants.BuffPriorities[role] then
		
		-- for: each benefit/buff that will be provided
		for _, label in ipairs(buffLabel) do
			
			-- if: role cares about the current type of buff more than the other benefits
			if self.Constants.BuffPriorities[role][buffLabel]
			and self.Constants.BuffPriorities[role][buffLabel] > desirability then
				desirability = self.Constants.BuffPriorities[role][buffLabel]
			end -- if: role cares about the type of buff more than the other benefits
		end -- for: each benefit/buff that will be provided
	end -- if: input data validates
	
	return desirability
end

function BBPlayerState.base:MatchByLabel(labelLeft, labelRight)
	local matches = nil
	
	if type(labelLeft) == "string" then
	
		if type(labelRight) == "string" then
			matches = labelLeft == labelRight
		elseif type(labelRight) == "table" then
			matches = listContains(labelRight, labelLeft)
		end
	
	elseif type(labelLeft) == "table" then

		if type(labelRight) == "string" then
			matches = listContains(labelLeft, labelRight)
		elseif type(labelRight) == "table" then
			matches = labelRight == labelLeft
		end
	
	end
	
	return matches
end

function BBPlayerState.base:MatchBySpell(spellid, labels)
	local matches = nil
	
	return matches
end

function BBPlayerState.classic:ProfileUnit(toProfile)
	local targetPlayer = nil
	local unknownSpells = {}
	local theirClass
	local theirFamily
	local theirType
	local theirLevel = UnitLevel(toProfile)
	local theirName = UnitName(toProfile)
	local typeID
	local theirGUID = UnitGUID(toProfile)
	
	if theirGUID then
		--typeID = BuffBroker:ParseGUID(theirGUID)
		
		_, theirClass = UnitClass(toProfile)
		theirFamily = UnitCreatureFamily(toProfile)
		
		-- if: online
		if UnitIsConnected(toProfile)
		and theirLevel > 0
		and theirName
		and theirClass
		and UnitIsVisible(theirName) then

		-- TODO:  Check for secondary role on zone-change, based on
		-- isTank, isHeal, isDPS = UnitGroupRolesAssigned(unitid)

			if (typeID == self.Constants.Types.CombatPet or typeID == self.Constants.Types.Player) then
				MyDebugPrint("profiling unit %s", toProfile)
				targetPlayer = {
					Name = theirName,
					Class = theirClass,
					Type = typeID,
					Level = theirLevel,
					Role = self.Constants.Roles.Unknown,
					Inspected = nil,
					BuffSlots = {},
					CastableBuffs = {},
					ActiveBuffs = {},
					Near = true,
					LOS = true,
					Stale = true,
					ActiveTalentGroup = self.Constants.TalentGroup.Unknown,
				}
				
				-- for: seeding each type of castable buff
				for labelName, _ in pairs(self.Constants.DownRankLookup) do
					targetPlayer.CastableBuffs[labelName] = self.Constants.Buffs.None
				end -- for: seeding each type of castable buff

				-- if: pet or player
				if typeID == self.Constants.Types.Player then -- else: player

					if theirClass == self.Constants.Classes.Mage
					or theirClass == self.Constants.Classes.Priest
					or theirClass == self.Constants.Classes.Warlock
					or theirClass == self.Constants.Classes.Shaman
					or theirClass == self.Constants.Classes.Paladin then
						-- assign basic mana-using profile
						targetPlayer.Role = self.Constants.Roles.ManaUser
					else
						-- assign basic non-mana-using profile
						targetPlayer.Role = self.Constants.Roles.NoMana
					end
					
					-- determine spec-independent roles and buffs
					if theirClass == self.Constants.Classes.Mage then
						targetPlayer.Role = self.Constants.Roles.Caster

						targetPlayer.CastableBuffs["INTELLECT"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["BRILLIANCE"] = self.Constants.BuffSlots["BRILLIANCE"]
						targetPlayer.CastableBuffs["MAGE_ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["MAGE_ARMOR"] = self.Constants.BuffSlots["MAGE_ARMOR"]
					elseif theirClass == self.Constants.Classes.Priest then
						targetPlayer.CastableBuffs["STAMINA"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["FORTITUDE"] = self.Constants.BuffSlots["FORTITUDE"]
						targetPlayer.CastableBuffs["SPIRIT"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["SPIRIT"] = self.Constants.BuffSlots["SPIRIT"]
						targetPlayer.CastableBuffs["PRIEST_INNER"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["PRIEST_INNER"] = self.Constants.BuffSlots["PRIEST_INNER"]
						targetPlayer.CastableBuffs["PRIEST_FORM"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["PRIEST_FORM"] = self.Constants.BuffSlots["PRIEST_FORM"]
						targetPlayer.CastableBuffs["SHADOW_RESIST"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["PRIEST_PROTECTION"] = self.Constants.BuffSlots["PRIEST_PROTECTION"]
					elseif theirClass == self.Constants.Classes.Druid then
						targetPlayer.CastableBuffs["WILD"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["WILD"] = self.Constants.BuffSlots["WILD"]
						targetPlayer.CastableBuffs["THORNS"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["THORNS"] = self.Constants.BuffSlots["THORNS"]
						targetPlayer.CastableBuffs["OWL_FORM"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["TREE_FORM"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["SHAPESHIFT"] = self.Constants.BuffSlots["SHAPESHIFT"]
					elseif theirClass == self.Constants.Classes.Warlock then
						if targetPlayer.Level < 62 then
							-- doesn't have fel armor yet
							targetPlayer.Role = self.Constants.Roles.Healer
						else
							targetPlayer.Role = self.Constants.Roles.Caster
						end

						targetPlayer.CastableBuffs["WARLOCK_ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["WARLOCK_ARMOR"] = self.Constants.BuffSlots["WARLOCK_ARMOR"]
					elseif theirClass == self.Constants.Classes.Rogue then
						targetPlayer.Role = self.Constants.Roles.PureMelee
					elseif theirClass == self.Constants.Classes.Deathknight then
						targetPlayer.Role = self.Constants.Roles.PureMelee
						targetPlayer.CastableBuffs["STRENGTH_AGILITY"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["HORNS"] = self.Constants.BuffSlots["HORNS"]
					elseif theirClass == self.Constants.Classes.Hunter then
						if targetPlayer.Level < 20 then
							-- doesn't have aspect of the viper yet
							targetPlayer.Role = self.Constants.Roles.MeleeMana_Low
						else
							targetPlayer.Role = self.Constants.Roles.MeleeMana
						end
						
					elseif theirClass == self.Constants.Classes.Shaman then
						targetPlayer.CastableBuffs["MP5"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["HP5"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["STRENGTH_AGILITY"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["SOLO_FIRE_TOTEM"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["FLAT_SPELL"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["MELEE_HASTE"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["SPELL_HASTE"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["WATER_TOTEMS"] = self.Constants.BuffSlots["WATER_TOTEMS"]
						targetPlayer.BuffSlots["EARTH_TOTEMS"] = self.Constants.BuffSlots["EARTH_TOTEMS"]
						targetPlayer.BuffSlots["FIRE_TOTEMS"] = self.Constants.BuffSlots["FIRE_TOTEMS_BASIC"]
						targetPlayer.BuffSlots["AIR_TOTEMS"] = self.Constants.BuffSlots["AIR_TOTEMS"]
					elseif theirClass == self.Constants.Classes.Warrior then
						targetPlayer.Role = self.Constants.Roles.PureMelee
						targetPlayer.CastableBuffs["AP"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["HP"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["SHOUTS"] = self.Constants.BuffSlots["SHOUTS"]
					elseif theirClass == self.Constants.Classes.Paladin then
						targetPlayer.CastableBuffs["AP"] = self.Constants.Buffs.BasicLong
						targetPlayer.CastableBuffs["STATS"] = self.Constants.Buffs.BasicLong
						targetPlayer.CastableBuffs["MP5"] = self.Constants.Buffs.BasicLong
						targetPlayer.CastableBuffs["PALADIN_SEAL"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["RIGHTEOUS_FURY"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["REFLECTION"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["NO_PUSHBACK"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["RESISTANCE"] = self.Constants.Buffs.Basic
						
						targetPlayer.BuffSlots["BLESSINGS"] = self.Constants.BuffSlots["BLESSINGS_BASIC"]
						targetPlayer.BuffSlots["SEALS"] = self.Constants.BuffSlots["SEALS"]
						targetPlayer.BuffSlots["RIGHTEOUS_FURY"] = self.Constants.BuffSlots["RIGHTEOUS_FURY"]
						targetPlayer.BuffSlots["AURAS"] = self.Constants.BuffSlots["AURAS"]						
					end
				elseif typeID == self.Constants.Types.CombatPet then -- is permanentpet
					targetPlayer.Stale = false
					targetPlayer.Inspected = true
					
					if targetPlayer.Class == self.Constants.Classes.Paladin then
						targetPlayer.Role = self.Constants.Roles.MeleeMana
					elseif targetPlayer.Class == self.Constants.Classes.Warrior then
						targetPlayer.Role = self.Constants.Roles.PureMelee
					elseif targetPlayer.Class == self.Constants.Classes.Mage then
						targetPlayer.Role = self.Constants.Roles.Caster
					end

					if UnitCreatureType(toProfile) == L["Demon"] then
						if UnitCreatureFamily(toProfile) == L["Voidwalker"] then
							targetPlayer.Class = self.Constants.Classes.Warrior
						elseif UnitCreatureFamily(toProfile) == L["Felguard"] then
							targetPlayer.Class = self.Constants.Classes.Warrior
						elseif UnitCreatureFamily(toProfile) == L["Imp"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						elseif UnitCreatureFamily(toProfile) == L["Felhunter"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						elseif UnitCreatureFamily(toProfile) == L["Succubus"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						end
					elseif UnitCreatureType(toProfile) == L["Beast"] then
						targetPlayer.Class = self.Constants.Classes.Warrior
					end
					-- NOTE:  BuffSlots will be auto-filled in if/when they're found as auras
					-- i.e. for Imp, Felguard, or felhunter, beasts ...
					
				end -- if: check if pet or player
			elseif typeID ~= self.Constants.Types.NPC
			and typeID ~= self.Constants.Types.Vehicle then -- is permanentpet
				-- TODO:  Handle NPC pets made permanent (ghoul via talent, water elemental via glyph)
				BuffBroker:SetFailCode("buffbroker error: found party member who isn't a player, pet, or vehicle! please notify author of this player/guid: "..toProfile.." - "..UnitGUID(toProfile))
			end -- if: controlled, permanent GUID
		end -- if: online
	end -- if: has a GUID
	
	return UnitGUID(toProfile), targetPlayer

end

-- Cataclysm - changed Functions

function BBPlayerState.base:PetChanged(owner)
	local ownersGUID = UnitGUID(owner)
	local petGUID = UnitGUID(owner..'pet')
	local ownersProfile = self:GetProfile(ownersGUID)
	local petProvidedBuff
	local petFamily
	local spellLabel
	local spellId
	local spellLabel
	local aurasChanged = true
	
	-- if: target has pet, and is of interest to us
	if petGUID and ownersProfile then
		petFamily = UnitCreatureFamily(owner..'pet')

		if (not self.Players[ownersGUID].ActivePet) or (petFamily ~= self.Players[ownersGUID].ActivePet) then
			-- remove buffs provided by prior pet (skip if no prior pet, or useless pet)
			spellId = self.Constants.PetBuff[self.Players[ownersGUID].ActivePet]
			
			if spellId and self.Constants.BuffSlots['PET'][spellId] then
				for _, spellLabel in pairs(self.Constants.BuffSlots['PET'][spellId].Types) do
					ownersProfile.CastableBuffs[spellLabel] = nil
					aurasChanged = true
				end
			end
			
			-- set new/current pet
			self.Players[ownersGUID].ActivePet = petFamily
			
			-- specify buffs provided by current pet
			spellId = self.Constants.PetBuff[petFamily]
			
			if spellId and self.Constants.BuffSlots['PET'][spellId] then
				for _, spellLabel in pairs(self.Constants.BuffSlots['PET'][spellId].Types) do
					ownersProfile.CastableBuffs[spellLabel] = self.Constants.BuffSlots['PET'][spellId].Score
					aurasChanged = true
				end
			end
		end
	end
	
	return aurasChanged
end

--[[ Duplicate!?
function BBPlayerState.classic:RefreshPlayers()
	-- ensure cached names match current party/raid
	local i, iTooFar = 0, 0
	local partyMembers,isRaid
	local prefix, numMembers
	local targetGUID, targetProfile, petProfile
	local oldTargetIndex
	local iterGUID, iterNext
	local rosterChanged = nil
	local labelName
	local spellID

	-- get your own GUID	
	targetGUID = UnitGUID('player')

	-- if: never seen self before
	if nil == self.Players[targetGUID] then
	
		-- player not yet cached in party!
		targetGUID, targetProfile = self:ProfileUnit('player')

		-- if: able to profile
		if targetProfile then

			-- if: new to the cache
			if nil == self.Players[targetGUID] then
			
				self.Players[targetGUID] = targetProfile
				self.PlayerCount = self.PlayerCount + 1
				self.PlayerGUID = targetGUID
				self:PetChanged('player')

				rosterChanged = true
			end -- if: new to the cache
		end -- if: able to profile
	else
		-- check names
		targetGUID = UnitGUID('player')

		-- update name, if it changed
		if self.Players[targetGUID]
		and self.Players[targetGUID].Name ~= UnitName('player') then

			self.Players[targetGUID].Name = UnitName('player')
		end -- update name, if it changed
	end -- if: never seen before

	-- Build the Bufflist.Players as 'potential buffers';  it will
	-- act as an L'inspect' list for a later mechanism
	numMembers = self.Constants:GetNumGroupMembers()
	prefix = self.Constants:GetGroupPrefix()
	
	-- for: each REAL party member
	for i=1,numMembers do
		
		targetGUID = UnitGUID(prefix..i)

		-- if: never seen before
		if not self.Players[targetGUID] then
		
			-- perform a shallow-profile (name, class, ...)
			targetGUID, targetProfile = self:ProfileUnit(prefix..i)
			
			-- if: able to profile
			if targetProfile then
				
				-- if: new to cache
				if not self.Players[targetGUID] then
					-- Add player, scan buffs, mark for inspection
					self.Players[targetGUID] = targetProfile
					self.PlayerCount = self.PlayerCount + 1
					self:PetChanged(prefix..i)
					
					rosterChanged = true
				end -- if: new to the cache
			end -- if: able to profile
		else
			-- check names
			targetGUID = UnitGUID(prefix..i)
			-- update name, if it changed
			if self.Players[targetGUID]
			and self.Players[targetGUID].Name ~= UnitName(prefix..i) then
				self.Players[targetGUID].Name = UnitName(prefix..i)
			end -- update name, if it changed
			
			-- check visibility (players only)
			if not UnitIsVisible(self.Players[targetGUID].Name) and self.Players[targetGUID].Type == self.Constants.Types.Player then
				-- outside area of interest/events:  mark for full scan when near us
				self.Players[targetGUID].Stale = true
			end -- check visibility
		end -- if: never seen before

	end -- for: each REAL party member

	-- remove players who left
	iterGUID, currentProfile = next(self.Players, nil)
	
	-- for: each cached party member
	while iterGUID and not (iTooFar > self.Constants.MaxPlayers) do
		iterNext, nextProfile = next(self.Players, iterGUID)
		
		-- if: not in raid/party
		if currentProfile.Type == self.Constants.Types.Player
		and not UnitInParty(currentProfile.Name)
		and not UnitInRaid(currentProfile.Name) then
			-- stop tracking unit
			MyDebugPrint('removing %s; left party/raid', currentProfile.Name)
			
			self.Players[iterGUID] = nil
			self.PlayerCount = self.PlayerCount - 1

			rosterChanged = true
		end -- if: not in raid/party
		
		-- next entry
		iterGUID = iterNext
		currentProfile = nextProfile
		
		iTooFar = iTooFar + 1
	end -- for: each cached party member
	
	return rosterChanged
end
]]

function BBPlayerState.cataclysm:RefreshPlayers()
	-- ensure cached names match current party/raid
	local i, iTooFar = 0, 0
	local partyMembers,isRaid
	local prefix, numMembers
	local targetGUID, targetProfile, petProfile
	local oldTargetIndex
	local iterGUID, iterNext
	local rosterChanged = nil
	local labelName
	local spellID

	-- get your own GUID	
	targetGUID = UnitGUID('player')

	-- if: never seen self before
	if nil == self.Players[targetGUID] then
	
		-- player not yet cached in party!
		targetGUID, targetProfile = self:ProfileUnit('player')

		-- if: able to profile
		if targetProfile then

			-- if: new to the cache
			if nil == self.Players[targetGUID] then
			
				self.Players[targetGUID] = targetProfile
				self.PlayerCount = self.PlayerCount + 1
				self.PlayerGUID = targetGUID
				self:PetChanged('player')

				rosterChanged = true
			end -- if: new to the cache
		end -- if: able to profile
	else
		-- check names
		targetGUID = UnitGUID('player')

		-- update name, if it changed
		if self.Players[targetGUID]
		and self.Players[targetGUID].Name ~= UnitName('player') then

			self.Players[targetGUID].Name = UnitName('player')
		end -- update name, if it changed
	end -- if: never seen before

	--[[
	-- if: in group, not inspected, and not waiting for inspection
	if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
		table.insert(self.StalePlayers, targetGUID)
	end -- if: in group, not inspected, and not waiting for inspection
	]]
	
	-- Build the Bufflist.Players as 'potential buffers';  it will
	-- act as an L'inspect' list for a later mechanism
	numMembers = self.Constants:GetNumGroupMembers()
	prefix = self.Constants:GetGroupPrefix()
	
	-- for: each REAL party member
	for i=1,numMembers do
		
		targetGUID = UnitGUID(prefix..i)

		-- if: never seen before
		if not self.Players[targetGUID] then
		
			-- perform a shallow-profile (name, class, ...)
			targetGUID, targetProfile = self:ProfileUnit(prefix..i)
			
			-- if: able to profile
			if targetProfile then
				
				-- if: new to cache
				if not self.Players[targetGUID] then
					-- Add player, scan buffs, mark for inspection
					self.Players[targetGUID] = targetProfile
					self.PlayerCount = self.PlayerCount + 1
					self:PetChanged(prefix..i)
					
					rosterChanged = true
				end -- if: new to the cache
			end -- if: able to profile
		else
			-- check names
			targetGUID = UnitGUID(prefix..i)
			-- update name, if it changed
			if self.Players[targetGUID]
			and self.Players[targetGUID].Name ~= UnitName(prefix..i) then
				self.Players[targetGUID].Name = UnitName(prefix..i)
			end -- update name, if it changed
			
			-- check visibility (players only)
			if not UnitIsVisible(self.Players[targetGUID].Name) and self.Players[targetGUID].Type == self.Constants.Types.Player then
				-- outside area of interest/events:  mark for full scan when near us
				self.Players[targetGUID].Stale = true
			end -- check visibility
		end -- if: never seen before

		--[[
		-- if: in group, not inspected, and not waiting for inspection
		if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
			-- mark for talent scan
			table.insert(self.StalePlayers, targetGUID)
		end -- mark for talent scan
		]]
		
	end -- for: each REAL party member

	-- remove players who left
	iterGUID, currentProfile = next(self.Players, nil)
	
	-- for: each cached party member
	while iterGUID and not (iTooFar > self.Constants.MaxPlayers) do
		iterNext, nextProfile = next(self.Players, iterGUID)
		
		-- if: not in raid/party
		if currentProfile.Type == self.Constants.Types.Player
		and not UnitInParty(currentProfile.Name)
		and not UnitInRaid(currentProfile.Name) then
			-- stop tracking unit
			MyDebugPrint('removing %s; left party/raid', currentProfile.Name)
			
			self.Players[iterGUID] = nil
			self.PlayerCount = self.PlayerCount - 1

			rosterChanged = true
		end -- if: not in raid/party
		
		-- next entry
		iterGUID = iterNext
		currentProfile = nextProfile
		
		iTooFar = iTooFar + 1
	end -- for: each cached party member
	
	return rosterChanged
end

function BBPlayerState.cataclysm:ProfileUnit(toProfile)
	local targetPlayer = nil
	local unknownSpells = {}
	local theirClass
	local theirFamily
	local theirType
	local theirLevel = UnitLevel(toProfile)
	local theirName = UnitName(toProfile)
	local typeID
	local theirGUID = UnitGUID(toProfile)
	
	MyDebugPrint("THN: profiling unit "..tostring(toProfile)..", "..theirName..", guid "..tostring(theirGUID))
	if theirGUID then
		typeID = self:ParseGUID(theirGUID)

		_, theirClass = UnitClass(toProfile)
		theirFamily = UnitCreatureFamily(toProfile)
		
		-- if: online
		if UnitIsConnected(toProfile)
		and theirLevel > 0
		and theirName
		and theirClass
		and UnitIsVisible(theirName) then

		-- TODO:  Check for secondary role on zone-change, based on
		-- isTank, isHeal, isDPS = UnitGroupRolesAssigned(unitid)

			--if (typeID == self.Constants.Types.CombatPet or typeID == self.Constants.Types.Player) then
			if typeID == self.Constants.Types.Player then
				MyDebugPrint("profiling unit %s", toProfile)
				targetPlayer = {
					Name = theirName,
					Class = theirClass,
					Type = typeID,
					Level = theirLevel,
					Role = self.Constants.Roles.Unknown,
					Inspected = nil,
					BuffSlots = {},
					CastableBuffs = {},
					ActiveBuffs = {},
					Near = true,
					LOS = true,
					Stale = true,
					ActiveTalentGroup = self.Constants.TalentGroup.Unknown,
				}
				
				-- for: seeding each type of castable buff
				for labelName, _ in pairs(self.Constants.DownRankLookup) do
					targetPlayer.CastableBuffs[labelName] = self.Constants.Buffs.None
				end -- for: seeding each type of castable buff

				-- if: pet or player
				if typeID == self.Constants.Types.Player then -- else: player

					if theirClass == self.Constants.Classes.Mage
					or theirClass == self.Constants.Classes.Priest
					or theirClass == self.Constants.Classes.Warlock
					or theirClass == self.Constants.Classes.Shaman
					or theirClass == self.Constants.Classes.Paladin then
						-- assign basic mana-using profile
						targetPlayer.Role = self.Constants.Roles.ManaUser
					else
						-- assign basic non-mana-using profile
						targetPlayer.Role = self.Constants.Roles.NoMana
					end
					
					-- determine spec-independent roles and buffs
					if theirClass == self.Constants.Classes.Mage then
						targetPlayer.Role = self.Constants.Roles.Caster

						targetPlayer.CastableBuffs["MANA_POOL"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["SPELL_POWER"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["MAGE_ARMOR"] = self.Constants.Buffs.Basic

						targetPlayer.BuffSlots["BRILLIANCE"] = self.Constants.BuffSlots["BRILLIANCE"]
						targetPlayer.BuffSlots["MAGE_ARMOR"] = self.Constants.BuffSlots["MAGE_ARMOR"]
					elseif theirClass == self.Constants.Classes.Priest then
						targetPlayer.CastableBuffs["STAMINA"] = self.Constants.Buffs.Basic
						--targetPlayer.CastableBuffs["SPIRIT"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["PRIEST_INNER"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["PRIEST_FORM"] = self.Constants.Buffs.Basic

						targetPlayer.BuffSlots["FORTITUDE"] = self.Constants.BuffSlots["FORTITUDE"]
						--targetPlayer.BuffSlots["SPIRIT"] = self.Constants.BuffSlots["SPIRIT"]
						targetPlayer.BuffSlots["PRIEST_INNER"] = self.Constants.BuffSlots["PRIEST_INNER"]
						targetPlayer.BuffSlots["PRIEST_FORM"] = self.Constants.BuffSlots["PRIEST_FORM"]
						targetPlayer.CastableBuffs["SHADOW_RESIST"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["PRIEST_PROTECTION"] = self.Constants.BuffSlots["PRIEST_PROTECTION"]
					elseif theirClass == self.Constants.Classes.Druid then
						targetPlayer.CastableBuffs["STATS"] = self.Constants.Buffs.Basic

						targetPlayer.BuffSlots["WILD"] = self.Constants.BuffSlots["WILD"]
						targetPlayer.CastableBuffs["OWL_FORM"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["TREE_FORM"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["SHAPESHIFT"] = self.Constants.BuffSlots["SHAPESHIFT"]
					elseif theirClass == self.Constants.Classes.Warlock then
						targetPlayer.Role = self.Constants.Roles.Caster

						targetPlayer.CastableBuffs["WARLOCK_ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["WARLOCK_ARMOR"] = self.Constants.BuffSlots["WARLOCK_ARMOR"]

						-- matching CastableBuffs will be assigned as pets are summoned/seen
						targetPlayer.BuffSlots["PET"] = self.Constants.BuffSlots["PET"]

					elseif theirClass == self.Constants.Classes.Rogue then
						targetPlayer.Role = self.Constants.Roles.PureMelee
					elseif theirClass == self.Constants.Classes.Deathknight then
						targetPlayer.Role = self.Constants.Roles.PureMelee
						targetPlayer.CastableBuffs["STRENGTH_AGILITY"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["HORNS"] = self.Constants.BuffSlots["HORNS"]
					elseif theirClass == self.Constants.Classes.Hunter then
						targetPlayer.Role = self.Constants.Roles.MeleeMana
						
						-- matching CastableBuffs will be assigned as pets are summoned/seen
						targetPlayer.BuffSlots["PET"] = self.Constants.BuffSlots["PET"]
						
					elseif theirClass == self.Constants.Classes.Shaman then
						targetPlayer.CastableBuffs["MP5"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["HP5"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["STRENGTH_AGILITY"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["SOLO_FIRE_TOTEM"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["FLAT_SPELL"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["MELEE_HASTE"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["SPELL_HASTE"] = self.Constants.Buffs.Basic
						targetPlayer.BuffSlots["WATER_TOTEMS"] = self.Constants.BuffSlots["WATER_TOTEMS"]
						targetPlayer.BuffSlots["EARTH_TOTEMS"] = self.Constants.BuffSlots["EARTH_TOTEMS"]
						targetPlayer.BuffSlots["FIRE_TOTEMS"] = self.Constants.BuffSlots["FIRE_TOTEMS"]
						targetPlayer.BuffSlots["AIR_TOTEMS"] = self.Constants.BuffSlots["AIR_TOTEMS"]
					
					elseif theirClass == self.Constants.Classes.Warrior then
						targetPlayer.Role = self.Constants.Roles.PureMelee
						targetPlayer.CastableBuffs["STRENGTH_AGILITY"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["HEALTH"] = self.Constants.Buffs.Basic

						targetPlayer.BuffSlots["SHOUTS"] = self.Constants.BuffSlots["SHOUTS"]
					
					elseif theirClass == self.Constants.Classes.Paladin then
						targetPlayer.CastableBuffs["AP"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["STATS"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["MANA_REGEN"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["PALADIN_SEAL"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["RIGHTEOUS_FURY"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["REFLECTION"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["NO_PUSHBACK"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["ARMOR"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["RESISTANCE"] = self.Constants.Buffs.Basic
						targetPlayer.CastableBuffs["MOUNT_SPEED"] = self.Constants.Buffs.Basic
						
						targetPlayer.BuffSlots["BLESSINGS"] = self.Constants.BuffSlots["BLESSINGS"]
						targetPlayer.BuffSlots["SEALS"] = self.Constants.BuffSlots["SEALS"]
						targetPlayer.BuffSlots["RIGHTEOUS_FURY"] = self.Constants.BuffSlots["RIGHTEOUS_FURY"]
						targetPlayer.BuffSlots["AURAS"] = self.Constants.BuffSlots["AURAS"]
					end
				--[[ Pets can't be "buffed" in cataclysm
				elseif typeID == self.Constants.Types.CombatPet then -- is permanentpet
					targetPlayer.Stale = false -- data is accurate
					targetPlayer.Inspected = true -- never inspect
					targetPlayer.Obscured = true -- can't be the recipient of buffs
					
					if targetPlayer.Class == self.Constants.Classes.Paladin then
						targetPlayer.Role = self.Constants.Roles.MeleeMana
					elseif targetPlayer.Class == self.Constants.Classes.Warrior then
						targetPlayer.Role = self.Constants.Roles.PureMelee
					elseif targetPlayer.Class == self.Constants.Classes.Mage then
						targetPlayer.Role = self.Constants.Roles.Caster
					end

					if UnitCreatureType(toProfile) == L["Demon"] then
						if UnitCreatureFamily(toProfile) == L["Voidwalker"] then
							targetPlayer.Class = self.Constants.Classes.Warrior
						elseif UnitCreatureFamily(toProfile) == L["Felguard"] then
							targetPlayer.Class = self.Constants.Classes.Warrior
						elseif UnitCreatureFamily(toProfile) == L["Imp"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						elseif UnitCreatureFamily(toProfile) == L["Felhunter"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						elseif UnitCreatureFamily(toProfile) == L["Succubus"] then
							targetPlayer.Class = self.Constants.Classes.Warlock
						end
					elseif UnitCreatureType(toProfile) == L["Beast"] then
						targetPlayer.Class = self.Constants.Classes.Warrior
					end
					-- NOTE:  BuffSlots will be auto-filled in if/when they're found as auras
					-- i.e. for Imp, Felguard, or talented felhunter...or beasts in cataclysm
				]]
				end -- if: check if pet or player
			elseif typeID ~= self.Constants.Types.NPC
			and typeID ~= self.Constants.Types.Vehicle then -- is permanentpet
				-- TODO:  Handle NPC pets made permanent (ghoul via talent, water elemental via glyph)
				--BuffBroker:SetFailCode("buffbroker error: found party member who isn't a player, pet, or vehicle! please notify author of this player/guid: "..toProfile.." - "..UnitGUID(toProfile))
			end -- if: controlled, permanent GUID
		end -- if: online
	end -- if: has a GUID
	
	return UnitGUID(toProfile), targetPlayer

end

-- Warlords of Draenor - changed Functions

function BBPlayerState.base:ParseGUID(unitGUID)
	local guidOffset = 1
	local typeID
	local unitID
	local guidSnip

	-- i.e. Player-976-0002FD64
	-- i.e. Creature-0-976-0-11-31146-000136DF91

	for guidSnip in string.gmatch(unitGUID,"[%a%d]+") do
		if guidOffset == 1 then -- Type: Player, Creature, Pet, GameObject, Vehicle
			-- capture type
			if "Player" ==  guidSnip then
				typeID = self.Constants.Types.Player
			elseif "Pet" == guidSnip then
				typeID = self.Constants.Types.CombatPet
			elseif "Creature" == guidSnip then
				typeID = self.Constants.Types.NPC
			end
		elseif guidOffset == 3 and typeID == self.Constants.Types.Player then
			-- capture player UID
			unitID = guidSnip
		elseif guidOffset == 6 and (typeID == self.Constants.Types.CombatPet or typeID == self.Constants.Types.NPC) then
			-- capture Creature or Pet UID
			unitID = guidSnip
		end
	end
	
	return typeID, unitID
end

function BBPlayerState.base:RefreshPlayers()
	-- ensure cached names match current party/raid
	local i, iTooFar = 0, 0
	local partyMembers,isRaid
	local prefix, numMembers
	local targetGUID, playerGUID
	local targetProfile, petProfile
	local oldTargetIndex
	local iterGUID, iterNext
	local rosterChanged = nil
	local labelName
	local spellID

	-- get your own GUID	
	playerGUID = UnitGUID('player')

	-- if: never seen self before
	if nil == self.Players[playerGUID] then
	
		-- player not yet cached in party!
		playerGUID, targetProfile = self:ProfileUnit('player')

		-- if: able to profile
		if targetProfile then

			-- if: new to the cache
			if nil == self.Players[playerGUID] then
			
				self.Players[playerGUID] = targetProfile
				self.PlayerCount = self.PlayerCount + 1
				self.PlayerGUID = playerGUID
				self:PetChanged('player')

				rosterChanged = true
			end -- if: new to the cache
		end -- if: able to profile
	else
		-- check names
		playerGUID = UnitGUID('player')

		-- update name, if it changed
		if self.Players[playerGUID]
		and self.Players[playerGUID].Name ~= UnitName('player') then

			self.Players[playerGUID].Name = UnitName('player')
		end -- update name, if it changed
	end -- if: never seen before

	--[[
	-- if: in group, not inspected, and not waiting for inspection
	if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
		table.insert(self.StalePlayers, targetGUID)
	end -- if: in group, not inspected, and not waiting for inspection
	]]
	
	-- Build the Bufflist.Players as 'potential buffers';  it will
	-- act as an L'inspect' list for a later mechanism
	numMembers = self.Constants:GetNumGroupMembers()
	prefix = self.Constants:GetGroupPrefix()
	
	-- if: in a party, with more than self
	if prefix and numMembers > 1 then
		-- for: each REAL party member
		for i=1,numMembers do
			
			targetGUID = UnitGUID(prefix..i)

			-- if: never seen before
			if not self.Players[targetGUID] then
			
				-- perform a shallow-profile (name, class, ...)
				targetGUID, targetProfile = self:ProfileUnit(prefix..i)
				
				-- if: able to profile
				if targetProfile then
					
					-- if: new to cache
					if not self.Players[targetGUID] then
						-- Add player, scan buffs, mark for inspection
						self.Players[targetGUID] = targetProfile
						self.PlayerCount = self.PlayerCount + 1
						self:PetChanged(prefix..i)
						
						rosterChanged = true
					end -- if: new to the cache
				end -- if: able to profile
			else
				-- check names
				targetGUID = UnitGUID(prefix..i)
				-- update name, if it changed
				if self.Players[targetGUID]
				and self.Players[targetGUID].Name ~= UnitName(prefix..i) then
					self.Players[targetGUID].Name = UnitName(prefix..i)
				end -- update name, if it changed
				
				-- check visibility (players only)
				if not UnitIsVisible(self.Players[targetGUID].Name) and self.Players[targetGUID].Type == self.Constants.Types.Player then
					-- outside area of interest/events:  mark for full scan when near us
					self.Players[targetGUID].Stale = true
				end -- check visibility
			end -- if: never seen before

			--[[
			-- if: in group, not inspected, and not waiting for inspection
			if self.Players[targetGUID] and self.Players[targetGUID].Stale and not listContains(self.StalePlayers, targetGUID) then
				-- mark for talent scan
				table.insert(self.StalePlayers, targetGUID)
			end -- mark for talent scan
			]]
			
		end -- for: each REAL party member
	end -- in a party, with more than self

	-- remove players who left
	iterGUID, currentProfile = next(self.Players, nil)
	
	-- for: each cached party member
	while iterGUID and not (iTooFar > self.Constants.MaxPlayers) do
		iterNext, nextProfile = next(self.Players, iterGUID)
		
		-- if: not in raid/party
		if currentProfile.Type == self.Constants.Types.Player
		and not (UnitInParty(currentProfile.Name) or UnitInRaid(currentProfile.Name) or playerGUID == iterGUID) then
			-- stop tracking unit
			MyDebugPrint('removing %s; left party/raid', currentProfile.Name)
			
			self.Players[iterGUID] = nil
			self.PlayerCount = self.PlayerCount - 1

			rosterChanged = true
		end -- if: not in raid/party
		
		-- next entry
		iterGUID = iterNext
		currentProfile = nextProfile
		
		iTooFar = iTooFar + 1
	end -- for: each cached party member
	
	return rosterChanged
end

function BBPlayerState.base:ProfileUnit(toProfile)
	local targetPlayer = nil
	local unknownSpells = {}
	local theirClass
	local theirFamily
	local theirType
	local theirLevel = UnitLevel(toProfile)
	local theirName = UnitName(toProfile)
	local typeID
	local theirGUID = UnitGUID(toProfile)
	
	MyDebugPrint("THN: profiling unit "..tostring(toProfile)..", "..tostring(theirName)..", guid "..tostring(theirGUID))
	if theirGUID then
		typeID = self:ParseGUID(theirGUID)

		_, theirClass = UnitClass(toProfile)
		theirFamily = UnitCreatureFamily(toProfile)
		
		-- if: online
		if UnitIsConnected(toProfile)
		and theirLevel > 0
		and theirName
		and theirClass
		and UnitIsVisible(theirName) then

		-- TODO:  Check for secondary role on zone-change, based on
		-- isTank, isHeal, isDPS = UnitGroupRolesAssigned(unitid)

			--if (typeID == self.Constants.Types.CombatPet or typeID == self.Constants.Types.Player) then
			if typeID == self.Constants.Types.Player then
				MyDebugPrint("profiling unit %s", toProfile)
				targetPlayer = {
					Name = theirName,
					Class = theirClass,
					Type = typeID,
					Level = theirLevel,
					Role = self.Constants.Roles.Unknown,
					Inspected = nil,
					BuffSlots = {},
					CastableBuffs = {},
					ActiveBuffs = {},
					Near = true,
					LOS = true,
					Stale = true,
					ActiveTalentGroup = self.Constants.TalentGroup.Unknown,
				}
				
				-- for: seeding each type of castable buff
				for labelName, _ in pairs(self.Constants.DownRankLookup) do
					targetPlayer.CastableBuffs[labelName] = self.Constants.Buffs.None
				end -- for: seeding each type of castable buff
			end -- if: controlled, permanent GUID
		end -- if: online
	end -- if: has a GUID
	
	return UnitGUID(toProfile), targetPlayer

end

function BBPlayerState.base:SetRole(unitGUID, talentIndex)
	local slotName, buffType
	local buffSlot, buff
	local targetPlayer = self.Players[unitGUID]

	if targetPlayer then
		MyDebugPrint("found cached profile for "..targetPlayer.Name.." during Inspect.  talent "..tostring(talentIndex))
		-- Populate the types of buffs we can cast, and the slot they are mutually exclusive with

		-- for - each buff slot (BLESSING, SHOUT, HORN, etc)
		for slotName, buffSlot in pairs(self.Constants.BuffSlots) do
			-- for - each spell in the buff slot (kings, might, etc)
			for _, buff in pairs(buffSlot) do
				-- if - talentIndex is in .Spec
				if listContains(buff.Spec, talentIndex) and targetPlayer.Level >= buff.MinLevel then
			 		MyDebugPrint(targetPlayer.Name.." knows "..slotName)

					-- unitGUID's spec matches; they must know the spell, aka at least a subset of the buffSlot
					targetPlayer.BuffSlots[slotName] = buffSlot

					-- for - each .Types provided by the buff (STAMINA, HASTE, MASTERY, etc)
					for buffType in pairs(buff.Types) do-- sp?
						-- add type to CastableBuffs
				 		MyDebugPrint(targetPlayer.Name.." can provide "..buffType)
						targetPlayer.CastableBuffs[buffType] = buff.Score
					end
				end
			end
		end

		-- Assign a role, based on specializationIndex
		-- CORRECTIONS:
		-- 70 Retribution paladin

		-- Tanks: 
		if 66 == talentIndex or -- Protection (Paladin)
			73 == talentIndex or -- Protection (Warrior)
			104 == talentIndex or -- Guardian
			250 == talentIndex or -- Blood
			268 == talentIndex then -- Brewmaster

			targetPlayer.Role = self.Constants.Roles.Tank

		elseif -- Healers:
			65 == talentIndex or -- Holy
			105 == talentIndex or -- Restoration (Druid)
			256 == talentIndex or -- Discipline
			257 == talentIndex or -- Holy
			264 == talentIndex or -- Restoration (Shaman)
			270 == talentIndex then -- Mistweaver

			targetPlayer.Role = self.Constants.Roles.Healer

		elseif -- Spell Casters:
			62 == talentIndex or -- Arcane
			63 == talentIndex or -- Fire
			64 == talentIndex or -- Frost
			102 == talentIndex or -- Balance
			258 == talentIndex or -- Shadow
			262 == talentIndex or -- Elemental
			265 == talentIndex or -- Affliction
			266 == talentIndex or -- Demonology
			267 == talentIndex then -- Destruction

			targetPlayer.Role = self.Constants.Roles.Caster

		elseif -- Physical DPS:
			70 == talentIndex or -- Retribution
			71 == talentIndex or -- Arms
			72 == talentIndex or -- Fury
			103 == talentIndex or -- Feral
			251 == talentIndex or -- Frost
			252 == talentIndex or -- Unholy
			253 == talentIndex or -- Beast Mastery
			254 == talentIndex or -- Marksmanship
			255 == talentIndex or -- Survival
			259 == talentIndex or -- Assassination
			260 == talentIndex or -- Combat
			261 == talentIndex or -- Subtlety
			263 == talentIndex or -- Enhancement
			269 == talentIndex then -- Windwalker

			targetPlayer.Role = self.Constants.Roles.PureMelee
		else
			targetPlayer.Role = self.Constants.Roles.Unknown
		end

 		MyDebugPrint(targetPlayer.Name.." is a "..targetPlayer.Role)
	end

	return true
end