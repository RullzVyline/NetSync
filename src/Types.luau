--!strict
-- NetSync Types

local Types = {}

export type NetType = {
	__type: string,
	inner: NetType?,
	schema: { [string]: NetType }?,
	keys: { string }?, 
}

Types.U8 = { __type = "U8" } :: NetType
Types.U16 = { __type = "U16" } :: NetType
Types.U32 = { __type = "U32" } :: NetType
Types.I8 = { __type = "I8" } :: NetType
Types.I16 = { __type = "I16" } :: NetType
Types.I32 = { __type = "I32" } :: NetType
Types.F32 = { __type = "F32" } :: NetType
Types.F64 = { __type = "F64" } :: NetType
Types.Boolean = { __type = "Boolean" } :: NetType
Types.String = { __type = "String" } :: NetType
Types.Vector3 = { __type = "Vector3" } :: NetType
Types.CFrame = { __type = "CFrame" } :: NetType

-- Array type
function Types.Array(innerType: NetType): NetType
	return {
		__type = "Array",
		inner = innerType
	} :: any
end

-- Struct type
function Types.Struct(schema: { [string]: NetType }): NetType
	local count = 0
	for _ in pairs(schema) do
		count += 1
	end

	local sortedKeys = table.create(count)
	for k in pairs(schema) do
		table.insert(sortedKeys, k)
	end
	table.sort(sortedKeys)

	return {
		__type = "Struct",
		schema = schema,
		keys = sortedKeys
	} :: any
end

return Types