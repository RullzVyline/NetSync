--!strict
-- NetSync Tutorial
-- Basic usage examples for NetSync.
-- Put the NetSync folder inside ReplicatedStorage.

-- 1. REQUIRE THE LIBRARY
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage:WaitForChild("NetSync"))

-- ======================================================================
-- 2. DEFINE SCHEMA 
-- ======================================================================

-- Example A: Simple player damage packet
local PlayerDamageSchema = NetSync.Types.Struct({
	TargetId = NetSync.Types.U32,      
	Damage = NetSync.Types.F32,        
	IsCritical = NetSync.Types.Boolean,
	WeaponType = NetSync.Types.String  
})

-- Register Packet
local DamagePacket = NetSync.Packet("DamagePlayer", PlayerDamageSchema)


-- Example B: Array Payload (Use instead of dynamic dictionaries)
local WorldStateSchema = NetSync.Types.Array(
	NetSync.Types.Struct({
		EntityId = NetSync.Types.U16, 
		Position = NetSync.Types.CFrame
	})
)

local WorldStatePacket = NetSync.Packet("SpawnWorld", WorldStateSchema)


-- ======================================================================
-- 3. LISTENING FOR EVENTS
-- ======================================================================
DamagePacket.Listen(function(player, data)
	-- Client: `player` argument will be `data`, and `data` will be nil
	-- Server: `player` is the Player, `data` is your schema Struct
	
	local safeData = typeof(player) == "Instance" and data or player
	local safePlayer = typeof(player) == "Instance" and player or nil
	
	print(`{safePlayer and safePlayer.Name or "Server"} fired Damage!`)
	print(`Target: {safeData.TargetId}, Amount: {safeData.Damage}, Wpn: {safeData.WeaponType}`)
end)


-- ======================================================================
-- 4. SENDING PACKETS
-- Packets are queued and sent in batches at the end of the frame.
-- ======================================================================

-- FireServer Example:
-- DamagePacket.FireServer({
-- 	TargetId = 1234567,
-- 	Damage = 45.2,
-- 	IsCritical = true,
-- 	WeaponType = "Excalibur"
-- })

-- FireAllClients Example (Array of Structs):
-- local massivePayload = {}
-- for i = 1, 100 do
-- 	table.insert(massivePayload, {
-- 		EntityId = i,
-- 		Position = CFrame.new(0, 50, 0)
-- 	})
-- end
-- WorldStatePacket.FireAllClients(massivePayload)
