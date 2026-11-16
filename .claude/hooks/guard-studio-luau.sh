#!/usr/bin/env bash
# PreToolUse-Hook für mcp__Roblox_Studio__execute_luau (Playtester), Version 2.
# Wird aus dem Control Checkout auf `main` geladen, in dem der Playtester läuft. Der getestete
# Stand liegt in einer separaten Playtest Worktree, ein Pull Request kann den Hook also nicht
# abschwächen. Exit 2 = blockieren, stderr geht an den Agent zurück. Läuft in Git Bash, ohne jq.
#
# Erlaubt: State lesen und die Studio switches der ADRs setzen, und zwar nur in der Form
#   game.ServerScriptService:SetAttribute("<Name>", <Wert>)
# Alles andere, was den Place, Daten, Netzwerk oder den Spielzustand verändert, wird geblockt.

input="$(cat)"

deny() {
  echo "Blockiert vom Playtester-Hook: $1. Nicht umformulieren, um die Sperre zu umgehen: das AC als ERROR (blocked by hook) mit dieser Meldung melden." >&2
  exit 2
}

check() {
  # $1 = Regex (case-insensitive), $2 = Grund
  if printf '%s' "$input" | grep -Eiq -- "$1"; then deny "$2"; fi
}

# Netzwerk / dynamischer Code
check 'HttpService|HttpGet|HttpPost|RequestAsync|GetAsync\(|PostAsync\(|loadstring' 'HTTP / dynamischer Code'
# DataStores / persistente Daten
check 'DataStoreService|MemoryStoreService|SetAsync|UpdateAsync|IncrementAsync|RemoveAsync|OrderedDataStore' 'DataStore-Zugriff'
# Publish / Speichern / Assets
check 'SavePlace|PublishAsync|AssetService|InsertService|LoadAsset|CreatePlaceAsync' 'Publish / Asset-Laden'
# Käufe
check 'MarketplaceService|PromptPurchase|PromptProductPurchase|PromptGamePassPurchase|ProcessReceipt' 'Käufe'
# Teleports
check 'TeleportService|TeleportAsync|:Teleport\(' 'Teleport'
# Instances erzeugen, löschen, umhängen, Scripts ändern
check 'Instance\.new|:Destroy\(|:Remove\(|:Clone\(|:ClearAllChildren\(|ChangeHistoryService|require\([[:space:]]*[0-9]' 'Änderung am Place / externes require'
# Spielzustand per Code statt per Input verändern (Bewegung, Physik, Remotes, Tags, Character)
check ':(PivotTo|MoveTo|SetPrimaryPartCFrame|TranslateBy|ApplyImpulse|ApplyAngularImpulse|ApplyImpulseAtPosition|SetNetworkOwner|SetNetworkOwnershipAuto|BreakJoints|TakeDamage|LoadCharacter|Kick|Move|ChangeState|SetStateEnabled|AddTag|RemoveTag|FireServer|FireClient|FireAllClients|InvokeServer|InvokeClient|Fire)\(' 'Spielzustand per Code verändern (Bewegung, Physik, Remotes, Tags). Gespielt wird über character_navigation, user_keyboard_input und user_mouse_input'
# Zuweisung an Properties oder Felder (x.y = …, auch +=). Vergleiche (==, ~=, <=, >=) sind erlaubt.
check '[]A-Za-z0-9_)]\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\+|-|\*|/|%|\^|\.\.)?=([^=]|$)' 'Zuweisung an eine Property oder ein Feld (x.y = …). Für Hilfswerte lokale Variablen oder table.insert verwenden'
# Index-Zuweisung (x[…] = …)
check '\][[:space:]]*(\+|-|\*|/|%|\^|\.\.)?=([^=]|$)' 'Index-Zuweisung (x[…] = …). Für Hilfswerte table.insert verwenden'

# Studio switches: SetAttribute nur in der festen Form auf ServerScriptService
all_set="$(printf '%s' "$input" | grep -o 'SetAttribute' | wc -l)"
if [ "$all_set" -gt 0 ]; then
  allowed_set="$(printf '%s' "$input" | grep -o 'game\.ServerScriptService:SetAttribute(' | wc -l)"
  if [ "$all_set" -ne "$allowed_set" ]; then
    deny 'SetAttribute ist nur als game.ServerScriptService:SetAttribute("<Name>", <Wert>) erlaubt (Studio switches)'
  fi
  if printf '%s' "$input" | grep -Eq '"datamodel_type"[[:space:]]*:[[:space:]]*"edit"'; then
    deny 'Studio switches nur während Play im DataModel server setzen, nicht im Edit mode'
  fi
fi

exit 0
