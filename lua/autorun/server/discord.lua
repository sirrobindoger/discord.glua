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
					type = type && tonumber( type ) || 0,
				},
				afk = false,
				since = JSON.null, -- "since" is not used on discord bots.
			}
		end
	},
	[4] = {
		Name = "Voice-State-Update"
		-- No action required.
	},
	[6] = {
		Name = "Resume",
		Action = function(self)
			return {
				token = self.token,
				session_id = self.session_id,
				seq = self.heart.val || 0,
			}
		end
	},
	[7] = {
		Name = "reconnect"
		// TODO: finish this function
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
		Action = function(self)
			// STATUS SET TO KILLED
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
        self.user = tab.user
        self.guilds = {}
        self.session_id = tab.session_id
        for i = 1, #tab.guilds do
        	self.guilds[ tab.guilds[i]["id"] ] = {stub = true}
        end
        // TODO: Data handler section
    end,

	--[[
		Guilds
	]]
    ["GUILD_CREATE"] = function(self, tab)
    	--self.guilds[ tab["id"] ] = setmetatable(tab, Discord.Objects.Guild)
    	self.guilds[ tab["id"] ] = tab
    	self.guilds[ tab["id"] ]["unavailable"] = nil
    	self.guilds[ tab["id"] ]["ref"] = table.Merge({guild = tab.id}, self.ref)
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
    	return tab
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
 		return tab

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
    	return tab
    end,
    ["GUILD_MEMBER_UPDATE"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
 		table.Merge(guild.members[ tab.user.id ], tab)
 		return tab 	
    end,
    ["GUILD_MEMBER_REMOVE"] = function(self, tab)
     	local guild = self.guilds[ tab["guild_id"] ]
 		guild.members[ tab.id ] = nil
    end,
    ["GUILD_MEMBERS_CUNK"] = function(self, tab)
    	local guild = self.guilds[ tab["guild_id"] ]
    	for k,v in pairs(tab.members) do
    		table.insert(v, guild["ref"])
    		guild.members[ v["id"] ] = setmetatable(v, Discord.Objects.members)
    	end
    	return
    end,
}

--[[
	Socket Object
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
		["Killed"] = -1,
		["Closed"] = 0,
		["Identifying"] = 1,
		["Open"] = 2,
		["Reconnect"] = 3,
	},
	status = 0,
	session_id = "",
	token = "",
	OP = table.Copy(OPCodes),
    events = {},
    __endpoint = "https://sbmrp.com/hcon/test2.php",
    __events = table.Copy(ievents),
    __tasks = {["all"] = {lastreset = SysTime(), reset = 1, count = 0, max = 50}},
})

function Client:active()
	return self.status > 0
end

function Client:say(opCode, ...)
	if self.OP[ opCode ] then
		local payload = self.OP[ opCode ].Action(self, ...)
        Internal:Output("Gateway", "To Discord [" .. opCode .. "]")
		self:write(JSON.encode({
			op = opCode,
			d = payload
		}))
	end
end

function Client:dispatch(_, event)
    Internal:Output("Gateway","FROM DISCORD: " .. event.op  .. " [" .. (event.t || "Unknown") .. "]" )
   if self.__events[event.t] then
       self.__events[event.t](self, event.d)
   end
   // Todo: client end event handler
   if self.events[event.t] then
       self.events[event.t](self, event.d)
   end
end

local validStatus = {
	["IDLE"] = true,
	["LIMITED"] = true,
	["ACTIVE"] = true,
	["RECONNECT"] = true,
	["DEAD"] = true,
}

function Client:status(status)
	if !status then return self.__status end
	if !validStatus[ status:Upper() ] then return end
	self.__status = status:Upper()
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

--[[
    Client
]]

function Client:run(token)
  assert(token && tostring(token), "You must provide a token!")

  self:closeNow()
  self.token = token
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
    Internal:Output("Gateway","Closed by connection.")
end

function Client:onMessage(msg)
    local res = JSON.decode(msg)
    --print("FROM DISCORD: " .. res.op  .. " [" .. (res.t || "Unknown") .. "]" )
    if self.OP[res.op] then
        self.OP[res.op].Action(self, (res.t && res) || res.d)
    end
    self.heart.val = res.s || self.heart.val
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

--[[
	Local role (for creating a new role)
]]




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


--[[-------------------------------------------------------------------------
Third Party
---------------------------------------------------------------------------]]

--[==[

David Kolf's JSON module for Lua 5.1/5.2

Version 2.5


For the documentation see the corresponding readme.txt or visit
<http://dkolf.de/src/dkjson-lua.fsl/>.

You can contact the author by sending an e-mail to 'david' at the
domain 'dkolf.de'.


Copyright (C) 2010-2014 David Heiko Kolf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]==]
print("Discord.glua initalized.")
JSON = {}

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset =
      pairs, type, tostring, tonumber, debug.getmetatable, setmetatable, rawset
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat =
      string.rep, string.gsub, string.sub, string.byte, string.char,
      string.find, string.len, string.format
local strmatch = string.match
local concat = table.concat

-- I don't like creating modules so we'll just add it to our table
-- :ok_hand:, thanks axel.
setfenv(1, JSON)

version = "dkjson 2.5"

null = setmetatable ({}, {
  __tojson = function () return "null" end
})

local function isarray (tbl)
  local max, n, arraylen = 0, 0, 0
  for k,v in pairs (tbl) do
    if k == 'n' and type(v) == 'number' then
      arraylen = v
      if v > max then
        max = v
      end
    else
      if type(k) ~= 'number' or k < 1 or floor(k) ~= k then
        return false
      end
      if k > max then
        max = k
      end
      n = n + 1
    end
  end
  if max > 10 and max > arraylen and max > n * 2 then
    return false -- don't create an array with too many holes
  end
  return true, max
end

local escapecodes = {
  ["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n",  ["\r"] = "\\r",  ["\t"] = "\\t"
}

local function escapeutf8 (uchar)
  local value = escapecodes[uchar]
  if value then
    return value
  end
  local a, b, c, d = strbyte (uchar, 1, 4)
  a, b, c, d = a or 0, b or 0, c or 0, d or 0
  if a <= 0x7f then
    value = a
  elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
    value = (a - 0xc0) * 0x40 + b - 0x80
  elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
    value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
  elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
    value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
  else
    return ""
  end
  if value <= 0xffff then
    return strformat ("\\u%.4x", value)
  elseif value <= 0x10ffff then
    -- encode as UTF-16 surrogate pair
    value = value - 0x10000
    local highsur, lowsur = 0xD800 + floor (value/0x400), 0xDC00 + (value % 0x400)
    return strformat ("\\u%.4x\\u%.4x", highsur, lowsur)
  else
    return ""
  end
end

local function fsub (str, pattern, repl)
  -- gsub always builds a new string in a buffer, even when no match
  -- exists. First using find should be more efficient when most strings
  -- don't contain the pattern.
  if strfind (str, pattern) then
    return gsub (str, pattern, repl)
  else
    return str
  end
end

function quotestring (value)
  -- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
  value = fsub (value, "[%z\1-\31\"\\\127]", escapeutf8)
  if strfind (value, "[\194\216\220\225\226\239]") then
    value = fsub (value, "\194[\128-\159\173]", escapeutf8)
    value = fsub (value, "\216[\128-\132]", escapeutf8)
    value = fsub (value, "\220\143", escapeutf8)
    value = fsub (value, "\225\158[\180\181]", escapeutf8)
    value = fsub (value, "\226\128[\140-\143\168-\175]", escapeutf8)
    value = fsub (value, "\226\129[\160-\175]", escapeutf8)
    value = fsub (value, "\239\187\191", escapeutf8)
    value = fsub (value, "\239\191[\176-\191]", escapeutf8)
  end
  return "\"" .. value .. "\""
end

local function replace(str, o, n)
  local i, j = strfind (str, o, 1, true)
  if i then
    return strsub(str, 1, i-1) .. n .. strsub(str, j+1, -1)
  else
    return str
  end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint ()
  decpoint = strmatch(tostring(0.5), "([^05+])")
  -- build a filter that can be used to remove group separators
  numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function num2str (num)
  return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

local function str2num (str)
  local num = tonumber(replace(str, ".", decpoint))
  if not num then
    updatedecpoint()
    num = tonumber(replace(str, ".", decpoint))
  end
  return num
end

local function addnewline2 (level, buffer, buflen)
  buffer[buflen+1] = "\n"
  buffer[buflen+2] = strrep ("  ", level)
  buflen = buflen + 2
  return buflen
end

function addnewline (state)
  if state.indent then
    state.bufferlen = addnewline2 (state.level or 0,
                           state.buffer, state.bufferlen or #(state.buffer))
  end
end

local encode2 -- forward declaration

local function addpair (key, value, prev, indent, level, buffer, buflen, tables, globalorder, state)
  local kt = type (key)
  if kt ~= 'string' and kt ~= 'number' then
    return nil, "type '" .. kt .. "' is not supported as a key by JSON."
  end
  if prev then
    buflen = buflen + 1
    buffer[buflen] = ","
  end
  if indent then
    buflen = addnewline2 (level, buffer, buflen)
  end
  buffer[buflen+1] = quotestring (key)
  buffer[buflen+2] = ":"
  return encode2 (value, indent, level, buffer, buflen + 2, tables, globalorder, state)
end

local function appendcustom(res, buffer, state)
  local buflen = state.bufferlen
  if type (res) == 'string' then
    buflen = buflen + 1
    buffer[buflen] = res
  end
  return buflen
end

local function exception(reason, value, state, buffer, buflen, defaultmessage)
  defaultmessage = defaultmessage or reason
  local handler = state.exception
  if not handler then
    return nil, defaultmessage
  else
    state.bufferlen = buflen
    local ret, msg = handler (reason, value, state, defaultmessage)
    if not ret then return nil, msg or defaultmessage end
    return appendcustom(ret, buffer, state)
  end
end

function encodeexception(reason, value, state, defaultmessage)
  return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function (value, indent, level, buffer, buflen, tables, globalorder, state)
  local valtype = type (value)
  local valmeta = getmetatable (value)
  valmeta = type (valmeta) == 'table' and valmeta -- only tables
  local valtojson = valmeta and valmeta.__tojson
  if valtojson then
    if tables[value] then
      return exception('reference cycle', value, state, buffer, buflen)
    end
    tables[value] = true
    state.bufferlen = buflen
    local ret, msg = valtojson (value, state)
    if not ret then return exception('custom encoder failed', value, state, buffer, buflen, msg) end
    tables[value] = nil
    buflen = appendcustom(ret, buffer, state)
  elseif value == nil then
    buflen = buflen + 1
    buffer[buflen] = "null"
  elseif valtype == 'number' then
    local s
    if value ~= value or value >= huge or -value >= huge then
      -- This is the behaviour of the original JSON implementation.
      s = "null"
    else
      s = num2str (value)
    end
    buflen = buflen + 1
    buffer[buflen] = s
  elseif valtype == 'boolean' then
    buflen = buflen + 1
    buffer[buflen] = value and "true" or "false"
  elseif valtype == 'string' then
    buflen = buflen + 1
    buffer[buflen] = quotestring (value)
  elseif valtype == 'table' then
    if tables[value] then
      return exception('reference cycle', value, state, buffer, buflen)
    end
    tables[value] = true
    level = level + 1
    local isa, n = isarray (value)
    if n == 0 and valmeta and valmeta.__jsontype == 'object' then
      isa = false
    end
    local msg
    if isa then -- JSON array
      buflen = buflen + 1
      buffer[buflen] = "["
      for i = 1, n do
        buflen, msg = encode2 (value[i], indent, level, buffer, buflen, tables, globalorder, state)
        if not buflen then return nil, msg end
        if i < n then
          buflen = buflen + 1
          buffer[buflen] = ","
        end
      end
      buflen = buflen + 1
      buffer[buflen] = "]"
    else -- JSON object
      local prev = false
      buflen = buflen + 1
      buffer[buflen] = "{"
      local order = valmeta and valmeta.__jsonorder or globalorder
      if order then
        local used = {}
        n = #order
        for i = 1, n do
          local k = order[i]
          local v = value[k]
          if v then
            used[k] = true
            buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
            prev = true -- add a seperator before the next element
          end
        end
        for k,v in pairs (value) do
          if not used[k] then
            buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
            if not buflen then return nil, msg end
            prev = true -- add a seperator before the next element
          end
        end
      else -- unordered
        for k,v in pairs (value) do
          buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
          if not buflen then return nil, msg end
          prev = true -- add a seperator before the next element
        end
      end
      if indent then
        buflen = addnewline2 (level - 1, buffer, buflen)
      end
      buflen = buflen + 1
      buffer[buflen] = "}"
    end
    tables[value] = nil
  else
    return exception ('unsupported type', value, state, buffer, buflen,
      "type '" .. valtype .. "' is not supported by JSON.")
  end
  return buflen
end

function encode (value, state)
  state = state or {}
  local oldbuffer = state.buffer
  local buffer = oldbuffer or {}
  state.buffer = buffer
  updatedecpoint()
  local ret, msg = encode2 (value, state.indent, state.level or 0,
                   buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state)
  if not ret then
    error (msg, 2)
  elseif oldbuffer == buffer then
    state.bufferlen = ret
    return true
  else
    state.bufferlen = nil
    state.buffer = nil
    return concat (buffer)
  end
end

local function loc (str, where)
  local line, pos, linepos = 1, 1, 0
  while true do
    pos = strfind (str, "\n", pos, true)
    if pos and pos < where then
      line = line + 1
      linepos = pos
      pos = pos + 1
    else
      break
    end
  end
  return "line " .. line .. ", column " .. (where - linepos)
end

local function unterminated (str, what, where)
  return nil, strlen (str) + 1, "unterminated " .. what .. " at " .. loc (str, where)
end

local function scanwhite (str, pos)
  while true do
    pos = strfind (str, "%S", pos)
    if not pos then return nil end
    local sub2 = strsub (str, pos, pos + 1)
    if sub2 == "\239\187" and strsub (str, pos + 2, pos + 2) == "\191" then
      -- UTF-8 Byte Order Mark
      pos = pos + 3
    elseif sub2 == "//" then
      pos = strfind (str, "[\n\r]", pos + 2)
      if not pos then return nil end
    elseif sub2 == "/*" then
      pos = strfind (str, "*/", pos + 2)
      if not pos then return nil end
      pos = pos + 2
    else
      return pos
    end
  end
end

local escapechars = {
  ["\""] = "\"", ["\\"] = "\\", ["/"] = "/", ["b"] = "\b", ["f"] = "\f",
  ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
}

local function unichar (value)
  if value < 0 then
    return nil
  elseif value <= 0x007f then
    return strchar (value)
  elseif value <= 0x07ff then
    return strchar (0xc0 + floor(value/0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0xffff then
    return strchar (0xe0 + floor(value/0x1000),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0x10ffff then
    return strchar (0xf0 + floor(value/0x40000),
                    0x80 + (floor(value/0x1000) % 0x40),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  else
    return nil
  end
end

local function scanstring (str, pos)
  local lastpos = pos + 1
  local buffer, n = {}, 0
  while true do
    local nextpos = strfind (str, "[\"\\]", lastpos)
    if not nextpos then
      return unterminated (str, "string", pos)
    end
    if nextpos > lastpos then
      n = n + 1
      buffer[n] = strsub (str, lastpos, nextpos - 1)
    end
    if strsub (str, nextpos, nextpos) == "\"" then
      lastpos = nextpos + 1
      break
    else
      local escchar = strsub (str, nextpos + 1, nextpos + 1)
      local value
      if escchar == "u" then
        value = tonumber (strsub (str, nextpos + 2, nextpos + 5), 16)
        if value then
          local value2
          if 0xD800 <= value and value <= 0xDBff then
            -- we have the high surrogate of UTF-16. Check if there is a
            -- low surrogate escaped nearby to combine them.
            if strsub (str, nextpos + 6, nextpos + 7) == "\\u" then
              value2 = tonumber (strsub (str, nextpos + 8, nextpos + 11), 16)
              if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
                value = (value - 0xD800)  * 0x400 + (value2 - 0xDC00) + 0x10000
              else
                value2 = nil -- in case it was out of range for a low surrogate
              end
            end
          end
          value = value and unichar (value)
          if value then
            if value2 then
              lastpos = nextpos + 12
            else
              lastpos = nextpos + 6
            end
          end
        end
      end
      if not value then
        value = escapechars[escchar] or escchar
        lastpos = nextpos + 2
      end
      n = n + 1
      buffer[n] = value
    end
  end
  if n == 1 then
    return buffer[1], lastpos
  elseif n > 1 then
    return concat (buffer), lastpos
  else
    return "", lastpos
  end
end

local scanvalue -- forward declaration

local function scantable (what, closechar, str, startpos, nullval, objectmeta, arraymeta)
  local len = strlen (str)
  local tbl, n = {}, 0
  local pos = startpos + 1
  if what == 'object' then
    setmetatable (tbl, objectmeta)
  else
    setmetatable (tbl, arraymeta)
  end
  while true do
    pos = scanwhite (str, pos)
    if not pos then return unterminated (str, what, startpos) end
    local char = strsub (str, pos, pos)
    if char == closechar then
      return tbl, pos + 1
    end
    local val1, err
    val1, pos, err = scanvalue (str, pos, nullval, objectmeta, arraymeta)
    if err then return nil, pos, err end
    pos = scanwhite (str, pos)
    if not pos then return unterminated (str, what, startpos) end
    char = strsub (str, pos, pos)
    if char == ":" then
      if val1 == nil then
        return nil, pos, "cannot use nil as table index (at " .. loc (str, pos) .. ")"
      end
      pos = scanwhite (str, pos + 1)
      if not pos then return unterminated (str, what, startpos) end
      local val2
      val2, pos, err = scanvalue (str, pos, nullval, objectmeta, arraymeta)
      if err then return nil, pos, err end
      tbl[val1] = val2
      pos = scanwhite (str, pos)
      if not pos then return unterminated (str, what, startpos) end
      char = strsub (str, pos, pos)
    else
      n = n + 1
      tbl[n] = val1
    end
    if char == "," then
      pos = pos + 1
    end
  end
end

scanvalue = function (str, pos, nullval, objectmeta, arraymeta)
  pos = pos or 1
  pos = scanwhite (str, pos)
  if not pos then
    return nil, strlen (str) + 1, "no valid JSON value (reached the end)"
  end
  local char = strsub (str, pos, pos)
  if char == "{" then
    return scantable ('object', "}", str, pos, nullval, objectmeta, arraymeta)
  elseif char == "[" then
    return scantable ('array', "]", str, pos, nullval, objectmeta, arraymeta)
  elseif char == "\"" then
    return scanstring (str, pos)
  else
    local pstart, pend = strfind (str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
    if pstart then
      local number = str2num (strsub (str, pstart, pend))
      if number then
        return number, pend + 1
      end
    end
    pstart, pend = strfind (str, "^%a%w*", pos)
    if pstart then
      local name = strsub (str, pstart, pend)
      if name == "true" then
        return true, pend + 1
      elseif name == "false" then
        return false, pend + 1
      elseif name == "null" then
        return nullval, pend + 1
      end
    end
    return nil, pos, "no valid JSON value at " .. loc (str, pos)
  end
end

local function optionalmetatables(...)
  if select("#", ...) > 0 then
    return ...
  else
    return {__jsontype = 'object'}, {__jsontype = 'array'}
  end
end

function decode (str, pos, nullval, ...)
  local objectmeta, arraymeta = optionalmetatables(...)
  return scanvalue (str, pos, nullval, objectmeta, arraymeta)
end




--[[-------------------------------------------------------------------------
Module loading
---------------------------------------------------------------------------]]

--[[local function recursiveLoad(str)
	local files, dirs = file.Find(str .. "/*", "LUA")
	for k,v in pairs(files) do
		include(str .. "/" .. v)
	end
	for k,v in pairs(dirs) do
		recursiveLoad(str .. "/" .. v)
	end
end

hook.Add("Initialize", "discord_core-init", function()
	recursiveLoad("discord_relay")
	print("Loaded Sirro's discord relay...")
end)]]--