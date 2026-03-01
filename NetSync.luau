--!strict
-- NetSync (V1.5)
-- Production-Ready Networking Framework with Identifier Compression.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local IS_SERVER = RunService:IsServer()

export type RateLimitConfig = {
	MaxRequestsPerSecond: number,
	Punishment: "Drop" | "Kick",
}

local NetSync = {}
NetSync._listeners = {} :: { [number]: (...any) -> () }

-- DJB2 Hash: Compresses any string (e.g. "WeaponFire") into a predictable 16-bit integer (0-65535)
-- This saves enormous bandwidth by avoiding string transmission over the network.
local function getEventId(eventName: string): number
	local hash = 5381
	for i = 1, #eventName do
		hash = (hash * 33) + string.byte(eventName, i)
	end
	return hash % 65536
end

if IS_SERVER then
	NetSync._rateLimits = {} :: { [Player]: { _lastTick: number, _count: number } }
	NetSync._config = { MaxRequestsPerSecond = 20, Punishment = "Drop" } :: RateLimitConfig

	local RemoteEvent = ReplicatedStorage:FindFirstChild("NetSync_Bridge")
	if not RemoteEvent then
		RemoteEvent = Instance.new("RemoteEvent")
		RemoteEvent.Name = "NetSync_Bridge"
		RemoteEvent.Parent = ReplicatedStorage
	end

	RemoteEvent.OnServerEvent:Connect(function(player: Player, packet: any)
		if type(packet) ~= "table" then return end

		if not NetSync._rateLimits[player] then
			NetSync._rateLimits[player] = { _lastTick = os.clock(), _count = 0 }
		end

		local rateData = NetSync._rateLimits[player]
		local currentTick = os.clock()
		
		if currentTick - rateData._lastTick > 1 then
			rateData._count = 0
			rateData._lastTick = currentTick
		end
		
		-- In V1.5, each nested array is a request. Rate limit by length of the batched packet.
		rateData._count += #packet
		if rateData._count > NetSync._config.MaxRequestsPerSecond then
			if NetSync._config.Punishment == "Kick" then
				player:Kick("NetSync: Rate limit exceeded.")
			end
			return
		end

		for _, dataPair in ipairs(packet) do
			if type(dataPair) == "table" and #dataPair == 2 then
				local eventId = dataPair[1]
				local payload = dataPair[2]
				
				local listener = NetSync._listeners[eventId]
				if listener then
					task.spawn(listener, player, payload)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		NetSync._rateLimits[player] = nil
	end)

	function NetSync.fire(player: Player, eventName: string, data: any)
		RemoteEvent:FireClient(player, { {getEventId(eventName), data} })
	end

	function NetSync.fireAll(eventName: string, data: any)
		RemoteEvent:FireAllClients({ {getEventId(eventName), data} })
	end

	function NetSync.configureRateLimit(config: RateLimitConfig)
		NetSync._config = config
	end

else
	NetSync._outgoingQueue = {} :: { {any} }

	local RemoteEvent = ReplicatedStorage:WaitForChild("NetSync_Bridge", 10) :: RemoteEvent
	if not RemoteEvent then
		error("NetSync Client: 'NetSync_Bridge' remote not found.")
	end

	RemoteEvent.OnClientEvent:Connect(function(packet: any)
		if type(packet) ~= "table" then return end
		
		for _, dataPair in ipairs(packet) do
			if type(dataPair) == "table" and #dataPair == 2 then
				local eventId = dataPair[1]
				local payload = dataPair[2]
				
				local listener = NetSync._listeners[eventId]
				if listener then
					task.spawn(listener, payload)
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		if #NetSync._outgoingQueue == 0 then return end 
		
		local packetToSend = NetSync._outgoingQueue
		NetSync._outgoingQueue = {} 
		
		RemoteEvent:FireServer(packetToSend)
	end)

	function NetSync.fire(eventName: string, data: any)
		table.insert(NetSync._outgoingQueue, {getEventId(eventName), data})
	end
end

function NetSync.listen(eventName: string, callback: (...any) -> ())
	NetSync._listeners[getEventId(eventName)] = callback
end

return NetSync
