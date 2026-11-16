#!/usr/bin/env bash
# PreToolUse-Hook für Bash, in allen Sessions dieses Repos (settings.json).
# Der Development Manager darf nur seine Issue-Branches löschen
# (feat|fix|chore|docs/<issue>-<slug>), einzeln, nie erzwungen, nie main, und nur
# Agent-Worktrees unter .claude/worktrees/ entfernen. Force-Pushes sind gesperrt.
# Wann gelöscht wird, regelt der cleanup-Skill; dieser Hook sorgt dafür, dass nichts
# anderes gelöscht werden kann. Exit 2 = blockieren. Läuft in Git Bash, ohne jq.

input="$(cat)"

deny() {
  echo "Blockiert vom Cleanup-Hook: $1. Siehe CLAUDE.md Abschnitt 7; andere Branches löscht ein Mensch." >&2
  exit 2
}

ISSUE_BRANCH='^(refs/heads/)?(feat|fix|chore|docs)/[0-9]+-[A-Za-z0-9._-]+$'
STRICT=1

# Wert von "command" aus dem JSON holen und die nötigsten Escapes auflösen.
cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p')"
if [ -z "$cmd" ]; then
  if printf '%s' "$input" | grep -Eq 'push[^"]*(--delete|--mirror|--prune|--force)|branch[^"]*-D|worktree[^"]*remove|update-ref[^"]*-d'; then
    deny 'Befehl konnte nicht geprüft werden'
  fi
  exit 0
fi
cmd="$(printf '%s' "$cmd" | sed -e 's/\\\\/@@BS@@/g' -e 's/\\n/;/g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/@@BS@@/\\/g')"

strip_quotes() {
  local t="$1"
  t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"
  printf '%s' "$t"
}

is_issue_branch() {
  printf '%s' "$1" | grep -Eq "$ISSUE_BRANCH"
}

check_git() {
  # $@ = Tokens nach "git"; globale Optionen (-C <pfad>, -c <k=v>) überspringen
  local -a args=("$@")
  local i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      -C|-c) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  local sub="${args[$i]}"
  local -a rest=("${args[@]:$((i + 1))}")
  local t

  case "$sub" in
    push)
      local del=0 remote=""
      local -a refs=()
      for t in "${rest[@]}"; do
        t="$(strip_quotes "$t")"
        case "$t" in
          --mirror|--prune) deny "git push $t kann Branches auf GitHub löschen" ;;
          --force*) deny 'Force-Push ist nicht erlaubt' ;;
          --delete) del=1 ;;
          --*) ;;
          -*)
            case "$t" in *f*) deny 'Force-Push ist nicht erlaubt' ;; esac
            case "$t" in *d*) del=1 ;; esac
            ;;
          *) if [ -z "$remote" ]; then remote="$t"; else refs+=("$t"); fi ;;
        esac
      done
      for t in "${refs[@]}"; do
        case "$t" in
          :*) deny 'Löschen mit ":<branch>" ist nicht erlaubt, nur git push origin --delete <branch>' ;;
          +*) deny 'Force-Push ist nicht erlaubt' ;;
        esac
      done
      if [ $del -eq 1 ]; then
        if [ -n "$remote" ] || [ $STRICT -eq 1 ]; then
          [ "$remote" = "origin" ] || deny 'Branches nur auf origin löschen'
        fi
        if [ ${#refs[@]} -gt 1 ] || { [ $STRICT -eq 1 ] && [ ${#refs[@]} -ne 1 ]; }; then
          deny 'genau einen Branch pro Befehl löschen'
        fi
        for t in "${refs[@]}"; do
          is_issue_branch "$t" || deny "\"$t\" ist kein Issue-Branch des Development Managers"
        done
      fi
      ;;
    branch)
      local del=0 force=0
      local -a names=()
      for t in "${rest[@]}"; do
        t="$(strip_quotes "$t")"
        case "$t" in
          --delete) del=1 ;;
          --force) force=1 ;;
          --*) ;;
          -*)
            case "$t" in *D*) deny 'git branch -D ist nicht erlaubt, nur git branch -d' ;; esac
            case "$t" in *d*) del=1 ;; esac
            case "$t" in *f*) force=1 ;; esac
            ;;
          *) names+=("$t") ;;
        esac
      done
      if [ $del -eq 1 ]; then
        [ $force -eq 0 ] || deny 'erzwungenes Löschen eines Branches ist nicht erlaubt'
        for t in "${names[@]}"; do
          is_issue_branch "$t" || deny "\"$t\" ist kein Issue-Branch des Development Managers"
        done
      fi
      ;;
    worktree)
      if [ "${rest[0]}" = "remove" ]; then
        local -a paths=()
        for t in "${rest[@]:1}"; do
          t="$(strip_quotes "$t")"
          case "$t" in
            --force) deny 'git worktree remove --force ist nicht erlaubt' ;;
            --*) ;;
            -*) case "$t" in *f*) deny 'git worktree remove --force ist nicht erlaubt' ;; esac ;;
            *) paths+=("$t") ;;
          esac
        done
        for t in "${paths[@]}"; do
          printf '%s' "$t" | grep -Eq '\.claude[\\/]+worktrees[\\/]+[^\\/]' || deny "nur Agent-Worktrees unter .claude/worktrees/ entfernen, nicht \"$t\""
        done
      fi
      ;;
    update-ref)
      for t in "${rest[@]}"; do
        [ "$t" = "-d" ] && deny 'git update-ref -d ist nicht erlaubt'
      done
      ;;
  esac
}

check_segments() {
  local seg
  local -a tok
  while IFS= read -r seg || [ -n "$seg" ]; do
    read -ra tok <<< "$seg"
    [ ${#tok[@]} -eq 0 ] && continue
    case "${tok[0]}" in
      git) check_git "${tok[@]:1}" ;;
      gh)
        if printf '%s' "$seg" | grep -Eq '(-X|--method)[[:space:]=]*DELETE' && printf '%s' "$seg" | grep -q 'git/refs'; then
          deny 'Branches nicht über gh api löschen, nur mit git push origin --delete <branch>'
        fi
        ;;
    esac
  done
}

# 1. Durchgang: Befehle an &&, ||, &, ;, | und Zeilenumbrüchen trennen.
STRICT=1
check_segments < <(printf '%s' "$cmd" | sed -e 's/&&/;/g' -e 's/||/;/g' -e 's/[&|]/;/g' | tr ';' '\n')
# 2. Durchgang: zusätzlich an Quotes, Backticks und Klammern trennen, damit auch
# verschachtelte Befehle (bash -c "…", $(…)) geprüft werden.
STRICT=0
check_segments < <(printf '%s' "$cmd" | sed -e 's/&&/;/g' -e 's/||/;/g' -e "s/[&|\"'\`(){}]/;/g" -e 's/\$;/;/g' | tr ';' '\n')

exit 0
