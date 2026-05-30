#!/usr/bin/env python3
"""F1 시즌 standings seed 생성 (Jolpica/Ergast API → CSV).
   드라이버/컨스트럭터 챔피언십 순위를 시즌별로 수집."""
import csv
import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = ROOT / "seeds"
SEEDS.mkdir(exist_ok=True)

SEASONS = range(2010, 2025)   # 2010~2024
BASE = "https://api.jolpi.ca/ergast/f1"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "dbt-playground"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


# ── 드라이버 standings ──────────────────────────────────────────────────
drivers = []
constructors = []
for season in SEASONS:
    d = get(f"{BASE}/{season}/driverStandings.json?limit=100")
    lists = d["MRData"]["StandingsTable"]["StandingsLists"]
    if lists:
        for s in lists[0]["DriverStandings"]:
            drv = s["Driver"]
            team = s["Constructors"][-1]["name"] if s.get("Constructors") else ""
            drivers.append({
                "season": season,
                "position": int(s.get("position") or 0),
                "driver_id": drv["driverId"],
                "driver_name": f'{drv["givenName"]} {drv["familyName"]}',
                "code": drv.get("code", ""),
                "constructor": team,
                "points": float(s.get("points") or 0),
                "wins": int(s.get("wins") or 0),
            })
    time.sleep(0.4)

    c = get(f"{BASE}/{season}/constructorStandings.json?limit=100")
    clists = c["MRData"]["StandingsTable"]["StandingsLists"]
    if clists:
        for s in clists[0]["ConstructorStandings"]:
            con = s["Constructor"]
            constructors.append({
                "season": season,
                "position": int(s.get("position") or 0),
                "constructor_id": con["constructorId"],
                "constructor_name": con["name"],
                "points": float(s.get("points") or 0),
                "wins": int(s.get("wins") or 0),
            })
    time.sleep(0.4)
    print(f"  {season}: drivers={len(lists[0]['DriverStandings']) if lists else 0}")

with (SEEDS / "f1_driver_standings.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "season", "position", "driver_id", "driver_name", "code",
        "constructor", "points", "wins"])
    w.writeheader()
    w.writerows(drivers)
print(f"f1_driver_standings.csv: {len(drivers)} rows")

with (SEEDS / "f1_constructor_standings.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "season", "position", "constructor_id", "constructor_name",
        "points", "wins"])
    w.writeheader()
    w.writerows(constructors)
print(f"f1_constructor_standings.csv: {len(constructors)} rows")
