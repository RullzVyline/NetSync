# NetSync

*[Baca dalam Bahasa Indonesia](README_id.md)*

A single-module networking framework for Roblox. It implements a single RemoteEvent architecture with payload batching and token-bucket rate limiting.

## Features
- **Strict Typing:** Written in strict Luau.
- **Identifier Compression:** Automatically hashes string event names into 16-bit integers via DJB2, slashing bandwidth usage.
- **Payload Batching:** Queues outgoing requests and fires them collectively at the end of the frame via `RunService.Heartbeat`.
- **Rate Limiting:** Server-side token-bucket algorithm to manage incoming request frequencies per player.
- **Single-Remote Architecture:** Routes all traffic through one dynamically created `RemoteEvent`.

## Performance Benchmarks (V1.5)
In a rigorous 50-player simulated stress test generating heavy combat and positional data (over 3,300+ incoming requests per second):
- **Server CPU Time:** Maintained a stable ~16.1ms (60 FPS threshold) inside Roblox Studio.
- **Total DataCost:** Efficiently compressed 3,300+ events/sec into just ~161 KB/s of total bandwidth.
- **Network Ping:** Held steady at 0-15ms, with zero packet-queue bottlenecking.

## Usage

### 1. Installation
Place the `NetSync.luau` ModuleScript into `ReplicatedStorage`. 

### 2. Examples

**Server Example**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage.NetSync)

-- Optional: Configure the limit defaults to 20 req/s
NetSync.configureRateLimit({
    MaxRequestsPerSecond = 30,
    Punishment = "Drop" -- "Drop" | "Kick"
})

-- Listen for an event
NetSync.listen("WeaponFire", function(player, data)
    print(`Received weapon data from {player.Name}`)
    NetSync.fire(player, "HitConfirmation", { target = data.target })
end)
```

**Client Example**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage.NetSync)

-- Listen for server events
NetSync.listen("HitConfirmation", function(data)
    print(`Server confirmed hit on: {data.target}`)
end)

-- Fire an event (automatically batched)
NetSync.fire("WeaponFire", { target = "Model1" })
NetSync.fire("UpdatePosition", { x = 10, y = 20 })
```

## API Reference

### `NetSync` (Shared)
- `listen(eventName: string, callback: (...any) -> ())`: Attaches a listener.

### `NetSync` (Server-only APIs)
- `fire(player: Player, eventName: string, data: any)`: Sends a payload to a specific player.
- `fireAll(eventName: string, data: any)`: Sends a payload to all players.
- `configureRateLimit(config: RateLimitConfig)`: Updates rate limit configuration.

### `NetSync` (Client-only APIs)
- `fire(eventName: string, data: any)`: Queues a payload to be sent to the server on the next frame.
