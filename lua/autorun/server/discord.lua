--[[-------------------------------------------------------------------------
Discord.glua

TODO: ADD SIMPLE DOCS AND INTRO HERE



---------------------------------------------------------------------------]]

Discord = Discord || {}
	Discord.Objects = {} -- object storage
	Discord.API = {} -- function storage
	Discord.Internal = Discord.Internal || {} -- internal functions and hooks
	Discord.Clients =  Discord.Clients || {}
	Discord.Sockets = pcall(require, "gwsockets")
	Discord.version = "0.1"

if !Discord.Sockets then 
	local msg = function(...) return MsgC(Color(255,255,0), ... .. "\n") end
	msg("--------------------------------------------------")
	msg("You are missing GWSockets, the relay cannot load!")
	msg("Without that, the Discord relay will NOT load.")
	msg("Download the " .. jit.os .. " release at [https://github.com/FredyH/GWSockets/releases]")
	msg("Get and install the addon into garrysmod/lua/bin for the relay to work...")
	msg("--------------------------------------------------")
	Discord = nil
	return
end

local Internal, API, Clients, Meta = 
	Discord.Internal, Discord.API, Discord.Clients, Discord.Objects


--[[-------------------------------------------------------------------------
META FUNCTIONS
---------------------------------------------------------------------------]]

--[[
	Tracked hooks.
]]
function Internal:newHook(realm, flag, name, func, ...)
	local varargs = {...}
	hook.Add(flag, "Discord." .. realm .. "." .. name, function()
		local override = hook.Run("Discord.Internal.", realm .. "." .. name)
		if !override then
			func(unpack(varargs))
		end
	end)
end



--[[
	Organized think process.
	These processes will ONLY be ran when there is an active Gateway.
--]]
Internal.hooks = {}
function Internal:newProcess(name, func, ...)
	if !isstring( name ) || !isfunction( func ) then
		return
	end
	Internal.hooks[ name ] = {
    func = func,
    args = {...}
  }
  Discord.Internal:Output("Internal", "Process " .. name .. " was created.")
	return function()
		Internal.hooks[ name ] = nil
	end
end

function Internal:doProcess()
	for k,v in pairs(Internal.hooks) do
		local r, e = pcall(function() v.func(unpack(v.args)) end)
		if !r then
			Discord.Internal:Output("Internal", "Process " .. k .. " killed.\n[" .. e .. "]", false)
			Internal.hooks[ k ] = nil
			continue
		end
	end
end
Internal:newHook("Internal", "Tick", "Think", Internal.doProcess, Discord.Internal)

function Internal:Output(realm, str, iserror)
  local tag = "[Discord.glua (alpha) - " .. realm .. "]: " .. str
  if iserror then
    return error(tag)
  else
    return print(tag)
  end
end

--[[
	Shitty discord color format to RGB
]]

function Internal.hex2rgb(hex)
    hex = tostring(hex):gsub("#","")
    return Color( tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6)) )
end
--[[
	RGB to Shitty discord color format
]]

function Internal.rgb2hex(col)
    local color, hex = table.concat({col.r, col.b, col.g}, " "), "0x"
    for rgb in color:gmatch('%d+') do
        hex = hex .. ('%02X'):format(tonumber(rgb))
    end
    return bit.tobit(tonumber(hex))
end

function IsDiscordObj(tab)
	return istable(tab) && tab.discordOjb
end

--[[
	Object Creation
]]

local defaultObject = {
	["defaultValues"] = function(self, tab)
		return table.Merge(self, tab)
	end,
}

function Internal:newObject(str, constructor)
	if isstring( str ) then
		Discord.Objects[str] = {}
        Discord.Objects[str].discordOjb = true
        Discord.Objects[str].__index = Discord.Objects[str]
        setmetatable(Discord.Objects[str], {__call = constructor || function() return end})
		return table.Merge(Discord.Objects[str], defaultObject)
	end
end

API.Bitflags = {
	["CREATE_INSTANT_INVITE"] = 0x1,
	["KICK_MEMBERS"] = 0x2,
	["BAN_MEMBERS"] = 0x4,
	["ADMINISTRATOR"] = 0x8,
	["MANAGE_CHANNELS"] = 0x10,
	["MANAGE_GUILD"] = 0x20,
	["ADD_REACTIONS"] = 0x40,
	["VIEW_AUDIT_LOG"] = 0x80,
	["PRIORITY_SPEAKER"] = 0x100,
	["STREAM"] = 0x200,
	["VIEW_CHANNEL"] = 0x400,
	["SEND_MESSAGES"] = 0x800,
	["SEND_TTS_MESSAGES"] = 0x1000,
	["MANAGE_MESSAGES"] = 0x2000,
	["EMBED_LINKS"] = 0x4000,
	["ATTACH_FILES"] = 0x8000,
	["READ_MESSAGE_HISTORY"] = 0x10000,
	["MENTION_EVERYONE"] = 0x20000,
	["USE_EXTERNAL_EMOJIS"] = 0x40000, -- 40k :haah:
	["CONNECT"] = 0x100000,
	["SPEAK"] = 0x200000,
	["MUTE_MEMBERS"] = 0x400000,
	["DEAFEN_MEMBERS"] = 0x800000,
	["MOVE_MEMBERS"] = 0x1000000,
	["USE_VAD"] = 0x2000000,
	["CHANGE_NICKNAME"] = 0x4000000,
	["MANAGE_NICKNAMES"] = 0x8000000,
	["MANAGE_ROLES"] = 0x10000000,
	["MANAGE_WEBHOOKS"] = 0x20000000,
	["MANAGE_EMOJIS"] = 0x40000000,
}

function API.permission(...)
	local bitFlag = 0x0
	local tab = {...}
	for i = 1, #tab do
		if API.Bitflags[tab[i]] then
			bitFlag = bit.bor(bitFlag, API.Bitflags[tab[i]])
		end
	end
	return bitFlag
end

function API.checkPermission(bitflag, permission)
	assert(API.Bitflags[permission], "Permission value not found!")
	return bit.band(bitflag, API.Bitflags[permission]) == API.Bitflags[permission]
end

function API.translatePermission(bitflag)
	local perms = {}
	for x,o in pairs(API.Bitflags) do
		if API.checkPermission(bitflag, x) then
			table.insert(perms, x)
		end
	end
	return perms
end


--[[-------------------------------------------------------------------------
GATEWAY
---------------------------------------------------------------------------]]

--[[
	Protocal (OPCodes) Object
]]

local OPCodes = {
	[0] = {
		Name = "Dispatch-Event",
		Action = function(self, tab)
			if tab.t then
				tab.t = tab.t:upper()
				self:dispatch(tab.t, tab)
			end
		end
	},
	[1] = {
		Name = "heartbeat-send",
		Action = function(self)
			self.heart.active = false
			return self.heart.val || ""
		end
	},
	[2] = {

		Name = "Identify",
		Action = function(self)
			return {
				token = self.token,
				properties = {
					["$os"] = jit.os || "GM_SERV",
					["$browser"] = "discord.glua",
					["$device"] = "discord.glua",
				}
			}
		end
	},
	[3] = {
		Name = "Status-Update",
		Action = function(self, nameStr, type, status)
			return {
				status = status || "online",
				game = {
					name = nameStr || "online",
					type = isnumber( type ) || 0,
				},
				afk = false,
				since = "null", -- "since" is not used on discord bots.
			}
		end
	},
	[4] = {
		Name = "Voice-State-Update"
		-- No action required.
	},
	[6] = {
		Name = "Resume-request",
		Action = function(self)
			return {
				token = self.token,
				session_id = self.session_id,
				seq = self.heart.val || 0,
			}
		end
	},
	[7] = {
		Name = "reconnect",
		Action = function(self)
			self:setStatus("reconnect-resume")
			self:close()
		end
	},
	[8] = {
		Name = "Request-Guild-Members",
		Action = function(self, id, query, limit)
			return {
				guild_id = id,
				query = query && tostring(query) || "", -- empty string == all members
				limit = limit && tonumber(limit) || 0, -- /shrug
			}
		end
	},
	[9] = {
		Name = "Invalid-session",
		Action = function(self, resume)
			if resume then
				self:setStatus("reconnect-resume")
				self:closeNow()
				return
			end
			self:setStatus("reconnect")
			self:closeNow()
		end
	},
  [11] = {
    Name = "heartbeat-return",
    Action = function(self)
      self.heart.active = true
    end
  },
	[10] = {
		Name = "Hello",
		Action = function(self, tab)
			self.heart.interval = tab.heartbeat_interval / 1000
			self.heart.active = true
			self:startHeartBeat()
			if self:getStatus() == "reconnect-resume" then
				self:say(6)
				return
			end
			self:say(2)
		end
	}
}

--[[
    Internal events (shit the end user won't need to touch)
]]

local ievents = {
	--[[
		Status events
	]]
    ["HELLO"] = function(self, tab)
        print("Recived hello event!")
    end,
    ["RECONNECT"] = function(self, tab)
    	self:status("RECONNECT")
    	self:close()
    end,
    ["READY"] = function(self, tab)
        self.user = setmetatable(tab.user, Discord.Objects.members)
        if self:getStatus() == "reconnect-resume" then
        	self:say(6)
        	return
        end
        self:setStatus("active")
        self.__attempts = 0
        self.guilds = {}
        self.session_id = tab.session_id
        for i = 1, #tab.guilds do
        	self.guilds[ tab.guilds[i]["id"] ] = {stub = true}
        end
        // TODO: Data handler section
    end,
    ["RESUMED"] = function(self)
    	self:setStatus("active")
    	self.__attempts = 0
    end,

	--[[
		Guilds
	]]
    ["GUILD_CREATE"] = function(self, tab)
    	--self.guilds[ tab["id"] ] = setmetatable(tab, Discord.Objects.Guild)
    	self.guilds[ tab["id"] ] = tab
    	self.guilds[ tab["id"] ]["unavailable"] = nil
    	self.guilds[ tab["id"] ]["ref"] = table.Merge({guild = tab.id}, self.ref)
    	self.guilds[ tab["id"] ]["events"] = {}
    	setmetatable(self.guilds[ tab["id"] ], Discord.Objects.DiscordGuild)

    	self.guilds[ tab["id"] ]()
    	return self.guilds[ tab["id"] ]
    	--self.guilds[ tab["id"] ]:Update()
    end,
    ["GUILD_UPDATE"] = function(self, tab)
    	--self.guilds[ tab["id"] ] = setmetatable(tab, Discord.Objects.Guild)
    	self.guilds[ tab["id"] ] = table.Merge(self.guilds[ tab["id"] ], tab)
    	return self.guilds[ tab["id"] ]
    end,
    ["GUILD_DELETE"] = function(self, tab)
    	self.guilds[ tab["id"] ]["unavailable"] = true
    end,
    ["GUILD_BAN_ADD"] = function(self, tab)
    	local tab = setmetatable(tab["user"], Discord.Objects.members)
    	self.guilds[ tab["guild_id"] ]["banlist"][ tab["user"]["id"] ] = tab
    	return self.guilds[ tab["guild_id"] ]["banlist"][ tab["user"]["id"] ]
    end,
    ["GUILD_BAN_REMOVE"] = function(self, tab)
    	self.guilds[ tab["guild_id"] ]["banlist"][ tab["user"]["id"] ] = nil
    end,    
    --[[
		Channels
	]]
    ["CHANNEL_CREATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
 		table.insert(tab, guild["ref"])
 		local tab = setmetatable(tab, Discord.Objects.channels)
 		guild.channels[ tab.id ] = tab
 		return guild.channels[ tab.id ]

    end,
    ["CHANNEL_UPDATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
 		table.Merge(guild.channels[ tab.id ], tab)
 		return guild.channels[ tab.id ]
    end,
    ["CHANNEL_DELETE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
    	guild.channels[ tab.id ] = nil
    end,
    --[[
    	Member
    ]]
    ["GUILD_MEMBER_ADD"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
    	table.insert(tab, guild["ref"])
    	local tab = setmetatable(tab, Discord.Objects.members)
    	guild.members[ tab["id"] ] = tab
    	return guild.members[ tab["id"] ]
    end,
    ["GUILD_MEMBER_UPDATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
 		table.Merge(guild.members[ tab.user.id ], tab)
 		return guild.members[ tab.user.id ]
    end,
    ["GUILD_MEMBER_REMOVE"] = function(self, tab)
     	local guild = self.guilds[ tab["guild_id"] ]
 		guild.members[ tab.id ] = nil
    end,
    ["GUILD_MEMBERS_CHUNK"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
    	for k,v in pairs(tab.members) do
    		table.insert(v, guild["ref"])
    		guild.members[ v["user"]["id"] ] = setmetatable(v, Discord.Objects.members)
    	end
    end,
    ["USER_UPDATE"] = function(self, tab)
    	table.Merge(self.user, tab)
    	return self.user
    end,
    --[[
    	Message
    ]]
    ["MESSAGE_CREATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
 		tab["ref"] = table.Copy(guild["ref"])
		tab["getUser"] = function() return Discord.Clients[ tab.ref["usr"] ] end
		tab["getGuild"] = function() return Discord.Clients[ tab.ref["usr"] ].guilds[ tab.ref["guild"] ] end
 		local tab = setmetatable(tab, Discord.Objects.messages)
 		guild.channels[ tab.channel_id ].messages[ tab.id ] = tab
 		return guild.channels[ tab.channel_id ].messages[ tab.id ]
    end,
    ["MESSAGE_UPDATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
    	local msgLoc = guild.channels[ tab.channel_id ].messages
    	if msgLoc[tab.id] then
    		table.Merge(msgLoc[tab.id], tab)
    	else
    		msgLoc[tab.id] = setmetatable(tab, Discord.Objects.messages)
    	end
    	return msgLoc[ tab.id ]
    end,
}

--[[
    Client
]]


local Client = Internal:newObject("Client", function(self, name)
    assert(isstring(name), "Bad arugment #1, unique name (string) required, got" .. type(name) .. ".", false)
    if Discord.Clients[name] then
        return Discord.Clients[name] -- if there is already a client created
    end
    Discord.Clients[name] = GWSockets.createWebSocket("wss://gateway.discord.gg/?v=6&encoding=json",false)
    Discord.Clients[name]["ref"] = {usr = name}
    table.Merge(Discord.Clients[name], table.Copy(Discord.Objects.Client))
    return Discord.Clients[name]
end)

Client:defaultValues({
	heart = {
		val = 0,
		interval = 0,
		active = false,
	   	lastBeat = 0,
	},
	__status = {
		["off"] = -1,
		["reconnect"] = 0,
		["reconnect-resume"] = 1,
		["active"] = 2,
		["stopping"] = 3,
	},
	status = "off",
	session_id = "",
	token = "",
	OP = table.Copy(OPCodes),
	events = {},
    __attempts = 0,
    __endpoint = "https://sbmrp.com/hcon/test2.php",
    __events = table.Copy(ievents),
    __tasks = {["all"] = {lastreset = SysTime(), reset = 1, count = 0, max = 50}},
})


-- accessor functions

function Client:getStatus()
	return self.status
end


function Client:isActive()
	return self.status > 0
end

function Client:getToken()
	return self.token
end

function Client:getGuilds()
	return self.guilds
end

function Client:getGuild(str)
	if self.guilds[ str ] then
		return self.guilds[str]
	else
		for k,v in pairs(self.guilds) do
			if v:getName() == str then
				return v
			end
		end
	end
	return false
end

-- mutator

function Client:setStatus(str)
	assert(isstring(str), "Bad argument #1, string expected, got " .. type(str) .. ".")
	assert(self.__status[ str ], "Bad argument #1, not a valid status!")
	Internal:Output("Status", "Status changed: " .. self.status .. " --> " .. str)
	self.status = str

end


function Client:setToken(str)
	assert(isstring(str) && #str == 59, "Bad argument #1, token required!")
	self.token = str
end


function Client:say(opCode, ...)
	if self.OP[ opCode ] then
		local payload = self.OP[ opCode ].Action(self, ...)
        Internal:Output("OPCodes", "To Discord [" .. opCode .. "] " .. self.OP[ opCode ].Name)
        local msg = {
			op = opCode,
			d = payload
		}
		self:write(util.TableToJSON(msg):Replace(".0", ""))
	end
end

function Client:dispatch(_, event)
    Internal:Output("Event","From Discord: " .. event.op  .. " [" .. (event.t || "Unknown") .. "]" )
    local override = nil
   if self.__events[event.t] then
        override = self.__events[event.t](self, event.d)
   end
   // Todo: client end event handler
   if self.events[event.t] then
         self.events[event.t](self, override || event.d)
   end
   file.Write("dump.txt", util.TableToJSON(self.guilds, true))
end



local function checkRate(self, e)
	local s = SysTime()
	local t = self.__tasks
	if !t[e] then return end
	if ( s < ( t[e].lastreset + t[e].reset) ) then
		if t[e].count >= t[e].max then
			return -1, t[e].lastreset + t[e].reset - s
		end
		t[e].count = t[e].count + 1
	else
		t[e].lastreset = s
		t[e].count = 0
	end
	return true
end

function handleReturn(c, b, h)
	print("Code:\n" .. c)
	print("Body:\n" .. b)
	print("HEADERS:")
	PrintTable(h)
end

function Client:HTTP(e, m, p, c, f, h, t, a)
	--if !self:Status() != "ACTIVE" then return end
	local s = SysTime()
	local x = self.__tasks
	if (isnumber(t) && isnumber(a)) && !x[e] then
		x[e] = {
			lastreset = s,
			reset = t,
			count = 0,
			max = a,
		}
	end
	for k,v in pairs({e, "all"}) do
		if select(1, checkRate(self, v)) == -1 then
			timer.Simple(select(2, checkRate(self, v)) + math.Rand(0,1), function()
				self:HTTP(e, m, p, c, f, h, t, a)
			end)
			return
		end
	end
	local t_struct = {
		method = m,
		success = function(code,body,head) handleReturn(code,body,head,c) end,
		failure = f,
		body = util.TableToJSON(p, false),
		url = self.__endpoint,
		headers = {["Header-Json"] = util.TableToJSON(
			table.Merge( h || {}, {
				["Authorization"] = "Bot " .. self.token,
				["Desired-Discord-Url"] = "https://discordapp.com/api/" .. e
			})
		, false)},
		type = "application/json"
	}
	HTTP(t_struct)
end

function Client:beat()
    if ( self.heart.lastBeat < SysTime() ) then
        if !self.heart.active then
            self:stopHeartBeat()
            self:closeNow()
            print("Heartbeat failed! Closing socket.")
            return
        end
		self.heart.active = false
		self:say(1)
       self.heart.lastBeat = SysTime() + self.heart.interval
   end
end

function Client:startHeartBeat()
	heartProcess = Internal:newProcess("socket_heartbeat-" .. SysTime(), self.beat, self) -- runs heartbeat
	self.stopHeartBeat = heartProcess
end

function Client:stop()
	self:setStatus("off")
	self:close()
end



function Client:start()
	local st = self:getStatus()
	if st == "active" || st == "off" || self.__attempts > 1 then
		self:closeNow()
		self:setStatus("reconnect")
	end
	self.__attempts = self.__attempts + 1
	self:open()
end




function Client:updateSelf(nameStr, type, status)
  return self:say(3, nameStr, type, status)
end


function Client:onError()
    Internal:Output("Gateway","Erroring and closing.")
    self:closeNow()
end

function Client:onConnected()
    Internal:Output("Gateway","Opened new connection.")
end

function Client:onDisconnected()
    Internal:Output("Gateway","Socket closed.")
    self:stopHeartBeat()
    if self:getStatus() == "off" then return end
    if self.__attempts > 3 then
    	Internal:Output("Gateway", "Critical failure, failed to connect after three tries. Stopping relay.")
    	self:setStatus("off")
    	return
    elseif self.__attempts == 0 && self:getStatus() == "active" then
    	self:setStatus("reconnect-resume")
    	Internal:Output("Gateway","Attempting to resume previous connection.")
    end
    timer.Simple(1, function()
		Internal:Output("Gateway","Opening socket.")
    	self:start()
    end)
    
end

function Client:onMessage(msg)
    local res = util.JSONToTable(msg)
    --print("FROM DISCORD: " .. res.op  .. " [" .. (res.t || "Unknown") .. "]" )
    if self.OP[res.op] then
    	Internal:Output("OPCode", "From Discord: " .. res.op  .. " [" .. (self.OP[res.op].Name || "Unknown") .. "]" )
        self.OP[res.op].Action(self, (res.t && res) || res.d)
    end
    self.heart.val = res.s || self.heart.val
end

function Client:addEvent(event, func)
	assert(isstring(event), "Bad argument #1, string expected, got " .. type(event) .. ".")
	assert(isfunction(func), "Bad argument #1, function expected, got " .. type(event) .. ".")
	self.events[ event:upper():Replace(" ", "_") ] = func
end
--[[-------------------------------------------------------------------------
Discord Objects
---------------------------------------------------------------------------]]


--[[
	Guild object:
]]

local Guild = Internal:newObject("DiscordGuild")


local function scanTable(tab)
	for k,v in pairs(tab) do
		if istable(v) then
			scanTable(v)
		end

		if Discord.Objects[k] then
			for x,o in pairs(v) do
				if !istable(o) then continue end
				o["ref"] = tab.ref
				o["getUser"] = function() return Discord.Clients[ tab.ref["usr"] ] end
				o["getGuild"] = function() return Discord.Clients[ tab.ref["usr"] ].guilds[ tab.ref["guild"] ] end
				setmetatable(o, Discord.Objects[k])
			end
		end

	end
end

function Guild:__call()
	for k,v in pairs(self) do
		if istable( v ) && ( v[1] && istable(v[1])  && v[1]["id"] ) then
			local n = {}
			for x,o in pairs(v) do
				n[ o["id"] ] = o
			end
			self[k] = n
		elseif k == "members" then
			local n = {}
			for x,o in pairs(v) do
				n[ o["user"]["id"] ] = o
			end
			self[k] = n
		end
		if k == "channels" then
			for x,o in pairs(v) do
				o["messages"] = {}
			end
		end
	end
	return scanTable(self)
end

function Guild:getChannel(str)
	if self.channels[ str ] then
		return self.channels[str]
	else
		for k,v in pairs(self.channels) do
			if v:getName() == str then
				return v
			end
		end
	end
	return false
end

function Guild:getMember(str)
	if self.members[ str ] then
		return self.members[str]
	else
		for k,v in pairs(self.members) do
			if v:getName() == str then
				return str
			end
		end
	end
	return false
end

function Guild:getRole(str)
	if self.roles[ str ] then
		return self.roles[str]
	else
		for k,v in pairs(self.roles) do
			if v:getName() == str then
				return v
			end
		end
	end
	return false
end

function Guild:mainChannel()
	return self.channels[ self["system_channel_id"] ]
end

function Guild:getName()
	return self.name
end


function Guild:getID()
	return self.id
end

function Guild:isValid()
	return !self["unavailable"]
end

-- mutator functions




--[[
	Role object
]]
local Role = Internal:newObject("roles", function(self, guild)
	assert(guild && guild.name, "Bad argument #1, expected guild object.")
	return setmetatable({guild = guild, isLocal = true}, Discord.Objects.newRole)
end)

-- accessor functions
function Role:getName()
	return self.name
end

function Role:getID()
	return self.id
end

function Role:getColor()
	return Internal:hex2rgb(self.color)
end

function Role:isHoistable()
	return self.hoist
end

function Role:isMentionable()
	return self.mentionable
end

function Role:getPermissions()
	local perms = {}
	for x,o in pairs(API.Bitflags) do
		if API.checkPermission(self.permissions, x) then
			table.insert(perms, x)
		end
	end
	return perms
end

-- mutator functions
function Role:setColor(color)
	assert(color && IsColor(color), "Bad argument to #1, needs to be a color object!")
	self.color = Internal.rgb2hex(color)
	if self.isLocal then return end
	self:edit({color = self.color})
end

function Role:setName(str)
	assert(str && isstring(str), "Bad argument to #1, needs to be a string!")
	self.name = str
	if self.isLocal then return end
	self:edit({name = self.name})
end

function Role:setHoistable(bool)
	self.hoist = tobool(bool)
	if self.isLocal then return end
	self:edit({hoist = self.hoist})
end

function Role:setMentionable(bool)
	self.mentionable = tobool(bool)
	if self.isLocal then return end
	self:edit({mentionable = self.mentionable})
end

function Role:setPermissions(tab)
	self.permissions = API.permission(unpack(tab))
	if self.isLocal then return end
	self:edit({permissions = self.permissions})
end

function Role:create(cb)
	local newRole = {
		color = self.color || 0.0,
		hoist = self.hoist || false,
		mentionable = self.mentionable || false,
		permissions = self.permissions || 0,
		name = self.name || "new role",
	}
	local user, gld = Discord.Clients[ self.guild["ref"]["usr"] ],self.guild
	self.user:HTTP("guilds/" .. self.guild:getID() .. "/roles", "POST", newRole, function(a, b)
		if a != 200 then return end
		local retRole = setmetatable(util.JSONToTable(b), Discord.Objects.roles)
		if cb then
			cb(retRole)
		end
	end)
end



function Role:edit(tab)
	local n = table.Copy(tab)
	if n["color"] then
		n["color"] = Internal:rgb2hex( n["color"] )
	end
	local Client = Discord.Clients[ self.ref["usr"] ]
	if Client then
		Client:HTTP("guilds/" .. Client:getGuild(self["ref"]["guild"]):getID() .. "/roles/" .. self:getID(), "PATCH", n)
	end
end

function Role:remove()
	for x,o in pairs(Discord.Clients) do
		for k,v in pairs(o.guilds) do
			if v:getRole(self.id) then
				o:HTTP("guilds/" .. v:getID() .. "/roles/" .. self:getID(), "DELETE")
				return true
			end
		end
	end
	return false
end

--[[
	Channel object
]]
local Channel = Internal:newObject("channels", function(self, guild)
	assert(guild && guild.name, "Bad argument #1, expected guild object.")
	return setmetatable({guild = guild, isLocal = true}, Discord.Objects.newRole)
end)

-- accessor functions

function Channel:getName()
	return self.name
end

function Channel:getID()
	return self.id
end

function Channel:getPos()
	return self.position
end

function Channel:getMessage(id, cb)
	if self.messages[ id ] then
		cb(self.messages[id])
		return
	end

end


function Channel:getPermissions()
	local ret = {}
	for k,v in pairs(self.permission_overwrites) do
		ret[ k ] = table.Copy(v)
		ret[k]["allow"] = API.translatePermission(ret[k]["allow"])
		ret[k]["deny"] = API.translatePermission(ret[k]["deny"])
	end
	return ret
end


function Channel:latestMessage()
	// TODO
	return
end


function Channel:isNSFW() -- Channel:isHeyMister()
	return self.nsfw
end

function Channel:getCategory()
	return self.parent_id || nil
end

function Channel:isDM()
	return self.type == 3
end

function Channel:isVC()
	return self.type == 2
end

function Channel:isNews()
	return self.type == 5
end

function Channel:isStore()
	return self.type == 6
end

function Channel:isCategory()
	return self.type == 4
end

function Channel:isText()
	return self.type == 0
end

function Channel:getType()
	return self.type
end

-- mutator functions
function Channel:setName(str)
	assert(str && isstring(str), "Bad argument to #1, needs to be a string!")
	self.name = str
	if self.isLocal then return end
	self:edit({name = self.name})
end

function Channel:setNSFW(bool) -- :heymister:
	self.nsfw = tobool(bool)
	if self.isLocal then return end
	self:edit({nsfw = self.nsfw})
end

function Channel:setPos(num) -- :heymister:
	assert(isnumber(num), "Bad argument #1, number expected!")
	self.position = tonumber(num)
	if self.isLocal then return end
	self:edit({position = self.position})
end



function Channel:edit(tab)
	local Client = Discord.Clients[ self.ref["usr"] ]
	if Client then
		Client:HTTP("/channels/" .. self:getID(), "PATCH", tab)
	end
end

function Channel:create(cb)
	local newRole = {
		permissions = self.permissions || 0,
		name = self.name || "new role",
		type = self.type || 0,
	}
	local user, gld = Discord.Clients[ self.guild["ref"]["usr"] ],self.guild
	self.user:HTTP("guilds/" .. self.guild:getID() .. "/roles", "POST", newRole, function(a, b)
		if a != 200 then return end
		local retRole = setmetatable(util.JSONToTable(b), Discord.Objects.roles)
		if cb then
			cb(retRole)
		end
	end)
end

--[[
	Emote object
]]
local Emote = Internal:newObject("emojis")

function Emote:test()
	PrintTable(self)
end

--[[
	Member object
]]
local Member = Internal:newObject("members")

function Member:test()
	PrintTable(self)
end

--[[
	Presence Object
]]

local Presence = Internal:newObject("presences")

function Presence:test()
	PrintTable(self)
end

--[[
	Message Object
]]
local Message = Internal:newObject("messages", function(self, guild)
	assert(guild && guild.name, "Bad argument #1, expected guild object.")
	return setmetatable({guild = guild, isLocal = true}, Discord.Objects.messages)
end)

-- accessor functions

function Message:getContent()
	return self.content
end

function Message:isTTS()
	return self.tts
end

function Message:hasAttachments()
	return Either(#self.file == 0, false, true)
end
