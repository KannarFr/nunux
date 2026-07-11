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

# SubagentStop event — a background/sub-agent finished, main task still running.
agent_lines=(
  "Un agent a terminé."
  "Un de mes agents a fini."
  "Agent bouclé, ça continue."
  "Une tâche de fond est finie."
  "Un sous-agent vient de finir."
  "Ça avance, un agent a terminé."
  "Un helper a rendu sa copie."
  "Un agent en moins, je continue."
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

# Build the whole pool in a temp dir, then swap it into place only on full
# success — a network/edge-tts failure mid-run thus never wipes the working
# clips (edge-tts stderr is kept visible so a failure is diagnosable).
gen() {
  local dir="$1"; shift
  local tmpdir; tmpdir="$(mktemp -d "$dir.XXXXXX")"  # same fs as $dir → atomic mv
  chmod 755 "$tmpdir"                                 # mktemp -d is 0700; match repo dirs
  local i=1 line mp3 wav
  for line in "$@"; do
    wav="$tmpdir/$(printf '%02d' "$i").wav"
    mp3="$(mktemp --suffix=.mp3)"
    if ! edge-tts --voice "$voice" --text "$line" --write-media "$mp3" >/dev/null; then
      rm -f "$mp3"; rm -rf "$tmpdir"; return 1
    fi
    ffmpeg -y -loglevel error -i "$mp3" -ar 24000 -ac 1 -sample_fmt s16 "$wav"
    rm -f "$mp3"
    i=$((i + 1))
  done
  rm -rf "$dir"; mv "$tmpdir" "$dir"
}

gen "$here/done"  "${done_lines[@]}"
gen "$here/agent" "${agent_lines[@]}"
gen "$here/wait"  "${wait_lines[@]}"
echo "done: ${#done_lines[@]} clips | agent: ${#agent_lines[@]} clips | wait: ${#wait_lines[@]} clips (voice: $voice)"
