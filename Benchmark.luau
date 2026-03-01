--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage.NetSync)

local IS_SERVER = RunService:IsServer()

-- =========================================================
-- NETSYNC V1.5 STRESS TEST & BENCHMARK SUITE
-- Goal: 50 players sending 60hz updates simultaneously
-- =========================================================

if IS_SERVER then
	NetSync.configureRateLimit({
		MaxRequestsPerSecond = 50000, -- Disable anti-spam limit for pure stress testing
		Punishment = "Drop"
	})

	local totalDataCalls = 0
	local lastTime = os.clock()

	NetSync.listen("BotPositionUpdate", function(player, data)
		totalDataCalls += 1
	end)
	
	NetSync.listen("BotCombatUpdate", function(player, data)
		totalDataCalls += 1
	end)

	RunService.Heartbeat:Connect(function()
		local current = os.clock()
		--- Print results every 1 second
		if current - lastTime >= 1 then
			print(`[NetSync Server Benchmark] Processed {totalDataCalls} events over 1 second.`)
			totalDataCalls = 0
			lastTime = current
		end
	end)

else
	-- CLIENT: Simulated Bots
	task.spawn(function()
		task.wait(2)
		local BOTS_COUNT = 50
		print(`[NetSync Client Benchmark] Starting stress test with {BOTS_COUNT} simulated players...`)
		
		RunService.Heartbeat:Connect(function()
			for i = 1, BOTS_COUNT do
				-- Simulate 60Hz high-frequency movement replication
				NetSync.fire("BotPositionUpdate", {
					x = math.random() * 100,
					y = math.random() * 100,
					z = math.random() * 100
				})
				
				-- Simulate occasional combat event
				if math.random() > 0.9 then
					NetSync.fire("BotCombatUpdate", {
						targetId = "Enemy_" .. tostring(math.random(1, 10)),
						damage = 15
					})
				end
			end
		end)
	end)
end
