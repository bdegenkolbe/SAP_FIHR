# -*- coding: utf-8 -*-
"""Datenschutz-Transformationen fuer den Export.

Uebernommen aus Schwesterprojekt Ingolf (agent/privacy.py), unveraendert in der Logik:
  off           -> Klardaten (nur interner Betrieb)
  pseudonymize  -> stabile HMAC-Pseudonyme, Date-Shift, Freitext-De-ID
  anonymize     -> zusaetzlich Generalisierung (nur Geburtsjahr)

Die Zuordnung Pseudonym -> echte PATNR gehoert in den separat gesicherten Vault,
niemals in Exportdateien oder in die Analysezone.
"""
from __future__ import annotations
import base64
import datetime as _dt
import hashlib
import hmac
import re


class Privacy:
    def __init__(self, mode: str = "pseudonymize", secret: bytes | str = b"",
                 date_shift: bool = True, free_text_deid: bool = True,
                 keep_filenames: bool = False, gate: str = "enforce"):
        self.mode = mode
        self.secret = secret if isinstance(secret, bytes) else str(secret).encode()
        self.date_shift = date_shift
        self.free_text_deid = free_text_deid
        self.keep_filenames = keep_filenames
        self.gate = gate

    # -- Identifikatoren ----------------------------------------------------
    def pseudonym(self, pid) -> str:
        if self.mode == "off":
            return str(pid)
        mac = hmac.new(self.secret, str(pid).encode(), hashlib.sha256).digest()
        return "P" + base64.b32encode(mac)[:16].decode("ascii")

    def hash_id(self, value, label: str = "id") -> str | None:
        """Wertbasiertes Pseudonym fuer Sekundaer-IDs (z.B. KVNR): patientenuebergreifend
        konsistent. Bei mode=off unveraendert."""
        if value in (None, ""):
            return None
        if self.mode == "off":
            return str(value)
        mac = hmac.new(self.secret, (label + ":" + str(value)).encode(),
                       hashlib.sha256).digest()
        return label[:3].upper() + base64.b32encode(mac)[:14].decode("ascii")

    # -- Datumsverschiebung -------------------------------------------------
    def _shift_days(self, pid) -> int:
        if not self.date_shift or self.mode == "off":
            return 0
        mac = hmac.new(self.secret, ("shift:" + str(pid)).encode(),
                       hashlib.sha256).digest()
        return (int.from_bytes(mac[:4], "big") % 731) - 365  # +/- 1 Jahr, patientenfix

    def shift(self, pid, iso: str | None) -> str | None:
        if not iso:
            return iso
        d = self._shift_days(pid)
        if d == 0:
            return iso
        try:
            dt = _dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
            return (dt + _dt.timedelta(days=d)).isoformat()
        except ValueError:
            return iso

    # -- Patient-Ressource entschaerfen ------------------------------------
    def redact_patient(self, res: dict, pid) -> dict:
        if self.mode == "off":
            return res
        res.pop("name", None)
        res.pop("address", None)
        res.pop("telecom", None)
        res["identifier"] = [{"system": "urn:pseudonym", "value": self.pseudonym(pid)}]
        if "birthDate" in res:
            res["birthDate"] = str(res["birthDate"])[:4]  # nur Jahr
        return res

    # -- Freitext-De-Identifikation (minimal, erweiterbar) -----------------
    def text(self, pid, s: str | None) -> str | None:
        if self.mode == "off" or not self.free_text_deid or not s:
            return s
        s = re.sub(r"\b\d{1,2}\.\d{1,2}\.\d{2,4}\b", "[DATUM]", s)
        s = re.sub(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b", "[EMAIL]", s)
        s = re.sub(r"(?i)\b(herr|frau|dr\.?|prof\.?)\s+[A-ZÄÖÜ][a-zäöüß]+",
                   r"\1 [NAME]", s)
        s = re.sub(r"\b[A-Z]{1,3}\d{6,}\b", "[ID]", s)
        return s
