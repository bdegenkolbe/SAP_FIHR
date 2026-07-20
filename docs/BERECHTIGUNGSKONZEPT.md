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

**KORREKTUR R19b — der 3-Steller ist zu grob; es gibt einen echten IS-H-OE-BAUM.**
(Hinweis Björn.) Fundstellen live:
- **`test.ish_orgbaum`** — flachgeklopfter **IS-H-OE-Baum** (aus `sap.SETNODE`/`NORG`):
  `OEID → Parent`, `Ebene`, `Pfad`, `Wurzel`, `OE_Typ` ((K) Klinik/Institut, (U) UKL-
  Bereich, (D) Fremde), `Ebene1..6`. **2.271 OEs**; deckt **227 der 232 genutzten
  `NBEW.ORGFA` (97,8 %)** ab → korrektes Roll-up Station→Klinik→Bereich statt 3-Token.
- **`test.WPHR_OE_Baum_mit_Kostenstelle`** — **HR-Seite**: `AD_Login → OE_ID → OE_KOSTL
  (Kostenstelle) → 10-stufige Hierarchie`, **6.164 AD-Logins**.
- Basisquelle des Baums: `sap.SETNODE` (SAP-Set-Hierarchie) + `dbo.SETNODE_Baumstrukturen_v1`
  (Echtzeit-Flachung). `NORG.ORGZU` ist KEIN Parent-Pointer (nur Namensfortsetzung).

**Verbindung der beiden Bäume:** `WPHR.OE_ID` (HR-Raum, 20.689 IDs) hat **0 Überschneidung**
mit `ish_orgbaum.OEID`/`NORG.ORGID` → **kein gemeinsamer OE-Code**. Der Pivot ist die
**Kostenstelle**: HR-Seite `WPHR.OE_KOSTL` bzw. `PA0001.KOSTL` (je PERNR) ↔ IS-H-OE-
Kostenstelle. **Nächste Verifikation:** IS-H-OE→Kostenstelle-Quelle (Kandidaten:
`NORG.KSTKZ`, `ZNKVOE`, `ZNRKT_C_CENT_OE`). Alternativ liefert `WPHR` bereits
`AD_Login → OE_KOSTL` fertig; fehlt nur `IS-H-OE (NBEW.ORGFA) → Kostenstelle`.

**Neues Zielbild der Strecke (baumbasiert):**
```
AD-Login --WPHR/PA0105--> PERNR/OE_KOSTL(Kostenstelle)
   --[Kostenstelle<->IS-H-OE]--> IS-H-OE
   --ish_orgbaum (Roll-up ueber Pfad/Ebene)--> Menge zustaendiger OEs (inkl. Unter-OEs)
   --NBEW.ORGFA--> sichtbare Patienten
```
Vorteil: Leitungsebene erbt via `Pfad`/`Ebene` automatisch alle Unter-OEs (Bereich→Kliniken→
Stationen). **Caveat:** `test.*` sind Prototypen (Provenienz/Refresh unklar) — die Logik
(`SETNODE`→`ish_orgbaum`, HR-Baum) in die eigene Pipeline produktiv nachbauen, nicht auf
`test.*` verlassen.

---

**Historischer Zwischenstand (verworfen): Fach-Token.** Die *aktuell gültigen* HR-Orgeinheiten
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
