#!/usr/bin/env bash
# Regressionstest für guard-studio-luau.sh. Aufruf aus dem Repo-Root:
#   bash .claude/hooks/test-guard-studio-luau.sh
# Jeder Fall schickt eine PreToolUse-Payload wie Claude Code (JSON, Code als JSON-String) an den
# Hook und prüft den Exit-Code: 0 = erlaubt, 2 = blockiert. Exit 1, wenn ein Fall abweicht.

hook="$(dirname "$0")/guard-studio-luau.sh"
pass=0
fail=0

# $1 = erwarteter Exit-Code, $2 = Beschreibung, $3 = Luau-Code als JSON-String-Inhalt (schon escaped),
# $4 = DataModel (optional, Default server)
expect() {
  local want="$1" name="$2" code="$3" dm="${4:-server}"
  local payload
  payload="$(printf '{"tool_name":"mcp__Roblox_Studio__execute_luau","tool_input":{"code":"%s","datamodel_type":"%s"}}' "$code" "$dm")"
  printf '%s' "$payload" | bash "$hook" 2>/dev/null
  local got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (erwartet $want, bekommen $got)" >&2
    echo "      payload: $payload" >&2
  fi
}

allow() { expect 0 "$@"; }
block() { expect 2 "$@"; }

# --- require / getfenv / setfenv (#130 / #37 round 1) ---
block 'require eines Game-Moduls' 'local D = require(game.ServerScriptService.Server.Services.DataService) return D'
block 'require mit Leerzeichen' 'return require (game.ReplicatedStorage.Shared.Config)'
block 'require mit Asset-Id' 'return require(123456)'
block 'require ohne Klammern (String-Call)' 'return require \"x\"'
block 'require als Wert gespeichert' 'local r = require return r'
block 'require nach JSON-Newline' 'local x = 1\nrequire(game.ReplicatedStorage.Shared.Config)'
block 'require nach JSON-Tab' 'local x = 1\trequire(game.ReplicatedStorage.Shared.Config)'
block 'require am Anfang' 'require(game.ReplicatedStorage.Shared.Config)'
block 'require in Grossschreibung' 'return REQUIRE(game.ReplicatedStorage.Shared.Config)'
block 'getfenv' 'return getfenv()'
block 'getfenv mit Index' 'return getfenv(0)[\"req\" .. \"uire\"]'
block 'setfenv' 'setfenv(1, {}) return 1'
block 'rawget auf getfenv' 'return rawget(getfenv(), \"require\")'

# --- bestehende Sperren ---
block 'HttpService' 'return game:GetService(\"HttpService\")'
block 'loadstring' 'return loadstring(\"return 1\")()'
block 'DataStoreService' 'return game:GetService(\"DataStoreService\")'
block 'Instance.new' 'return 0 -- hook self-test: Instance.new'
block 'Destroy' 'workspace.Baseplate:Destroy()'
block 'Property-Zuweisung' 'workspace.Gravity = 0'
block 'Index-Zuweisung' 'local t = {} t[1] = 2 return t'
block 'FireServer' 'game.ReplicatedStorage.Remotes.Sell:FireServer()'
block 'SetAttribute auf anderem Objekt' 'workspace:SetAttribute(\"X\", 1)'
block 'Studio switch im Edit mode' 'game.ServerScriptService:SetAttribute(\"PlaytestX\", 1)' 'edit'

# --- erlaubt ---
allow 'PlaceId lesen' 'return game.PlaceId' 'edit'
allow 'Attribut lesen' 'return game.Players:GetPlayers()[1]:GetAttribute(\"Coins\")'
allow 'Studio switch im Play' 'game.ServerScriptService:SetAttribute(\"PlaytestX\", 1)'
allow 'Vergleich' 'return workspace.Gravity == 196.2'
allow 'table.insert mit Newline' 'local out = {}\nfor _, p in game.Players:GetPlayers() do table.insert(out, p.Name) end\nreturn table.concat(out, \",\")'
allow 'Wort mit require als Teil' 'local requirement = 1 return requirement'
allow 'Wort mit require als Suffix' 'local prerequire = 1 return prerequire'
allow 'Console-Fallback aus playtester.md' 'local out = {} for _, e in game:GetService(\"LogService\"):GetLogHistory() do table.insert(out, e.messageType.Name .. \": \" .. e.message) end return table.concat(out, \"\\n\")'

echo "guard-studio-luau: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
