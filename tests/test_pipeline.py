# -*- coding: utf-8 -*-
"""Tests fuer Merge-Layer (bronze_current, Compaction), Lastfenster und
Guard-Haertung — alles ohne Live-DB (temporaere Parquet-Fixtures).
"""
import datetime as dt
import os
import sys

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.extract import merge as MG
from sapfhir.extract.window import in_window, Window
from sapfhir.mcp import guard as G
from sapfhir.mcp.audit import Audit, verify

REG = {"NFAL": {"schema": "sap", "pk": ["MANDT", "EINRI", "FALNR"],
                "partition_date": "BEGDT", "cdc": "ct", "tier": 1}}


def _seed_bronze(tmp_path):
    base = tmp_path / "bronze" / "nfal" / "jahr=2026"
    base.mkdir(parents=True)
    rows = [
        {"MANDT": "100", "EINRI": "01", "FALNR": "F1", "PATNR": "P1",
         "BEGDT": "2026-01-01", "ENDAT": "2026-01-05", "STORN": ""},
        {"MANDT": "100", "EINRI": "01", "FALNR": "F2", "PATNR": "P2",
         "BEGDT": "2026-02-01", "ENDAT": None, "STORN": ""},
    ]
    pq.write_table(pa.Table.from_pylist(rows), str(base / "part-0.parquet"))
    delta = tmp_path / "bronze" / "_delta" / "nfal"
    delta.mkdir(parents=True)
    drows = [
        # Update: F2 bekommt ein Fallende
        {"MANDT": "100", "EINRI": "01", "FALNR": "F2", "PATNR": "P2",
         "BEGDT": "2026-02-01", "ENDAT": "2026-02-10", "STORN": "",
         "_op": "U", "_seq": "001"},
        # Delete: F1 verschwindet aus bronze_current
        {"MANDT": "100", "EINRI": "01", "FALNR": "F1", "PATNR": "P1",
         "BEGDT": "2026-01-01", "ENDAT": None, "STORN": "",
         "_op": "D", "_seq": "002"},
    ]
    pq.write_table(pa.Table.from_pylist(drows), str(delta / "seq-1.parquet"))
    return str(tmp_path / "bronze")


def test_bronze_current_last_write_wins(tmp_path):
    bronze = _seed_bronze(tmp_path)
    con = duckdb.connect()
    made = MG.create_views(con, REG, bronze)
    assert made == ["nfal"]
    rows = con.execute(
        "SELECT FALNR, ENDAT FROM bronze_current.nfal ORDER BY FALNR").fetchall()
    # F1 geloescht, F2 mit Delta-Update
    assert rows == [("F2", "2026-02-10")]


def test_compaction_faltet_deltas_ein(tmp_path):
    bronze = _seed_bronze(tmp_path)
    con = duckdb.connect()
    MG.create_views(con, REG, bronze)
    n = MG.compact_table(con, "NFAL", REG["NFAL"], bronze)
    assert n == 1   # eine Delta-Datei eingefaltet
    # Delta-Ordner leer, Archiv gefuellt
    assert not os.listdir(os.path.join(bronze, "_delta", "nfal"))
    assert os.listdir(os.path.join(bronze, "_delta_archive", "nfal"))
    # View neu erzeugen: Ergebnis unveraendert (idempotent nach Compaction)
    MG.create_views(con, REG, bronze)
    rows = con.execute(
        "SELECT FALNR, ENDAT FROM bronze_current.nfal ORDER BY FALNR").fetchall()
    assert rows == [("F2", "2026-02-10")]


def test_window_logik():
    # normales Fenster
    assert in_window(dt.time(2, 0), "01:00", "06:00")
    assert not in_window(dt.time(12, 0), "01:00", "06:00")
    # Fenster ueber Mitternacht
    assert in_window(dt.time(23, 0), "22:00", "05:00")
    assert in_window(dt.time(3, 0), "22:00", "05:00")
    assert not in_window(dt.time(12, 0), "22:00", "05:00")


def test_window_wartet_bis_fensterbeginn():
    slept = []
    w = Window({"start": "01:00", "end": "06:00"},
               sleep_fn=slept.append,
               now_fn=lambda: dt.datetime(2026, 7, 15, 12, 0))
    waited = w.wait()
    assert waited == slept[0] == 13 * 3600   # 12:00 -> 01:00 naechster Tag
    w2 = Window({"start": "01:00", "end": "06:00"},
                sleep_fn=slept.append,
                now_fn=lambda: dt.datetime(2026, 7, 15, 2, 0))
    assert w2.wait() == 0.0


def test_guard_blockt_dateifunktionen_und_fremde_schemata():
    with pytest.raises(G.GuardError):
        G.check_sql("SELECT * FROM read_csv('/etc/passwd')")
    with pytest.raises(G.GuardError):
        G.check_sql("SELECT * FROM read_parquet('data/bronze/npat/*.parquet')")
    with pytest.raises(G.GuardError):
        G.check_sql("SELECT * FROM bronze_current.npat")
    with pytest.raises(G.GuardError):
        G.check_sql("SELECT * FROM silver.fhir_index")
    # mcp.* ist erlaubt; String-Literale duerfen boese Woerter enthalten
    assert G.check_sql("SELECT * FROM mcp.fall WHERE FACHR = 'DROP'")
    assert G.check_sql("WITH x AS (SELECT * FROM mcp.diagnose) SELECT * FROM x")


def test_guard_cypher_blockt_load():
    with pytest.raises(G.GuardError):
        G.check_cypher("MATCH (n) CALL something() RETURN n")
    assert G.check_cypher("MATCH (p:Patient) RETURN p LIMIT 5")


def test_audit_hash_kette(tmp_path):
    p = str(tmp_path / "audit.jsonl")
    a = Audit(p)
    a.log("patient_search", {"patnr": "P1"}, 1, 0.01)
    a.log("cohort_sql", {"sql": "SELECT 1"}, 1, 0.02)
    ok, n = verify(p)
    assert ok and n == 2
    # Manipulation bricht die Kette
    lines = open(p).read().splitlines()
    lines[0] = lines[0].replace('"rows": 1', '"rows": 999')
    open(p, "w").write("\n".join(lines) + "\n")
    ok2, _ = verify(p)
    assert not ok2
    # Klarparameter tauchen nicht im Log auf
    assert "P1" not in open(p).read()


def test_lookups_katalog_und_fallback(tmp_path):
    """Katalog vorhanden -> Klartext; Katalog fehlt -> Fallback-Enum greift."""
    from sapfhir.fhir.lookups import Lookups
    from sapfhir.fhir import ids as I
    from sapfhir.fhir.mappers import core as M

    base = tmp_path / "bronze" / "tn14t"
    base.mkdir(parents=True)
    pq.write_table(pa.Table.from_pylist([
        {"MANDT": "100", "EINRI": "01", "BEWTY": "2", "BEWTX": "Entlassung (Haustext)"},
    ]), str(base / "part-0.parquet"))
    con = duckdb.connect()
    reg = {"TN14T": {"schema": "sap", "pk": ["MANDT", "EINRI", "BEWTY"],
                     "cdc": "full", "tier": 1}}
    MG.create_views(con, reg, str(tmp_path / "bronze"))
    lk = Lookups(con)
    assert "bewegungstyp" in lk.loaded
    assert lk.bewegungstyp("2") == "Entlassung (Haustext)"
    assert lk.bewegungstyp("99") is None

    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "01", "FALNR": "F1", "LFDNR": "1",
           "BEWTY": "2", "BWIDT": "2026-01-01", "STORN": ""}
    # mit Katalog: Haustext
    res = M.map_encounter_bewegung(row, ns, None, patnr="P1", lookups=lk)
    assert res["type"][0]["text"] == "Entlassung (Haustext)"
    # ohne Katalog: verifizierte Fallback-Enum (BEWTY 2=Entlassung, VERIFY_RESULTS_4)
    res2 = M.map_encounter_bewegung(row, ns, None, patnr="P1", lookups=None)
    assert res2["type"][0]["text"] == "Entlassung"
