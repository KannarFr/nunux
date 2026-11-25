#!/usr/bin/env python3
"""ecran-mqtt : l'écran de la Surface RT piloté par Home Assistant (écran mural de la salle à manger).

Contrat MQTT (préfixe ecran/salon/) :
  commande  HA -> tablette   on / off
  etat      tablette -> HA   on / off (retenu)
  contexte  HA -> tablette   {"vide": bool, "alerte": bool} (retenu)
  dispo     tablette -> HA   online / offline (retenu, LWT)
  son       HA -> tablette   nom d'un clip de SONS (personne_jour…) ou « stop »
  batterie  tablette -> HA   {"capacite", "etat", "secteur", "courant_a", "tension_v"} (retenu, toutes
                             les minutes) : elle s'est éteinte batterie vide le 2026-11-25

Un toucher rallume l'écran (X le fait déjà de lui-même) ; si la pièce est vide et qu'aucune alerte
n'est affichée, l'écran se rééteint 60 s après le dernier toucher. Sans contexte (HA ou broker
injoignable), l'écran reste allumé : c'est l'état sûr.

Configuration par l'environnement (/etc/ecran-salon.env, hors du repo) : MQTT_HOTE, MQTT_PORT,
MQTT_UTILISATEUR, MQTT_MOT_DE_PASSE, TACTILE (périphérique evdev de l'écran tactile).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import threading
import time
from dataclasses import dataclass, replace
from pathlib import Path

PREFIXE = "ecran/salon/"
SONS = Path("/usr/local/share/ecran-salon/sons")
ALIMENTATION = Path("/sys/class/power_supply")
DELAI_REXTINCTION = 60
NOM_CLIP = re.compile(r"^[a-z0-9_]+$")


@dataclass(frozen=True)
class Etat:
    ecran_allume: bool
    vide: bool | None
    alerte: bool
    touche_a: float | None

    @staticmethod
    def initial() -> "Etat":
        return Etat(ecran_allume=True, vide=None, alerte=False, touche_a=None)


def decider(evenement: str, etat: Etat, maintenant: float) -> tuple[Etat, list[str]]:
    """Ce que fait l'écran pour un évènement ; « contexte » arrive avec vide/alerte déjà dans l'état."""
    if evenement == "commande_on":
        return replace(etat, ecran_allume=True), ["allumer"]
    if evenement == "commande_off":
        return replace(etat, ecran_allume=False, touche_a=None), ["eteindre"]
    if evenement == "toucher":
        actions = [] if etat.ecran_allume else ["allumer"]
        return replace(etat, ecran_allume=True, touche_a=maintenant), actions
    if evenement == "contexte":
        if etat.alerte and not etat.ecran_allume:
            return replace(etat, ecran_allume=True), ["allumer"]
        return etat, []
    if evenement == "tic":
        if (etat.ecran_allume and etat.vide is True and not etat.alerte
                and etat.touche_a is not None and maintenant - etat.touche_a >= DELAI_REXTINCTION):
            return replace(etat, ecran_allume=False, touche_a=None), ["eteindre"]
        return etat, []
    return etat, []


def choisir_son(nom: str, dossier: Path) -> Path | None:
    """Le clip à jouer, seulement un nom simple qui existe dans le dossier des sons."""
    if not NOM_CLIP.match(nom):
        return None
    chemin = dossier / f"{nom}.mp3"
    return chemin if chemin.is_file() else None


class Lecteur:
    """Un seul son à la fois : un nouveau clip ou « stop » coupe celui en cours."""

    def __init__(self, programme: list[str]):
        self.programme = programme
        self.processus: subprocess.Popen | None = None
        self._verrou = threading.Lock()

    def jouer(self, chemin: str | Path) -> None:
        with self._verrou:
            self._couper()
            self.processus = subprocess.Popen([*self.programme, str(chemin)],
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self) -> None:
        with self._verrou:
            self._couper()

    def _couper(self) -> None:
        if self.processus is not None and self.processus.poll() is None:
            self.processus.terminate()
            try:
                self.processus.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.processus.kill()
        self.processus = None


def lire_batterie(dossier: Path) -> dict | None:
    """La batterie et le chargeur de la Surface RT (pilotes surface-rt-battery / surface-rt-ac-adapter)."""
    bat, sec = dossier / "surface-rt-battery", dossier / "surface-rt-ac-adapter"
    try:
        lire = lambda f: (bat / f).read_text().strip()
        return {"capacite": int(lire("capacity")), "etat": lire("status"),
                "secteur": (sec / "online").read_text().strip() == "1",
                "courant_a": round(int(lire("current_now")) / 1e6, 3),
                "tension_v": round(int(lire("voltage_now")) / 1e6, 3)}
    except (OSError, ValueError):
        return None


def ecran(allumer: bool) -> None:
    subprocess.run(["xset", "dpms", "force", "on" if allumer else "off"], check=False)


def main() -> None:
    import evdev
    import paho.mqtt.client as mqtt

    env = os.environ
    verrou = threading.Lock()
    etat = Etat.initial()
    lecteur = Lecteur(["pw-play"])
    client = mqtt.Client(client_id="ecran-salon")  # API paho 1.6 (Debian Bookworm)
    client.username_pw_set(env.get("MQTT_UTILISATEUR"), env.get("MQTT_MOT_DE_PASSE"))
    client.will_set(PREFIXE + "dispo", "offline", retain=True)

    def appliquer(evenement: str, **contexte) -> None:
        nonlocal etat
        with verrou:
            if contexte:
                etat = replace(etat, **contexte)
            etat, actions = decider(evenement, etat, time.monotonic())
            for action in actions:
                ecran(action == "allumer")
            if actions:
                client.publish(PREFIXE + "etat", "on" if etat.ecran_allume else "off", retain=True)

    def connecte(c, _u, _f, code):
        if code != 0:
            return
        c.publish(PREFIXE + "dispo", "online", retain=True)
        c.publish(PREFIXE + "etat", "on" if etat.ecran_allume else "off", retain=True)
        c.subscribe([(PREFIXE + t, 1) for t in ("commande", "contexte", "son")])

    def message(_c, _u, m):
        sujet = m.topic.removeprefix(PREFIXE)
        texte = m.payload.decode(errors="replace").strip()
        if sujet == "commande" and texte in ("on", "off"):
            appliquer("commande_" + texte)
        elif sujet == "contexte":
            try:
                ctx = json.loads(texte)
                appliquer("contexte", vide=bool(ctx["vide"]), alerte=bool(ctx["alerte"]))
            except (ValueError, KeyError, TypeError):
                pass
        elif sujet == "son":
            if texte == "stop":
                lecteur.stop()
            elif (chemin := choisir_son(texte, SONS)) is not None:
                lecteur.jouer(chemin)

    def tactile() -> None:
        while True:
            try:
                for ev in evdev.InputDevice(env["TACTILE"]).read_loop():
                    if ev.type == evdev.ecodes.EV_KEY and ev.value == 1:
                        appliquer("toucher")
            except OSError:
                time.sleep(5)

    client.on_connect = connecte
    client.on_message = message
    client.reconnect_delay_set(min_delay=2, max_delay=60)
    threading.Thread(target=tactile, daemon=True).start()
    ecran(True)
    client.connect_async(env.get("MQTT_HOTE", "10.0.0.151"), int(env.get("MQTT_PORT", "1883")))
    client.loop_start()
    secondes = 0
    while True:
        time.sleep(1)
        appliquer("tic")
        if secondes % 60 == 0 and (b := lire_batterie(ALIMENTATION)) is not None:
            client.publish(PREFIXE + "batterie", json.dumps(b), retain=True)
        secondes += 1


if __name__ == "__main__":
    main()
