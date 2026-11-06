--!strict
-- Snowball fight (concept 7.14 to 7.22). Startwerte. Studs and seconds.
-- Snow Coin rewards are in Config/Economy.

local Fight = {
	-- Modes (7.15). Points to win are fixed (decision 08.10.), time limits may be tuned.
	Modes = table.freeze({
		table.freeze({ Id = "2v2", Players = 4, Arena = "Small", PointsToWin = 8, TimeLimit = 180 }),
		table.freeze({ Id = "3v3", Players = 6, Arena = "Medium", PointsToWin = 12, TimeLimit = 240 }),
		table.freeze({ Id = "4v4", Players = 8, Arena = "Large", PointsToWin = 16, TimeLimit = 240 }),
	}),
	PointsPerFreeze = 1,
	StartCountdown = 5,
	AfkTimeout = 60, -- inactive players go back to the Lobby

	-- Matchmaking (7.14, 7.22).
	QueueMaxWait = 30, -- then the match starts and bots fill free places
	PartyMaxSize = 4,

	-- Throwing and hits (7.16).
	Ammo = 5,
	ReloadInterval = 0.4, -- one snowball per interval while holding, only on snow
	ThrowRange = 80,
	ThrowCooldown = 0.35,
	HitsToFreeze = 5, -- ✅ (decision 08.10.)
	RecoveryTime = 5, -- without a hit, the snow is gone again
	FrozenTime = 3,
	RespawnProtection = 2,

	-- Quick signals (7.17): 4 signals, only the own team sees them.
	SignalCount = 4,
	SignalShowTime = 3,
	SignalCooldown = 2,

	-- Power-ups (7.18).
	PowerupInterval = 30,
	TripleThrowDuration = 10,
	FastBootsDuration = 10,
	FastBootsSpeedBonus = 0.4,

	-- Arenas (7.19).
	SnowWallHits = 3,
	SnowWallRespawn = 15,

	-- Bots (7.22): switch off here once there are enough players.
	BotsEnabled = true,
	BotAccuracy = 0.4,
	BotThrowPause = 0.8,

	-- Levels (7.20): level 10 after about 20 matches (✅ decision 15.10.).
	MaxLevel = 100,
	TargetMatchesForLevel10 = 20,
}

return table.freeze(Fight)
