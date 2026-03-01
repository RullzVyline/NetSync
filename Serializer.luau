--!strict
-- NetSync Serializer

local Types = require(script.Parent.Types)

local Serializer = {}

local writeBuffer = buffer.create(2 * 1024 * 1024) 
local writeCursor = 0
local bufferSize = 2 * 1024 * 1024

function Serializer.resetWriteCursor()
	writeCursor = 0
end

function Serializer.getPayloadString(): string
	local fullStr = buffer.tostring(writeBuffer)
	return string.sub(fullStr, 1, writeCursor)
end

function Serializer.getWriteCursor(): number
	return writeCursor
end

function Serializer.setU16(position: number, value: number)
	assert(position >= 0 and position + 2 <= buffer.len(writeBuffer), "NetSync Serializer: setU16 position out of bounds")
	buffer.writeu16(writeBuffer, position, value)
end

-- internal function to prevent out-of-bounds error
local function ensureCapacity(additionalBytes: number)
	if writeCursor + additionalBytes > bufferSize then
		local newSize = bufferSize * 2
		local newBuffer = buffer.create(newSize)
		buffer.copy(newBuffer, 0, writeBuffer, 0, writeCursor)
		writeBuffer = newBuffer
		bufferSize = newSize
	end
end

-- Binary Writer
function Serializer.write(netType: Types.NetType, value: any)
	local t = netType.__type

	if t == "U8" then
		ensureCapacity(1)
		buffer.writeu8(writeBuffer, writeCursor, value)
		writeCursor += 1
	elseif t == "U16" then
		ensureCapacity(2)
		buffer.writeu16(writeBuffer, writeCursor, value)
		writeCursor += 2
	elseif t == "U32" then
		ensureCapacity(4)
		buffer.writeu32(writeBuffer, writeCursor, value)
		writeCursor += 4
	elseif t == "I8" then
		ensureCapacity(1)
		buffer.writei8(writeBuffer, writeCursor, value)
		writeCursor += 1
	elseif t == "I16" then
		ensureCapacity(2)
		buffer.writei16(writeBuffer, writeCursor, value)
		writeCursor += 2
	elseif t == "I32" then
		ensureCapacity(4)
		buffer.writei32(writeBuffer, writeCursor, value)
		writeCursor += 4
	elseif t == "F32" then
		ensureCapacity(4)
		buffer.writef32(writeBuffer, writeCursor, value)
		writeCursor += 4
	elseif t == "F64" then
		ensureCapacity(8)
		buffer.writef64(writeBuffer, writeCursor, value)
		writeCursor += 8
	elseif t == "Boolean" then
		ensureCapacity(1)
		buffer.writeu8(writeBuffer, writeCursor, value and 1 or 0)
		writeCursor += 1
	elseif t == "String" then
		local len = #value
		assert(len <= 65535, "NetSync: String exceeds max length of 65535 bytes")
		ensureCapacity(2 + len)
		buffer.writeu16(writeBuffer, writeCursor, len) 
		writeCursor += 2
		buffer.writestring(writeBuffer, writeCursor, value)
		writeCursor += len
	elseif t == "Vector3" then
		ensureCapacity(12)
		buffer.writef32(writeBuffer, writeCursor, value.X)
		buffer.writef32(writeBuffer, writeCursor + 4, value.Y)
		buffer.writef32(writeBuffer, writeCursor + 8, value.Z)
		writeCursor += 12
	elseif t == "CFrame" then
		ensureCapacity(24)
		local x, y, z = value.X, value.Y, value.Z
		local rx, ry, rz = value:ToEulerAnglesYXZ()
		buffer.writef32(writeBuffer, writeCursor, x)
		buffer.writef32(writeBuffer, writeCursor + 4, y)
		buffer.writef32(writeBuffer, writeCursor + 8, z)
		buffer.writef32(writeBuffer, writeCursor + 12, rx)
		buffer.writef32(writeBuffer, writeCursor + 16, ry)
		buffer.writef32(writeBuffer, writeCursor + 20, rz)
		writeCursor += 24
	elseif t == "Array" then
		local len = #value
		ensureCapacity(2)
		buffer.writeu16(writeBuffer, writeCursor, len) 
		writeCursor += 2

		for i = 1, len do
			Serializer.write(netType.inner :: Types.NetType, value[i])
		end
	elseif t == "Struct" then
		local keys = netType.keys :: {string}
		local schema = netType.schema :: {[string]: Types.NetType}

		for _, key in ipairs(keys) do
			Serializer.write(schema[key], value[key])
		end
	end
end

-- Binary Reader
function Serializer.read(readBuf: buffer, readCursor: number, netType: Types.NetType): (any, number)
	local t = netType.__type

	if t == "U8" then
		local v = buffer.readu8(readBuf, readCursor)
		return v, readCursor + 1
	elseif t == "U16" then
		local v = buffer.readu16(readBuf, readCursor)
		return v, readCursor + 2
	elseif t == "U32" then
		local v = buffer.readu32(readBuf, readCursor)
		return v, readCursor + 4
	elseif t == "I8" then
		local v = buffer.readi8(readBuf, readCursor)
		return v, readCursor + 1
	elseif t == "I16" then
		local v = buffer.readi16(readBuf, readCursor)
		return v, readCursor + 2
	elseif t == "I32" then
		local v = buffer.readi32(readBuf, readCursor)
		return v, readCursor + 4
	elseif t == "F32" then
		local v = buffer.readf32(readBuf, readCursor)
		return v, readCursor + 4
	elseif t == "F64" then
		local v = buffer.readf64(readBuf, readCursor)
		return v, readCursor + 8
	elseif t == "Boolean" then
		local v = buffer.readu8(readBuf, readCursor)
		return (v == 1), readCursor + 1
	elseif t == "String" then
		local len = buffer.readu16(readBuf, readCursor)
		readCursor += 2
		local v = buffer.readstring(readBuf, readCursor, len)
		return v, readCursor + len
	elseif t == "Vector3" then
		local x = buffer.readf32(readBuf, readCursor)
		local y = buffer.readf32(readBuf, readCursor + 4)
		local z = buffer.readf32(readBuf, readCursor + 8)
		return Vector3.new(x, y, z), readCursor + 12
	elseif t == "CFrame" then
		local x = buffer.readf32(readBuf, readCursor)
		local y = buffer.readf32(readBuf, readCursor + 4)
		local z = buffer.readf32(readBuf, readCursor + 8)
		local rx = buffer.readf32(readBuf, readCursor + 12)
		local ry = buffer.readf32(readBuf, readCursor + 16)
		local rz = buffer.readf32(readBuf, readCursor + 20)
		return CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(rx, ry, rz), readCursor + 24
	elseif t == "Array" then
		local len = buffer.readu16(readBuf, readCursor)
		readCursor += 2

		local arr = table.create(len)
		local innerType = netType.inner :: Types.NetType
		for i = 1, len do
			local val, nc = Serializer.read(readBuf, readCursor, innerType)
			arr[i] = val
			readCursor = nc
		end

		return arr, readCursor
	elseif t == "Struct" then
		local keys = netType.keys :: {string}
		local schema = netType.schema :: {[string]: Types.NetType}

		local struct = {}
		for _, key in ipairs(keys) do
			local val, nc = Serializer.read(readBuf, readCursor, schema[key])
			struct[key] = val
			readCursor = nc
		end

		return struct, readCursor
	end

	error("NetSync Serializer: Unknown DataType " .. tostring(t))
	return nil, readCursor
end

return Serializer