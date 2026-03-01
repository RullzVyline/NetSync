# NetSync V2

<div align="center">
  <img src="logo.png" alt="NetSync Logo" width="300" />
</div>

*[Baca dalam Bahasa Indonesia](README_id.md)*

A high-performance, strictly-typed networking framework for Roblox. NetSync V2 abandons traditional data tables and moves entirely to **zero-allocation binary buffer serialization**, creating a massively secure and fast environment for handling thousands of packets per second.

## Core Features
- **Strict Network Schemas:** Packets must have pre-defined strict data schemas (e.g., U8, F32, Array, Struct). This completely eliminates Lua tables during network transit.
- **Zero-Allocation Buffers:** Reads and writes binary data to a single continuously reused dynamic buffer. No garbage collection spikes.
- **Payload Batching:** Queues all `Fire` calls and compresses them into a single packet per frame via `RunService.Heartbeat`.
- **Advanced Hash Generation:** Uses a robust FNV-1a 32-bit hash algorithm instead of strings for packet IDs, guaranteeing zero collisions.
- **Exploit & DDoS Protection:** Enforces strict server-side rate limits (Token-Bucket algorithm), guards against Buffer Overflows (65535 byte string limits), safely ignores corrupted chunks with size prefixing, and wraps all bridge logic in `pcall`.

## Usage & API

### 1. Installation
Place the `NetSync` folder (containing `init.luau`, `Serializer.luau`, and `Types.luau`) into `ReplicatedStorage`. 

### 2. Defining Schemas
Unlike normal `RemoteEvents`, you must define exactly what your data looks like for the Binary Serializer.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage:WaitForChild("NetSync"))

local PlayerDamageSchema = NetSync.Types.Struct({
    TargetId = NetSync.Types.U32,      
    Damage = NetSync.Types.F32,        
    IsCritical = NetSync.Types.Boolean,
    WeaponType = NetSync.Types.String  
})

-- Register Packet
local DamagePacket = NetSync.Packet("DamagePlayer", PlayerDamageSchema)
```

### 3. Server-Side
```lua
-- Optional: Configure the limit (Default is 200 packets per second, punishes by Drop)
NetSync.ConfigureRateLimit({
    MaxRequestsPerSecond = 200,
    Punishment = "Drop" -- "Drop" | "Kick"
})

-- Listen for an event
local disconnect = DamagePacket.Listen(function(player, data)
    print(`Received damage: {data.Damage} from {player.Name}`)
    -- Fire back to the client
    DamagePacket.FireClient(player, data)
end)

-- To prevent memory leaks on destroyed objects:
-- disconnect() 
```

### 4. Client-Side
```lua
-- Listen for an event from Server
DamagePacket.Listen(function(player, data)
    -- On the Client, the first argument 'player' receives the 'data'.
    -- It's recommended to handle arguments cleanly as shown in NetSync_Tutorial.luau
    print(`Server confirmed damage!`)
end)

-- Fire an event (automatically queued and batched at Heartbeat)
DamagePacket.FireServer({
    TargetId = 1234567,
    Damage = 45.2,
    IsCritical = true,
    WeaponType = "Excalibur"
})
```

## Available Schema Types (`NetSync.Types`)
- `U8`, `U16`, `U32` (Unsigned Integers)
- `I8`, `I16`, `I32` (Signed Integers)
- `F32`, `F64` (Floats / Decimals)
- `Boolean`
- `String` (Max length 65535 bytes)
- `Vector3`
- `CFrame`
- `Array(innerType)`
- `Struct({ [string] = innerType })`
