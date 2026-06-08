#!/usr/bin/env bash
# Regenerate the Claude notification voice pools (edge-tts fr-FR-HenriNeural,
# "Henri"). claude-waiting.sh random-picks one clip per event, so the pools
# de-spam the repeated ping. Re-run after editing the phrase lists below.
# Needs: edge-tts (~/.local/bin), ffmpeg. Output matches the originals:
# 24 kHz, 16-bit, mono WAV.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
voice="fr-FR-HenriNeural"

# Stop event — Claude finished, waiting for your next message.
done_lines=(
  "C'est plié."
  "J'ai fini, à toi de jouer."
  "Terminé."
  "Et voilà le travail."
  "Mission accomplie."
  "Boulot terminé."
  "C'est bon, j'ai tout géré."
  "Fini, tu peux check."
  "Ça, c'est fait."
  "Terminé, à ton tour."
  "Voilà, propre et net."
  "J'ai bouclé."
)

# Notification event — Claude needs your input/attention.
wait_lines=(
  "Hé, j'ai besoin de toi."
  "Faut que tu valides un truc."
  "J'attends ton feu vert."
  "Y'a une question pour toi."
  "Reviens voir, j'ai un doute."
  "Bloqué, j'ai besoin de ton avis."
  "Yo, t'es là ? J'attends."
  "Faut que tu jettes un œil."
)

gen() {
  local dir="$1"; shift
  rm -rf "$dir"; mkdir -p "$dir"
  local i=1 line mp3 wav
  for line in "$@"; do
    wav="$dir/$(printf '%02d' "$i").wav"
    mp3="$(mktemp --suffix=.mp3)"
    edge-tts --voice "$voice" --text "$line" --write-media "$mp3" >/dev/null 2>&1
    ffmpeg -y -loglevel error -i "$mp3" -ar 24000 -ac 1 -sample_fmt s16 "$wav"
    rm -f "$mp3"
    i=$((i + 1))
  done
}

gen "$here/done" "${done_lines[@]}"
gen "$here/wait" "${wait_lines[@]}"
echo "done: ${#done_lines[@]} clips | wait: ${#wait_lines[@]} clips (voice: $voice)"
