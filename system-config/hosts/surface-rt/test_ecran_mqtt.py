"""Tests de la logique d'ecran-mqtt (python -m pytest -q system-config/hosts/surface-rt)."""

import time
from pathlib import Path

from ecran_mqtt import Etat, Lecteur, choisir_son, decider

T = 1000.0


def etat(**k):
    base = dict(ecran_allume=True, vide=None, alerte=False, touche_a=None)
    base.update(k)
    return Etat(**base)


def test_commande_off_eteint():
    e, a = decider("commande_off", etat(), T)
    assert a == ["eteindre"] and not e.ecran_allume


def test_commande_on_allume():
    e, a = decider("commande_on", etat(ecran_allume=False), T)
    assert a == ["allumer"] and e.ecran_allume


def test_toucher_rallume_ecran_eteint():
    e, a = decider("toucher", etat(ecran_allume=False), T)
    assert a == ["allumer"] and e.ecran_allume and e.touche_a == T


def test_rextinction_60s_piece_vide():
    e, _ = decider("toucher", etat(ecran_allume=False, vide=True), T)
    e, a = decider("tic", e, T + 59)
    assert a == []
    e, a = decider("tic", e, T + 60)
    assert a == ["eteindre"] and not e.ecran_allume


def test_pas_de_rextinction_pendant_alerte():
    e, _ = decider("toucher", etat(ecran_allume=False, vide=True, alerte=True), T)
    for dt in (60, 120, 600):
        e, a = decider("tic", e, T + dt)
        assert a == []
    assert e.ecran_allume


def test_pas_de_rextinction_piece_occupee():
    e, _ = decider("toucher", etat(ecran_allume=False, vide=False), T)
    e, a = decider("tic", e, T + 600)
    assert a == [] and e.ecran_allume


def test_sans_contexte_ecran_allume():
    e = Etat.initial()
    assert e.ecran_allume and e.vide is None
    e, a = decider("toucher", e, T)
    e, a = decider("tic", e, T + 600)
    assert a == [] and e.ecran_allume


def test_contexte_alerte_au_demarrage():
    e, a = decider("contexte", etat(ecran_allume=False, vide=True, alerte=True), T)
    assert a == ["allumer"] and e.ecran_allume


def test_contexte_sans_alerte_ne_force_rien():
    e, a = decider("contexte", etat(ecran_allume=False, vide=True, alerte=False), T)
    assert a == [] and not e.ecran_allume


def test_son_joue_clip_connu(tmp_path: Path):
    (tmp_path / "personne_jour.mp3").write_bytes(b"x")
    assert choisir_son("personne_jour", tmp_path) == tmp_path / "personne_jour.mp3"


def test_son_ignore_clip_inconnu(tmp_path: Path):
    (tmp_path / "personne_jour.mp3").write_bytes(b"x")
    assert choisir_son("absent", tmp_path) is None
    assert choisir_son("../etc/passwd", tmp_path) is None
    assert choisir_son("personne_jour.mp3", tmp_path) is None
    assert choisir_son("", tmp_path) is None


def test_stop_coupe_le_son():
    lecteur = Lecteur(["sleep"])
    lecteur.jouer("30")
    premier = lecteur.processus
    assert premier.poll() is None
    lecteur.jouer("30")
    premier.wait(timeout=5)
    assert premier.poll() is not None, "un nouveau clip coupe le précédent"
    second = lecteur.processus
    lecteur.stop()
    second.wait(timeout=5)
    assert second.poll() is not None
    assert lecteur.processus is None
