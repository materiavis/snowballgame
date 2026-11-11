--!strict
-- Teleports between Places (concept 5.6, 6.5; ADR 0003, ADR 0010). Startwerte, seconds unless
-- noted. The Simulator server size is Config.Lobby.SimulatorPlayers; PlaceIds are Config.Places.

local Travel = {
	-- Save before teleport (6.5). DataService.PrepareTeleport already retries its store call
	-- with backoff (Config.Data); these are whole PrepareTeleport calls on top of that.
	SaveAttempts = 2,
	SaveRetryDelay = 5,

	-- Teleport attempts per travel, each one saves first. Waits between attempts:
	-- TeleportRetryBase * TeleportRetryFactor ^ (attempt - 1), capped at TeleportRetryMax.
	TeleportAttempts = 3,
	TeleportRetryBase = 2,
	TeleportRetryFactor = 2,
	TeleportRetryMax = 8,
	-- No failure signal and the player is still here after this long: counts as a failed attempt.
	TeleportTimeout = 30,
	TeleportPoll = 0.25,

	-- ResumeAfterTeleportFailure calls that hit a store error before the player is sent to rejoin.
	ResumeAttempts = 3,
	ResumeRetryDelay = 2,

	-- Load failure outside the Lobby (ADR 0003): after this many failed load attempts
	-- (each one is a full DataService load with its own retries) the player is sent back to the
	-- Lobby, after showing the message for LoadFailReturnDelay.
	LoadFailuresBeforeLobby = 2,
	LoadFailReturnDelay = 5,

	-- Presence in MemoryStore (ADR 0003: TTL 60 s, refresh at most every 30 s). Losing it only
	-- loses the friend preference, never progress.
	PresenceTtl = 60,
	PresenceRefresh = 30,
	-- Private server -> reserved Simulator server mapping. The reserved servers stay valid, so
	-- the mapping lives long and is refreshed on every use (MemoryStore allows up to 45 days).
	PrivateMappingTtl = 86400,
	-- Online friends checked for the friend preference (5.6), one presence read each.
	FriendLookupMax = 20,
	-- MemoryStore calls per request before giving up (presence is best effort).
	PresenceAttempts = 2,
	PresenceRetryDelay = 0.5,

	-- MemoryStore names. Part of the cross-server format, but short-lived (TTL), so renaming one
	-- only loses current presence.
	PresenceMapName = "Presence",
	UserKeyPrefix = "user_",
	ServerKeyPrefix = "server_",
	PrivateKeyPrefix = "private_",
	ReservedKeyPrefix = "reserved_",

	-- On-screen message (owner decision 2026-11-10: simple text, the popup is #91).
	MessageSeconds = 4,
	MessageWidth = 520,
	MessageHeight = 44,
	MessageTopOffset = 64,
	MessageTextRGB = { 255, 255, 255 },
	MessageBackgroundRGB = { 30, 40, 60 },
	MessageBackgroundTransparency = 0.25,
	MessageCornerRadius = 10,
	MessagePadding = 8,
	MessageDisplayOrder = 10, -- above the HUD, so a failure message is never hidden

	-- Server -> client message keys and their text (German, short, for kids).
	Messages = {
		SaveRetry = "Speichern hat nicht geklappt. Neuer Versuch …",
		SaveFailed = "Speichern fehlgeschlagen, du bleibst hier.",
		TeleportRetry = "Teleport fehlgeschlagen. Neuer Versuch …",
		TeleportFailed = "Teleport fehlgeschlagen, du bleibst hier.",
		NotReady = "Deine Daten laden noch. Bitte warte kurz.",
		LoadFailedReturn = "Deine Daten laden gerade nicht. Zurück zur Lobby …",
		ResumeFailed = "Verbindung zum Speichern verloren. Bitte tritt neu bei.",
	},
}

table.freeze(Travel.MessageTextRGB)
table.freeze(Travel.MessageBackgroundRGB)
table.freeze(Travel.Messages)

return table.freeze(Travel)
