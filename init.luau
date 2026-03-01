--!strict
-- NetSync
-- Networking Library

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(script.Types)
local Serializer = require(script.Serializer)

local NetSync = {}
NetSync.Types = Types

type PacketConfig = {
	Name: string,
	Schema: Types.NetType,
}

local packetRegistry = {} :: { [number]: {config: PacketConfig, listeners: {(any, any) -> ()}, packetObj: any} }

export type RateLimitConfig = {
	MaxRequestsPerSecond: number,
	Punishment: "Drop" | "Kick",
}

export type PacketObject<T> = {
	Listen: (callback: (player: Player, data: T) -> ()) -> (() -> ()),
	FireClient: (player: Player, data: T) -> (),
	FireAllClients: (data: T) -> (),
	FireServer: (data: T) -> (),
}

-- Menggunakan Hash yang lebih aman (FNV-1a 32-bit) untuk mencegah bentrokan (collision)
local function getEventId(eventName: string): number
	local hash = 2166136261
	for i = 1, #eventName do
		hash = bit32.bxor(hash, string.byte(eventName, i))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

-- ==========================================================
-- Packet Interface
-- ==========================================================
function NetSync.Packet(name: string, schema: Types.NetType)
	local id = getEventId(name)

	if packetRegistry[id] then
		return packetRegistry[id].packetObj
	end

	local listeners = {}
	local packetObj = {}

	function packetObj.Listen(callback: (any, any) -> ())
		table.insert(listeners, callback)
		return function()
			local idx = table.find(listeners, callback)
			if idx then table.remove(listeners, idx) end
		end
	end

	function packetObj.FireClient(player: Player, data: any)
		if not RunService:IsServer() then error("FireClient (NetSync) can only be called from Server") end
		NetSync._queueForPlayer(player, id, schema, data)
	end

	function packetObj.FireAllClients(data: any)
		if not RunService:IsServer() then error("FireAllClients (NetSync) can only be called from Server") end
		for _, player in ipairs(Players:GetPlayers()) do
			NetSync._queueForPlayer(player, id, schema, data)
		end
	end

	function packetObj.FireServer(data: any)
		if not RunService:IsClient() then error("FireServer (NetSync) can only be called from Client") end
		NetSync._queueForServer(id, schema, data)
	end

	packetRegistry[id] = {
		config = { Name = name, Schema = schema },
		listeners = listeners,
		packetObj = packetObj
	}

	return packetObj
end

-- ==========================================================
-- Queueing & Batching
-- ==========================================================
local serverQueues = {} :: { [Player]: { {id: number, schema: Types.NetType, data: any} } }
local clientQueue = {} :: { {id: number, schema: Types.NetType, data: any} }

function NetSync._queueForPlayer(player: Player, packetId: number, schema: Types.NetType, data: any)
	if not serverQueues[player] then serverQueues[player] = {} end
	table.insert(serverQueues[player], {id = packetId, schema = schema, data = data})
end

function NetSync._queueForServer(packetId: number, schema: Types.NetType, data: any)
	table.insert(clientQueue, {id = packetId, schema = schema, data = data})
end

-- ==========================================================
-- Remote Bridge
-- ==========================================================
local RemoteEvent

if RunService:IsServer() then

	-- Rate Limit State (Moved securely to Server Scope)
	local rateLimits = {} :: { [Player]: { _lastTick: number, _count: number } }
	NetSync._config = { MaxRequestsPerSecond = 200, Punishment = "Drop" } :: RateLimitConfig

	function NetSync.ConfigureRateLimit(config: RateLimitConfig)
		NetSync._config = config
	end

	RemoteEvent = ReplicatedStorage:FindFirstChild("NetSync_BridgeV2")
	if not RemoteEvent then
		RemoteEvent = Instance.new("RemoteEvent")
		RemoteEvent.Name = "NetSync_BridgeV2"
		RemoteEvent.Parent = ReplicatedStorage
	end

	RunService.Heartbeat:Connect(function()
		local queuesSnapshot = serverQueues
		serverQueues = {}

		for player, queue in pairs(queuesSnapshot) do
			if #queue > 0 then
				Serializer.resetWriteCursor()
				Serializer.write(Types.U16, #queue)

				for _, call in ipairs(queue) do
					Serializer.write(Types.U32, call.id) -- Berubah jadi U32 untuk FNV-1a Hash

					-- Tulis placeholder size
					local sizeStart = Serializer.getWriteCursor()
					Serializer.write(Types.U16, 0)

					Serializer.write(call.schema, call.data)

					-- Hitung selisih byte size dan overwrite placeholder size
					local sizeEnd = Serializer.getWriteCursor()
					Serializer.setU16(sizeStart, sizeEnd - sizeStart - 2)
				end

				local batchedPayloadString = Serializer.getPayloadString()
				RemoteEvent:FireClient(player, batchedPayloadString)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		serverQueues[player] = nil
		rateLimits[player] = nil
	end)

	RemoteEvent.OnServerEvent:Connect(function(player: Player, payloadString: any)
		if type(payloadString) ~= "string" then return end

		local ok, err = pcall(function()
			-- Rate Limiting Logic
			if not rateLimits[player] then
				rateLimits[player] = { _lastTick = os.clock(), _count = 0 }
			end

			local rateData = rateLimits[player]
			local currentTick = os.clock()

			if currentTick - rateData._lastTick > 1 then
				rateData._count = 0
				rateData._lastTick = currentTick
			end

			local readBuf = buffer.fromstring(payloadString)
			local cursor = 0
			local packetCount = buffer.readu16(readBuf, cursor)
			cursor += 2

			-- Check rate limit based on packet count inside the batch
			rateData._count += packetCount
			if rateData._count > NetSync._config.MaxRequestsPerSecond then
				if NetSync._config.Punishment == "Kick" then
					player:Kick("NetSync: Rate limit exceeded. Possible packet spam detected.")
				end
				return -- Drop the entire batch
			end

			for i = 1, packetCount do
				local packetId = buffer.readu32(readBuf, cursor)
				cursor += 4

				local payloadSize = buffer.readu16(readBuf, cursor)
				cursor += 2

				local reg = packetRegistry[packetId]
				if reg then
					local data, newCursor = Serializer.read(readBuf, cursor, reg.config.Schema)
					cursor = newCursor

					for _, listener in ipairs(reg.listeners) do
						task.spawn(listener, player, data)
					end
				else
					warn("NetSync: Unregistered Packet ID:", packetId)
					-- Aman: Lompati array byte dari packet asing ini agar sisa antrean batch tidak ikut corrupt
					cursor += payloadSize
					continue
				end
			end
		end)

		if not ok then
			warn(`NetSync: Malformed payload caught from {player.Name} - {err}`)
		end
	end)

else -- CLIENT
	RemoteEvent = ReplicatedStorage:WaitForChild("NetSync_BridgeV2")

	-- BUG FIX: RenderStepped is not allowed in ModuleScripts running conceptually outside the camera scope. Use Heartbeat.
	RunService.Heartbeat:Connect(function()
		local queuesSnapshot = clientQueue
		clientQueue = {}

		if #queuesSnapshot > 0 then
			Serializer.resetWriteCursor()
			Serializer.write(Types.U16, #queuesSnapshot)

			for _, call in ipairs(queuesSnapshot) do
				Serializer.write(Types.U32, call.id)

				local sizeStart = Serializer.getWriteCursor()
				Serializer.write(Types.U16, 0)

				Serializer.write(call.schema, call.data)

				local sizeEnd = Serializer.getWriteCursor()
				Serializer.setU16(sizeStart, sizeEnd - sizeStart - 2)
			end

			local batchedPayloadString = Serializer.getPayloadString()
			RemoteEvent:FireServer(batchedPayloadString)
		end
	end)

	RemoteEvent.OnClientEvent:Connect(function(payloadString: any)
		if type(payloadString) ~= "string" then return end

		local ok, err = pcall(function()
			local readBuf = buffer.fromstring(payloadString)
			local cursor = 0

			local packetCount = buffer.readu16(readBuf, cursor)
			cursor += 2

			for i = 1, packetCount do
				local packetId = buffer.readu32(readBuf, cursor)
				cursor += 4

				local payloadSize = buffer.readu16(readBuf, cursor)
				cursor += 2

				local reg = packetRegistry[packetId]
				if reg then
					local data, newCursor = Serializer.read(readBuf, cursor, reg.config.Schema)
					cursor = newCursor

					for _, listener in ipairs(reg.listeners) do
						task.spawn(listener, data)
					end
				else
					warn("NetSync: Unregistered Packet ID:", packetId)
					cursor += payloadSize
					continue
				end
			end
		end)

		if not ok then
			warn(`NetSync: Client encountered malformed payload from Server: {err}`)
		end
	end)
end

return NetSync