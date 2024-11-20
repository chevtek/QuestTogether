QuestTogether = LibStub("AceAddon-3.0"):NewAddon(
	"QuestTogether",
	"AceComm-3.0",
	"AceConsole-3.0",
	"AceEvent-3.0",
	"AceHook-3.0",
	"AceSerializer-3.0"
)
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function QuestTogether:Debug(message)
	if self.db.profile.debugMode then
		self:Print("Debug: " .. message)
	end
end

function QuestTogether:OnInitialize()
	-- Initialize settings database.
	self.db = LibStub("AceDB-3.0"):New("QuestTogetherDB", self.defaultOptions, true)

	-- Register options table with Blizzard UI.
	AceConfig:RegisterOptionsTable("QuestTogether", self.options, { "qt", "questtogether", "questogether" })
	self.optionsFrame = AceConfigDialog:AddToBlizOptions("QuestTogether", "QuestTogether")

	-- Register the profiles panel with Blizzard UI.
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	AceConfig:RegisterOptionsTable("QuestTogether_Profiles", profiles)
	AceConfigDialog:AddToBlizOptions("QuestTogether_Profiles", "Profiles", "QuestTogether")

	-- Register comm prefix.
	self:RegisterComm("QuestTogether")

	self:Debug("Initialized.")
end

function QuestTogether:OnEnable()
	self:Debug("OnEnable()")

	-- Register events.
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_REMOVED")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("SUPER_TRACKING_CHANGED")
	self:RegisterEvent("GROUP_JOINED")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")

	-- Schedule task to run initial quest log scan.
	table.insert(self.onQuestLogUpdate, function()
		QuestTogether:Debug("Running initial quest log scan...")
		QuestTogether:ScanQuestLog()
	end)
end

function QuestTogether:OnDisable()
	self:Debug("OnDisable()")
end

function QuestTogether:ScanQuestLog()
	self:Debug("ScanQuestLog()")
	QuestTogether.db.global.questTrackers[UnitName("player")] = {}
	local numQuestLogEntries = C_QuestLog.GetNumQuestLogEntries()
	local questsTracked = 0
	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = C_QuestLog.GetInfo(questLogIndex)
		if
			questInfo.isHeader == false
			and questInfo.isHidden == false
			and not C_QuestLog.IsWorldQuest(questInfo.questID)
		then
			self:WatchQuest(questInfo.questID, questInfo)
			questsTracked = questsTracked + 1
		end
	end
	self:Print(questsTracked .. " quests are being monitored.")
end

function QuestTogether:WatchQuest(questId, questInfo)
	self:Debug("WatchQuest(" .. questId .. ")")
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questId)
	local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
	self.db.global.questTrackers[UnitName("player")][questId] = {
		title = questInfo.title,
		objectives = {},
	}
	for objectiveIndex = 1, numObjectives do
		local objectiveText, type = GetQuestObjectiveInfo(questId, objectiveIndex, false)
		if type == "progressbar" then
			local progress = GetQuestProgressBarPercent(questId)
			objectiveText = progress .. "% " .. objectiveText
		end
		self.db.global.questTrackers[UnitName("player")][questId].objectives[objectiveIndex] = objectiveText
	end
end

function QuestTogether:SanitizeChatInput(input)
	-- Remove texture links (e.g., |TtexturePath:size|t)
	input = input:gsub("|T.-|t", "")

	-- Remove color codes (e.g., |cAARRGGBBtext|r)
	input = input:gsub("|c%x%x%x%x%x%x%x%x", "") -- Remove opening color tags
	input = input:gsub("|r", "") -- Remove closing color tags

	-- Remove any other escape sequences (e.g., |Hhyperlink|htext|h)
	input = input:gsub("|H.-|h", "") -- Remove hyperlink tags
	input = input:gsub("|%a", "") -- Remove any remaining "|X" sequences

	-- Remove any invalid characters
	input = input:gsub("[^a-zA-Z0-9 !@#$%%%^&*()%-=_+%[%]{};:'\",.<>%?/|\\~`]", "")

	return input
end

function QuestTogether:Announce(message)
	message = self:SanitizeChatInput(message)
	self:Debug("Announce(" .. message .. ")")
	local function sendMessage(channel)
		local success, err = pcall(function()
			SendChatMessage(message, channel)
		end)
		if not success then
			self:Debug('Error sending "' .. message .. '" to ' .. channel .. ": " .. err)
		end
	end
	local primaryChannel = self.db.profile.primaryChannel
	local fallbackChannel = self.db.profile.fallbackChannel
	if primaryChannel == "console" then
		self:Print(message)
	elseif primaryChannel == "guild" and IsInGuild() then
		sendMessage("GUILD")
	elseif primaryChannel == "instance" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		sendMessage("INSTANCE_CHAT")
	elseif primaryChannel == "party" and UnitInParty("player") then
		sendMessage("PARTY")
	elseif primaryChannel == "raid" and IsInRaid() then
		sendMessage("RAID")
	else
		if fallbackChannel == "console" then
			self:Print(message)
		elseif fallbackChannel == "guild" and IsInGuild() then
			sendMessage("GUILD")
		elseif fallbackChannel == "instance" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			sendMessage("INSTANCE_CHAT")
		elseif fallbackChannel == "party" and UnitInParty("player") then
			sendMessage("PARTY")
		elseif fallbackChannel == "raid" and IsInRaid() then
			sendMessage("RAID")
		else
			self:Debug(
				"Unable to send message to primary or fallback channel: " .. primaryChannel .. "|" .. fallbackChannel
			)
			return
		end
	end
end
