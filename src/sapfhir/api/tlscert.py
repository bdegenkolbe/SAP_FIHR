# -*- coding: utf-8 -*-
"""Selbstsigniertes TLS-Zertifikat fuer den lokalen HTTPS-Betrieb (No-Admin).

Warum selbstsigniert: Die App bindet per Konzept nur auf Loopback (CONCEPT §10,
keine Patientendaten verlassen die Maschine). Eine CA-Kette braucht es dafuer nicht;
HTTPS dient hier der Erwartungskonformitaet (Browser-Warnung „nicht sicher",
Passwortfelder, Copy-Paste-Schutz), nicht dem Schutz eines Netzwerkpfads.

Achtung: Wird der Bind spaeter auf 0.0.0.0 geoeffnet, ist ein selbstsigniertes
Zertifikat NICHT ausreichend — dann gehoert ein Reverse-Proxy mit Haus-Zertifikat
davor (siehe docs/DEPLOYMENT.md).

CLI:  python -m sapfhir.api.tlscert            # erzeugt/erneuert config/certs/*
"""
from __future__ import annotations
import datetime as _dt
import ipaddress
import os
import socket

CERT_DIR = os.path.join("config", "certs")
CERT_FILE = os.path.join(CERT_DIR, "local.crt")
KEY_FILE = os.path.join(CERT_DIR, "local.key")


def ensure_cert(cert_file: str = CERT_FILE, key_file: str = KEY_FILE,
                days: int = 730) -> tuple[str, str] | None:
    """Erzeugt Zertifikat+Key, falls nicht vorhanden oder abgelaufen.
    Rueckgabe (cert, key) oder None, wenn `cryptography` fehlt."""
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
    except Exception:
        return None

    if os.path.exists(cert_file) and os.path.exists(key_file):
        try:
            with open(cert_file, "rb") as f:
                crt = x509.load_pem_x509_certificate(f.read())
            if crt.not_valid_after_utc > _dt.datetime.now(_dt.timezone.utc):
                return cert_file, key_file        # noch gueltig
        except Exception:
            pass                                   # defekt -> neu erzeugen

    os.makedirs(cert_dir := os.path.dirname(cert_file) or ".", exist_ok=True)
    host = socket.gethostname()
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "localhost"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "GREENBAY healthcare GmbH"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "CliniBots Patient Insight"),
    ])
    now = _dt.datetime.now(_dt.timezone.utc)
    san = [x509.DNSName("localhost"), x509.DNSName(host),
           x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
           x509.IPAddress(ipaddress.IPv6Address("::1"))]
    crt = (x509.CertificateBuilder()
           .subject_name(name).issuer_name(name)
           .public_key(key.public_key())
           .serial_number(x509.random_serial_number())
           .not_valid_before(now - _dt.timedelta(minutes=5))
           .not_valid_after(now + _dt.timedelta(days=days))
           .add_extension(x509.SubjectAlternativeName(san), critical=False)
           .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
           .sign(key, hashes.SHA256()))

    with open(key_file, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM,
                                  serialization.PrivateFormat.TraditionalOpenSSL,
                                  serialization.NoEncryption()))
    with open(cert_file, "wb") as f:
        f.write(crt.public_bytes(serialization.Encoding.PEM))
    try:            # Key nur fuer den eigenen Benutzer lesbar (No-Admin-taugliche ACL)
        os.chmod(key_file, 0o600)
    except OSError:
        pass
    return cert_file, key_file


def main():
    res = ensure_cert()
    if not res:
        raise SystemExit("cryptography fehlt — pip install cryptography")
    print(f"Zertifikat: {res[0]}\nSchluessel: {res[1]}")


if __name__ == "__main__":
    main()
