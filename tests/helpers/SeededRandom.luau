--!strict
-- Deterministic xorshift32 generator for tests. Roblox's `Random` does not exist under Lune,
-- and a fixed seed keeps statistical tests from flaking in CI.
-- Game modules should take a roll function (or a Random-like object) as a parameter so
-- tests can inject this and live code can pass Random.new().

local SeededRandom = {}

local UINT32 = 2 ^ 32

export type Generator = {
	-- Uniform float in [0, 1).
	next: () -> number,
	-- Uniform integer in [min, max], both inclusive.
	nextInteger: (min: number, max: number) -> number,
}

function SeededRandom.new(seed: number): Generator
	-- xorshift has a fixed point at 0, so a zero seed is remapped to a non-zero constant.
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if state == 0 then
		state = 0x9E3779B9
	end

	local function nextUint(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state
	end

	local function nextFloat(): number
		return nextUint() / UINT32
	end

	local function nextInteger(min: number, max: number): number
		assert(min <= max, "nextInteger: min must not exceed max")
		return min + math.floor(nextFloat() * (max - min + 1))
	end

	return table.freeze({ next = nextFloat, nextInteger = nextInteger })
end

return table.freeze(SeededRandom)
