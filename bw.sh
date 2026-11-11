#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/share/mise/shims:$PATH"

# bw generate is offline -- start both in background before the session check
# so the ~2.4s Node cold-start runs in parallel with auth, not before it
rm -f ~/.cache/bw-preview-pw ~/.cache/bw-preview-pp
trap 'rm -f "$TMPFILE" "$PREVIEW_SCRIPT" ~/.cache/bw-preview-pw ~/.cache/bw-preview-pp' EXIT
(umask 077; bw generate -ulns --length 20 > ~/.cache/bw-preview-pw) &
(umask 077; bw generate --passphrase      > ~/.cache/bw-preview-pp) &

SESSION_FILE="$HOME/.cache/bw-session"
mkdir -p "$(dirname "$SESSION_FILE")"

BW_SESSION=""
[[ -f "$SESSION_FILE" ]] && BW_SESSION="$(cat "$SESSION_FILE")"
export BW_SESSION SESSION_FILE

# skip bw status -- it costs a full Node cold-start (1.3s) every open.
# if BW_SESSION is cached, trust it; bw list items clears the cache on
# failure so the next open re-prompts. if BW_SESSION is empty we know
# we need to unlock, so skip status and go straight to the prompt.
if [[ -z "$BW_SESSION" ]]; then
  _tty=$(stty -g)
  read -rs -p "Master password: " _BW_PW; printf '\n'
  stty "$_tty"; unset _tty
  BW_SESSION=$(BW_UNLOCK_PW="$_BW_PW" bw unlock --raw --passwordenv BW_UNLOCK_PW 2>/dev/null) || true
  unset _BW_PW
  if [[ -z "$BW_SESSION" ]]; then printf 'Unlock failed.\n' >&2; exit 1; fi
  (umask 077; printf '%s' "$BW_SESSION" > "$SESSION_FILE")
fi

TMPFILE=$(mktemp)
PREVIEW_SCRIPT=$(mktemp)
export TMPFILE PREVIEW_SCRIPT

cat > "$PREVIEW_SCRIPT" << 'PREVIEW_EOF'
#!/usr/bin/env bash
# poll up to 3s for the background generate to finish (-s = non-empty)
for (( i = 0; i < 15; i++ )); do [[ -s "$HOME/.cache/bw-preview-pw" ]] && [[ -s "$HOME/.cache/bw-preview-pp" ]] && break; sleep 0.2; done
pw=$(cat "$HOME/.cache/bw-preview-pw" 2>/dev/null || echo "(none)")
pp=$(cat "$HOME/.cache/bw-preview-pp" 2>/dev/null || echo "(none)")
printf '\033[1;34m╭─ Generated Credentials ──────────────╮\033[0m\n'
printf '\033[1;34m│\033[0m \033[1mPassword:\033[0m\n'
printf '\033[1;34m│\033[0m \033[0;32m%s\033[0m\n' "$pw"
printf '\033[1;34m│\033[0m\n'
printf '\033[1;34m│\033[0m \033[1mPassphrase:\033[0m\n'
printf '\033[1;34m│\033[0m \033[0;33m%s\033[0m\n' "$pp"
printf '\033[1;34m│\033[0m\n'
printf '\033[1;34m├──────────────────────────────────────┤\033[0m\n'
printf '\033[1;34m│\033[0m \033[2mctrl+r\033[0m  regenerate\n'
printf '\033[1;34m│\033[0m \033[2malt+p\033[0m   copy password\n'
printf '\033[1;34m│\033[0m \033[2malt+P\033[0m   copy passphrase\n'
printf '\033[1;34m╰──────────────────────────────────────╯\033[0m\n'
PREVIEW_EOF
chmod +x "$PREVIEW_SCRIPT"

fzf \
  --with-nth 1 \
  --delimiter $'\t' \
  --header 'Loading vault...' \
  --preview-window 'right:50%:wrap' \
  --preview '"$PREVIEW_SCRIPT"' \
  --bind "start:reload(_raw=\$(bw list items 2>/dev/null); if [ -z \"\$_raw\" ]; then rm -f \"\$SESSION_FILE\"; echo 'vault load failed -- reopen to unlock'; else printf '%s\n' \"\$_raw\" | jq -c '.[] | select(.type==1)' | tee \"\$TMPFILE\" | jq -r '\"\(.name | gsub(\"\t\"; \" \"))\t\(.id)\"'; fi)" \
  --bind "load:change-header(enter=password  alt-u=username  alt-t=TOTP  alt-l=URL)" \
  --bind "enter:become(v=\$(jq -r 'select(.id==\"{2}\") | .login.password // empty' \"\$TMPFILE\"); [ -n \"\$v\" ] && printf '%s' \"\$v\" | pbcopy)" \
  --bind "alt-u:become(v=\$(jq -r 'select(.id==\"{2}\") | .login.username // empty' \"\$TMPFILE\"); [ -n \"\$v\" ] && printf '%s' \"\$v\" | pbcopy)" \
  --bind "alt-t:become(v=\$(jq -r 'select(.id==\"{2}\") | .login.totp // empty' \"\$TMPFILE\" | \"\$HOME\"/.config/rex/rex-bitwarden/bw-totp); [ -n \"\$v\" ] && printf '%s' \"\$v\" | pbcopy)" \
  --bind "alt-l:become(v=\$(jq -r 'select(.id==\"{2}\") | .login.uris[0].uri // empty' \"\$TMPFILE\"); [ -n \"\$v\" ] && printf '%s' \"\$v\" | pbcopy)" \
  --bind "ctrl-r:execute((umask 077; bw generate -ulns --length 20 > ~/.cache/bw-preview-pw) & (umask 077; bw generate --passphrase > ~/.cache/bw-preview-pp) & wait)+refresh-preview" \
  --bind "alt-p:execute(pbcopy < ~/.cache/bw-preview-pw)+become('')" \
  --bind "alt-P:execute(pbcopy < ~/.cache/bw-preview-pp)+become('')" \
  < /dev/null
