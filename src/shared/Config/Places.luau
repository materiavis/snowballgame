--!strict
-- Live PlaceIds for teleports. 0 means "not published yet"; humans fill these in at publish.

local Places = {
	Lobby = 0,
	-- Keyed by WorldIndex. Later worlds are added here together with their Rojo project.
	Worlds = table.freeze({
		[1] = 0,
	}),
	Arena = 0,
}

return table.freeze(Places)
