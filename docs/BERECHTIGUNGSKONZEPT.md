# Berechtigungskonzept — CliniBots Patient Insight

**Stand:** R19 (Live `higl-main`). **Prinzip:** *deny-by-default* — kein Patient ohne
explizite Berechtigung sichtbar. Jeder Patientenzugriff wird auditiert (Hash-Kette wie
CliniBots MDM). **Zweckbindung:** Sekundärnutzung Medizincontrolling/IT; die
Zugriffsgrenze für Abteilungspersonal folgt der tatsächlichen Behandlungsbeteiligung.

> **HRP-Scope (neue Anweisung Björn, R19):** Das `hrp`-Schema war bisher ausgeklammert.
> Für die **Berechtigungs-/Datenverfügbarkeits-Strecke** ist es jetzt IN Scope — jedoch
> ausschließlich für Auth/RBAC (Mitarbeiter↔Abteilung), NICHT für die klinisch-
> analytische FHIR-Ausleitung. Mitarbeiter-Personendaten unterliegen derselben
> Verkryptungspflicht wie Patientendaten.

## 1. Rollenmodell
| Rolle | Sichtbare Patienten | Quelle der Zuordnung |
|---|---|---|
| **Medizincontrolling** | alle | Rollen-Flag (AD-Gruppe / lokales Login) |
| **IT / Admin** | alle | Rollen-Flag |
| **Abteilungspersonal** | nur Patienten, die **jemals** eine Bewegung (`NBEW`) in einer OE hatten, der die Person zugeordnet ist/war | HR-Strecke (§3) |
| **Einzel-Logins (z. B. Björn)** | konfigurierbar (i. d. R. Medizincontrolling/Admin) | separates Login + explizite Rolle |

Regel Abteilungspersonal (Kern): Patient P sichtbar für Mitarbeiter E
⇔ ∃ Fall F von P mit ∃ Bewegung B∈`NBEW`(F) mit `B.OE ∈ OE(E)`, wobei `OE(E)` die
Menge aller IS-H-Organisationseinheiten ist, denen E über die Zeit zugeordnet war.
**Historisch** (nicht nur aktuell): war der Patient je in „meiner" Abteilung, bleibt er
sichtbar — deckt Verlegungen/Wiederaufnahmen ab.

## 2. Zugang (Authentifizierung)
- **AD / SSO** (Regelfall): Windows-Login → Abgleich gegen SAP-HR (§3.1). AD-Gruppen
  können zusätzlich die Rollen Medizincontrolling/IT setzen.
- **Separate Logins** (für definierte Einzelnutzer, z. B. Björn): lokales Konto mit
  Passwort im Windows Credential Manager (wie `mdmgmt.credentials`), explizite Rollen-
  und optional OE-Zuweisung. Kein AD nötig.
- Betrieb weiterhin loopback/on-prem; bei Netzbetrieb TLS + Reverse-Proxy vorschalten.

## 3. Datenverfügbarkeit über die HR-Strecke (live verifiziert)
Kette **AD-Login → PERNR → Orgeinheit(en) → IS-H-OE → NBEW → Patient**:

**3.1 AD-Login → PERNR** — `hrp.PA0105` (Kommunikation), **SUBTY `90AD`** (37.803 Zeilen)
trägt den AD-/Windows-Benutzernamen in `USRID`, je PERNR, zeitscheibenbasiert
(`BEGDA`/`ENDDA`). (Weitere Subtypen: `0010` E-Mail, `90OS`/`90ST` andere Systeme.)
```sql
SELECT PERNR FROM hrp.PA0105
WHERE SUBTY='90AD' AND UPPER(USRID)=UPPER(?) AND ? BETWEEN BEGDA AND ENDDA;
```

**3.2 PERNR → Orgeinheit** — `hrp.PA0001` (Organisatorische Zuordnung, 364.611 Zeilen):
`ORGEH` (Orgeinheit), `PLANS` (Planstelle), `KOSTL` (Kostenstelle), `WERKS`/`BTRTL`,
zeitscheibenbasiert. Alle je PERNR gültigen `ORGEH` über die Zeit = die HR-Abteilungen
des Mitarbeiters.

**3.3 Orgeinheit → IS-H-OE — OFFENER PUNKT (kritische Brücke).** Die HR-`ORGEH`
(OM-Objekt, 8-stellig) ist nicht zwingend identisch mit der IS-H-OE in
`NBEW.OE/ORGFA/ORGPF` bzw. `NORG`. Zu verifizieren (nächster Schritt, mit Daten):
1. **Direktgleichheit** prüfen: Schnittmenge `PA0001.ORGEH` ↔ `NORG.ORGID/OE`.
2. **`NORG`-Referenz**: trägt `NORG` ein HR-Feld (ORGEH/Planstelle)? → direkter Join.
3. **HRP1001-Relationen**: OM-Struktur (O→O/S→O) auf IS-H-OE abbilden.
4. **Fallback**: kuratierte Mapping-Tabelle `mcp.oe_mapping (orgeh → ish_oe)`, gepflegt
   vom Medizincontrolling (verlustfrei, versioniert).
Bis zur Klärung gilt für Abteilungspersonal *fail-closed* (keine Sicht), Medizincontrolling/
IT/Einzel-Logins sind davon unabhängig sofort nutzbar.

**3.4 IS-H-OE → Patient** — über die Bewegungen:
```sql
-- sichtbare Faelle je Mitarbeiter (historisch, alle je zugeordneten OE)
SELECT DISTINCT f.PATNR
FROM mcp.bewegung b JOIN mcp.fall f USING (FALNR)
WHERE b.OE IN (/* OE(E) aus 3.1-3.3 */);
```

## 4. Durchsetzung (Enforcement)
- **Row-Level in der `mcp.*`/Gold-Schicht**: zentrale Sicht
  `mcp.sichtbare_patienten(user)` (Rolle → alle; Abteilung → Join 3.4). Patient-360-API
  und alle patientenbezogenen Endpoints filtern gegen diese Sicht — **serverseitig**,
  nicht im Client.
- **Deny-by-default**: unbekannter Nutzer / fehlende Rolle / ungelöste OE-Brücke ⇒ keine
  Patienten.
- **Audit**: jeder Patientenzugriff (wer, wann, welche PATNR, Rolle, Trefferbegründung)
  in die Hash-Kette (`audit.append`, Muster aus CliniBots MDM). Kein Klartext-Name.
- **Zweck-/Feldschutz**: Verkryptung bleibt aktiv; die Berechtigung steuert *welche
  Patienten*, nicht die Aufhebung der Feld-Maskierung.

## 5. Datenmodell (Auth-Schicht, getrennt von Analytik)
Neue, gesicherte Auth-Tabellen (eigene Schicht, nicht in den Analytik-Marts):
- `auth_benutzer(login, typ[AD|lokal], rolle, aktiv)` — lokale Logins + Rollen-Overrides.
- `auth_pernr_map(login → PERNR)` — materialisiert aus PA0105/90AD (Nightly), oder live.
- `auth_oe(PERNR → ish_oe[])` — materialisiert aus PA0001 (+OE-Bridge §3.3).
- Auflösung zur Laufzeit: `login → rolle`; bei Abteilungsrolle `login → PERNR → ish_oe[] →
  PATNR[]`.

## 6. Offene Punkte / nächste Schritte
1. **OE-Brücke (§3.3) verifizieren** — der einzige echte Blocker für die Abteilungsrolle.
2. `PA0001`/`PA0105`/`HRP1000`/`HRP1001` in die Registry aufnehmen (Auth-Scope) + Dreiklang.
3. Auth-Modul implementieren (Resolver + Row-Level-Sicht + Audit) — nach OE-Klärung.
4. Mitarbeiter-Personendaten (PA0002 Name, PA0105 USRID) nur in der Auth-Schicht, nie in
   Analytik/Export; Verkryptung/DSGVO-Löschkonzept anwenden.
