# discord.glua
An API wrapper for Discord written in the Garry's Mod Lua Environment. [WIP]


# Documentation



### Client Discord.Objects.Client( string UniqueID )
discord.glua is object oriented. This is so you can make multiple bot users running simultaneously. This method allows you to create a new client instance or reference it by calling this method again using the UniqueID passed along.

## Client Object


### string Client:getStatus()
Returns the status of the Client, can be "off", "reconnect", "reconnect-resume", "active", "stopping".
### boolean Client:isActive()
Returns true if the client instance is currently connected to Discord.
### string Client:getToken()
Returns the set token for the discord Client. (must be set first!)
### table Client:getGuilds()
Returns a table of Guild objects, these are all the guilds the discord client is added to.
### Guild Client:getGuild( string GuildID/GuildName )
Accepts a string of either the ID of the guild or the name of the guild. If the Client is added to this guild it will return it's object.
### void Client:setToken( string Token )
Set the bot token of which you want to use with this method. You **must** do this before initalizing a connection!
### void Client:start()
Attempts to start and maintain a connection to Discord. You **must** set the token beforehand!
### void Client:stop()
Shuts down the connection to Discord.
### void Client:updateSelf( string Status-Name, number Type, string Status-Type )
Updates the profile display of the bot. The type and status-type values are as follows:
* Type:
  * 0: Playing
  * 1: Live on Twitch (idk how this works)
  * 2: Listening to
  * 3: Watching
* Status-Type:
  * dnd: Do Not Disturb (red)
  * idle: Idle status (yellow)
  * online: Online (green)
  * offline: Offline (invisible)
### void Client:addEvent( string EventName, function Callback)
This is an important function which allows you to hook your code onto events that happen on discord. The function passed in the 2nd argument will be called whenever the event takes place. The Client object will **always** be passed as the first argument in the callback function, followed by any other object depending on the event. Here all the events you're able to register:
Event Name | Objects Passed | Description
------------ | ------------ | -------------
HELLO | Null | Discord first opens a connection, this is before authentication.
RECONNECT | Null | Discord is requesting the Client to close and open a new connection. (This will be automatically handled internally.)
READY | Null | After succesfully authenticating with discord, this will be called when the connection is initalize and active.
RESUMED | Null | Follows after RECONNECT and when the reconnection to discord is successful.
GUILD_CREATE | Guild | When a guild is loaded in after lazy-load, or a guild became avaliable after a outage, or the Client joined a new guild. 
GUILD_UPDATE | Guild | When a change is made to a guild (ex. name, icon, etc), this event will pass store and pass the new guild with the updated changes.
GUILD_DELETE | Null | When a Client leaves a guild or a guild is made unavalible by an outage.
GUILD_BAN_ADD | number | When a member is banned from a discord, their ID will be passed through this function.
GUILD_BAN_REMOVE | Null | When a member is unbanned from the discord.
CHANNEL_CREATE | Channel | When a channel is created in a discord or a new DM channel is opened. That channel will be passed.
CHANNEL_UPDATE | Channel | When a channel is updated.
CHANNEL_DELETE | Null | When a channel is deleted.
GUILD_MEMBER_ADD | Member | When a user joins a guild.
GUILD_MEMBER_UPDATE | Member | When something is change in a user in a guild (ex. nickname, roles, avatar).
GUILD_MEMBER_REMOVE | Null | When a user leaves a guild.
GUILD_MEMBERS_CHUNK | table | Usually chunk-loading happens with large servers or when you request members, this will return a table of Members from a spesific guild.
USER_UPDATE | Client | When the current Client is updated (name, avatar, etc).
MESSAGE_CREATE | Message | When a new message is posted to a guild or DM.
MESSAGE_UPDATE | Message | When a message is edited.
MESSAGE_DELETE | Null | When a message is deleted from a guild or DM.
MESSAGE_BULK_DELETE | Null | Usually done with things like bot purge commands, this is when multiple messages are deleted at once.
MESSAGE_REACTION_ADD | Null | Not implemented yet.
GUILD_ROLE_CREATE | Role | When a new role is created in a guild.
GUILD_ROLE_UPDATE | Role | When a role is updated in a guild.
GUILD_ROLE_DELETE | Null | When a role is deleted in a guild.

