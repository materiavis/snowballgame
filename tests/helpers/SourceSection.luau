--!strict
-- Text helpers for wiring checks on Roblox-facing modules that cannot load under Lune.

local fs = require("@lune/fs")

local SourceSection = {}

-- The text from `startMarker` up to (not including) `endMarker`. Errors if either is missing,
-- so a renamed function fails the spec instead of silently passing it.
function SourceSection.between(path: string, startMarker: string, endMarker: string): string
	local text = fs.readFile(path)
	local from = string.find(text, startMarker, 1, true)
	assert(from, `{path}: "{startMarker}" not found`)
	local to = string.find(text, endMarker, from + #startMarker, true)
	assert(to, `{path}: "{endMarker}" not found after "{startMarker}"`)
	return string.sub(text, from, to - 1)
end

-- Position of `needle` in `text`, or nil.
function SourceSection.at(text: string, needle: string): number?
	return (string.find(text, needle, 1, true))
end

return table.freeze(SourceSection)
