# Patienten-Datenkatalog — CliniBots Patient Insight

**Zweck:** vollständige, reproduzierbare Inventur **aller patientenbezogenen Tabellen**
(`sap`-Schema, Spalte `PATNR` und/oder `FALNR`, befüllt). Grundlage für die Zusage
„zu einem Patienten müssen ALLE Daten verfügbar gemacht werden". Stand: R19 (Live
`higl-main`).

## 1. Mengengerüst (Live)
- `sap`-Schema: **977 Basistabellen** (ohne `__ct`), davon **790 befüllt**.
- Davon **patientenbezogen (PATNR/FALNR, befüllt): 77 Tabellen** — das ist der
  verbindliche Umfang für Patient-360/„alle Daten".
- Im kuratierten Katalog (`config/tables.yaml`, Dreiklang-verifiziert): **40 der 77**.
- **Noch NICHT katalogisiert: 37** (siehe §3) — davon mehrere großvolumig/klinisch relevant.
- `hrp`-Schema (304 Tabellen) war bisher ausgeklammert → jetzt für die Berechtigungs-/
  HR-Strecke im Scope (siehe `docs/BERECHTIGUNGSKONZEPT.md`).

**Reproduzieren** (Katalog neu erzeugen):
```sql
SELECT c.TABLE_NAME,
  MAX(CASE WHEN c.COLUMN_NAME='PATNR' THEN 1 ELSE 0 END) AS patnr,
  MAX(CASE WHEN c.COLUMN_NAME='FALNR' THEN 1 ELSE 0 END) AS falnr, SUM(p.rows) rows
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN sys.tables t ON t.name=c.TABLE_NAME JOIN sys.schemas s ON s.schema_id=t.schema_id AND s.name=c.TABLE_SCHEMA
JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE c.TABLE_SCHEMA='sap' AND c.TABLE_NAME NOT LIKE '%\_\_ct%' ESCAPE '\'
  AND c.COLUMN_NAME IN ('PATNR','FALNR') GROUP BY c.TABLE_NAME HAVING SUM(p.rows)>0;
```

## 2. Antwort auf „hast du alle ISH/ISHmed-Tabellen abgearbeitet?"
**Nein — bewusst nicht alle 790, aber der klinisch/analytisch relevante Kern.** Die
Registry deckt NPAT-zentriert + DIAS-genutzt + RKT/MD-Management ab (Dreiklang-verifiziert).
Für die Patienten-Vollständigkeit zählt jedoch die 77er-Liste — und dort fehlen **37**.
Ein „Datenkatalog" existiert (`config/tables.yaml` = kuratierte Registry mit PK/FHIR/
Tier/CDC/Befunden); dieses Dokument ergänzt ihn um die **vollständige patientenbezogene
Abdeckungssicht**.

## 3. Lücken — patientenbezogene Tabellen NOCH NICHT im Katalog (37)
Priorität nach Zeilen/klinischem Wert. **Vor Freigabe „alle Daten" je Tabelle Dreiklang
fahren** (PK, Fill, Verkryptungsbedarf).

### Hoch (großvolumig / klinisch-erlösrelevant)
| Tabelle | Schlüssel | Zeilen | Vermutung / Aufgabe |
|---|---|---:|---|
| `NLKZ` | FALNR | 64.017.773 | Leistungs-Kennzahlen (Erlös) — Familie NLEI/NLKZ/NLLZ |
| `NCIR` | PATNR+FALNR | 24.291.556 | **VERIFY Domäne** (großes Transaktionsobjekt, unklar) |
| `NLLZ` | FALNR | 19.892.409 | Leistungs-/Lieferzeilen (Erlös) |
| `ZCOPRA_01` | FALNR | 7.088.719 | **COPRA-Brücke** → Medikation/Vitalwerte (der in CLAUDE.md gesuchte Pfad!) |
| `N1FAT` | PATNR | 4.800.969 | Patiententransport/Fahrten |
| `N2DWSWL_TASK` | PATNR | 3.389.420 | DWS-Worklist (i.s.h.med Arbeitsliste) |
| `NLICZ` | FALNR | 1.349.291 | Leistungs-ICD-Zuordnung? VERIFY |
| `NDOC_ZNA` | PATNR+FALNR | 1.282.780 | ZNA-(Notaufnahme-)Dokumente (NDOC-Struktur) |
| `NDOCSTORNO` | PATNR+FALNR | 625.994 | stornierte Dokumente |
| `NMBG` / `NAMB` | FALNR | 144.823 / 142.656 | Mitbehandlung / Ambulanz-Zuordnung |
| `ZISH_COPRA_FALNR` | FALNR | 35.011 | COPRA↔IS-H-FALNR-Mapping |

### Mittel (Indizes / Versicherung / Custom)
`NPIX` (1,56 M Patienten-Index), `NPAE` (1,46 M Patienten-Ergänzung), `NVVP` (bereits
tw. bekannt), `N1ANF` (Anforderung), `NRSF`, `NPFO`, `NSTREM`, `NC301CEX`,
`YJWZBP`/`YJWZBK` (Haus-Y-Tabellen, VERIFY), `ZNV2000IS_SUBSCR`, `ZISH_BETT_FAL_BW`.

### Forschung / Spezialmodule
`ZBIO_T201`/`ZBIO_T202` (Biobank), `/UKL/PAT_STUDIE` (Studienteilnahme),
`/UKU/3CTUTMS_PAT`/`/UKU/3CTDIAGNOSI`/`/UKU/3CTEMAIL_P` (Tumordoku UKU-Namespace).

### Gehören zu CliniBots MDM (RKT/MD-Management, dort teils katalogisiert)
`ZNRKT_MCS_TXT`, `ZNRKT_REKL_TXT`, `ZNRKT_MDK_TXT`, `ZNRKT_KLA_TXT`, `ZNRKT_KG_TXT`,
`ZNRKT_TOB_TXT`, `ZNRKT_BERMAHN`, `/SMS/RKT_FRIST`, `/SMS/RKT_EDI`, `/SMS/RKT_AUF_TXT`.

## 4. Konsequenz für Patient 360
Die Fall-/Patientenakte muss diese 77 Tabellen als **vollständigen Verfügbarkeits-Rahmen**
führen. Aktuell bindet Patient 360 den Kern (NPAT/NFAL/NBEW/NDIA/NICP/N2LABOR/NDOC/
Timeline). Offene Anbindung v. a.: COPRA (Medikation/Vitalwerte über ZCOPRA_01/
ZISH_COPRA_FALNR), NLKZ/NLLZ (Erlös), NDOC_ZNA/NDOCSTORNO (Dokumente vollständig),
NMBG/NAMB, Forschungsmodule. → Backlog, jede Tabelle mit Dreiklang + Verkryptungsprüfung.
