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

**3.3 Orgeinheit → IS-H-OE — LIVE GEPRÜFT (R19): keine automatische Brücke, kuratierte
Mapping-Tabelle nötig.** Die HR-`ORGEH` (OM-Objekt, 8-stellig, z. B. `50013834`) und die
IS-H-OE (`NORG.ORGID`, hausspezifisch, z. B. `A02-1`, `URO`) liegen in **verschiedenen
Coderäumen**. Verifizierte Befunde:
- `NORG.MIGRATED_OBJID` durchgängig `00000000` → **kein** Migrations-Link (verworfen).
- ID-Gleichheit `ORGEH ↔ ORGID`: nicht gegeben (numerisch vs. alphanumerisch).
- Kürzel `HRP1000.SHORT` (OTYPE='O') ↔ `NORG.OKURZ/ORGID`: nur **83–85 von 2.406**
  (~3,5 %); Name ↔ `STEXT`: 35. → als alleinige Brücke **nicht tragfähig**.
- Operativ relevant sind **232 Fachabteilungs-OEs** (`NBEW.ORGFA`), nicht alle 2.406.

**FINALE STRUKTUR R19c — `SETNODE` = KOSTENSTELLEN-HIERARCHIE; die Kostenstelle ist der
Pivot.** (Anweisung Björn: `SETNODE` ist maßgeblich; `test.ish_orgbaum`/
`test.WPHR_OE_Baum_mit_Kostenstelle` sind Prototypen und werden **nicht** verwendet.)
Live verifiziert:
- **`sap.SETNODE`** (Kanten Set→Subset via `SETNAME → SUBSETNAME`) + **`sap.SETLEAF`**
  (Blätter: `VALFROM/VALTO` = **10-stellige Kostenstellen**, z. B. `0093213300`) +
  **`sap.SETHEADERT`** (Set-Bezeichnungen, z. B. `AERZTE`, `ABGR`). Das ist die
  **Kostenstellen-Gruppen-Hierarchie** (SAP-CO, Klassen 0101–0103) — NICHT der
  OE-Kurzcode-Baum (die `NBEW.ORGFA`-Codes wie `GYNA` sind bewusst NICHT in SETLEAF).
- **Personenseite geschlossen:** `PA0001.KOSTL` (Mitarbeiter-Kostenstelle, 10-stellig
  `0090113000…`) liegt im Format der SETLEAF-Blätter; **10/10 Top-Kostenstellen im
  Set-Baum bestätigt**. → AD-Login → `PA0105`/90AD → PERNR → `PA0001.KOSTL` → Knoten im
  `SETNODE`-Baum → Roll-up auf Department-Knoten → Menge aller Kostenstellen darunter.

**Zielbild der Strecke (kostenstellenbasiert):**
```
AD-Login --PA0105/90AD--> PERNR --PA0001.KOSTL--> Kostenstelle
   --SETNODE/SETLEAF (Roll-up der KoStl-Gruppe)--> Menge KoStl des Departments (inkl. Unter)
   --[IS-H-OE -> Kostenstelle]  <== EINZIGE offene Kante
   --NBEW.ORGFA (IS-H-OE der Bewegung)--> sichtbare Patienten
```
Vorteil: Leitung erbt über die SETNODE-Rekursion automatisch alle Unter-Kostenstellen.

**Letzte Kante GESCHLOSSEN via `sap.NOEK` (Hinweis Björn).** `NOEK` mappt IS-H-OE →
Kostenstelle, zeitscheibenbasiert: `[MANDT, ORGFA, ORGPF, ENDDT]` → **`KOSTL`** (+`BEGDT`).
Live: 2.587 Zeilen, **510 ORGFA → 606 Kostenstellen**, alle mit KOSTL, 2.418 aktuell.
Stichprobe bestätigt: alle geprüften OEs (inkl. der zuvor „ungematchten" `KLCL`, `EMIS1`)
sind enthalten; `KOSTL` (`0093117100`…) liegt im selben 10-stelligen Raum wie `SETLEAF`
und `PA0001.KOSTL`. Eine OE kann auf mehrere Kostenstellen zeigen (je Pflege-OE/Periode).

**Vollständige, verifizierte Kette (Patient ⇄ Mitarbeiter über die Kostenstelle):**
```
Mitarbeiter: AD-Login --PA0105/90AD--> PERNR --PA0001.KOSTL--> Kostenstelle E
             --SETNODE/SETLEAF-Rollup--> Menge der Kostenstellen des Departments von E
Patient:     NBEW.ORGFA/ORGPF --NOEK--> Kostenstelle(n) des Falls
Sichtbar  ⇔  Fall-Kostenstelle ∈ Department-Kostenstellenmenge von E
```
Alle vier Joins live bestätigt (`PA0105`→PERNR, `PA0001`→KOSTL∈SETLEAF 10/10, `NOEK`→
KOSTL, `NBEW`→ORGFA∈NOEK). Zeitscheiben (`BEGDA/ENDDA`, `BEGDT/ENDDT`) je Join beachten;
Historie „war je in meiner Abteilung" = Bewegung, deren NOEK-Kostenstelle jemals unter dem
Department des Mitarbeiters lag. Medizincontrolling/IT/Einzel-Logins bleiben rollenbasiert
(alle Patienten).

---

**Historische Zwischenstände (verworfen):** (a) 3-Token-Match (~3,5 %), (b) Fach-Token
(76,5 %, aber grob), (c) `test.*`-Prototypbäume (nicht verwenden). Für Kontext siehe unten.

**Fach-Token (verworfen).** Die *aktuell gültigen* HR-Orgeinheiten
(`ISTAT='1'`, `ENDDA='9999-12-31'`) kodieren `SHORT = <DEPARTMENT>-<FACH>`, z. B.
`DOPM-URO` (Urologie), `DIND-NEU` (Neurologie). Zwei nutzbare Ebenen:
- **Department** (Präfix, ~15-20 Häuser): `DIND`, `DOPM`, `DM`, `DFKM`, `DKZM`, `DDIA`,
  `DBSM`, `DPSY`, … — grobe, robuste Gruppierung („Abteilung" im weiten Sinn).
- **Fach-Token** (3-stellig, Suffix): `URO`, `NEU`, `GYN`, `HNO`, … Die IS-H-`NBEW.ORGFA`
  sind Fach-Codes (`UROA`, `GYNA`, `HNOA`, `CH1A`, …). **65 von 85 IS-H-Fach-Tokens
  (76,5 %) matchen automatisch** einen HR-Fach-Token (statt 3,5 % beim plain-Kürzel).

**Empfohlener Weg (evidenzbasiert):** kuratierte, versionierte Mapping-Tabelle
`mcp.oe_mapping (department, hr_fach, ish_orgfa, gueltig_von/bis)`:
1. **Auto-Seed (~77 %)** über Fach-Token: `SUBSTRING(HRP1000.SHORT nach '-',3)` =
   `LEFT(NBEW.ORGFA,3)` — deckt die große Mehrheit der ~85 genutzten Fachcodes ab.
2. **Department-Gruppierung** aus dem SHORT-Präfix → Leitungskräfte/Departmentsicht erben
   alle Fach-OEs ihres Departments; `HRP1001` liefert zusätzlich die Feinhierarchie,
   `HRP1000.STEXT` die Klarnamen für die Pflege-UI.
3. **Manuelle Vervollständigung** der ~20 Rest-Tokens (kein Auto-Match) durch das
   Medizincontrolling — klein, verlustfrei, auditierbar.

Bis das Mapping vollständig ist, gilt für Abteilungspersonal *fail-closed* (nur explizit
gemappte Fach-OEs sichtbar); Medizincontrolling/IT/Einzel-Logins sind davon unabhängig
sofort nutzbar. HRP1000/1001 tragen **Resolution (AD→PERNR→ORGEH), Department-Struktur,
Hierarchie und Namen**; die Fach-Token-Heuristik seedet die OE-Zuordnung zu ~77 %.

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
