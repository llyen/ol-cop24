"""Odtwarzanie scenariusza kryzysowego COP-24 w czasie rzeczywistym.

Zasilanie idzie bezposrednio przez streaming ingestion Eventhouse (REST), dzieki czemu
kazde zdarzenie jest widoczne w dashboardzie w czasie ponizej sekundy od wyslania.

Uzycie:
    python scenario/replay.py --reset --speed 3600
    python scenario/replay.py --speed 600 --from 2026-09-14T00:00:00Z
"""
from __future__ import annotations

import argparse
import json
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATASETS = ROOT / "datasets"
CONFIG = ROOT / "scenario" / "scenario.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


# --- uwierzytelnianie -------------------------------------------------------

class TokenCache:
    """Token Kusto z az CLI, odswiezany zanim wygasnie."""

    def __init__(self, resource: str = "https://kusto.kusto.windows.net"):
        self.resource = resource
        self._token = None
        self._expires = datetime.now(timezone.utc)
        self._lock = threading.Lock()

    def get(self) -> str:
        with self._lock:
            if self._token and datetime.now(timezone.utc) < self._expires:
                return self._token
            cmd = ["az", "account", "get-access-token", "--resource", self.resource, "-o", "json"]
            out = subprocess.run(cmd, capture_output=True, text=True, shell=(sys.platform == "win32"))
            if out.returncode != 0:
                raise SystemExit(f"az account get-access-token nie powiodlo sie: {out.stderr.strip()}")
            data = json.loads(out.stdout)
            self._token = data["accessToken"]
            self._expires = datetime.now(timezone.utc) + timedelta(minutes=45)
            return self._token


# --- klient Kusto -----------------------------------------------------------

class KustoClient:
    def __init__(self, cluster: str, database: str, tokens: TokenCache):
        self.cluster = cluster.rstrip("/")
        self.database = database
        self.tokens = tokens

    def _post(self, url: str, body: bytes) -> bytes:
        last = None
        for attempt in range(5):
            req = urllib.request.Request(url, data=body, method="POST")
            req.add_header("Authorization", f"Bearer {self.tokens.get()}")
            req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    return resp.read()
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")[:400]
                last = f"HTTP {exc.code}: {detail}"
                # 429 i 5xx sa przejsciowe, pozostalych nie ma sensu ponawiac
                if exc.code not in (429, 500, 502, 503, 504):
                    raise SystemExit(f"{url}\n{last}")
            except urllib.error.URLError as exc:
                last = str(exc)
            time.sleep(min(2 ** attempt, 15))
        raise SystemExit(f"Nie udalo sie wykonac zadania po 5 probach: {last}")

    def mgmt(self, csl: str):
        body = json.dumps({"db": self.database, "csl": csl}).encode("utf-8")
        return json.loads(self._post(f"{self.cluster}/v1/rest/mgmt", body))

    def query(self, csl: str):
        body = json.dumps({"db": self.database, "csl": csl}).encode("utf-8")
        return json.loads(self._post(f"{self.cluster}/v1/rest/query", body))

    def scalar(self, csl: str):
        rows = self.query(csl)["Tables"][0]["Rows"]
        return rows[0][0] if rows else None

    def table_columns(self, table: str):
        raw = self.mgmt(f".show table {table} schema as json")["Tables"][0]["Rows"][0][1]
        return [c["Name"] for c in json.loads(raw)["OrderedColumns"]]

    def ensure_mapping(self, table: str, columns, mapping_name: str = "scenario_map"):
        mapping = [{"column": c, "Properties": {"Path": f"$.{c}"}} for c in columns]
        literal = json.dumps(mapping, ensure_ascii=False).replace("\\", "\\\\").replace("'", "\\'")
        self.mgmt(f".create-or-alter table {table} ingestion json mapping '{mapping_name}' '{literal}'")

    def ingest(self, table: str, ndjson: str, mapping_name: str = "scenario_map"):
        url = (f"{self.cluster}/v1/rest/ingest/{self.database}/{table}"
               f"?streamFormat=json&mappingName={mapping_name}")
        self._post(url, ndjson.encode("utf-8"))

    def ingest_from_onelake(self, table: str, url: str, mapping_name: str = "scenario_map") -> str:
        """Ingestia wsadowa z OneLake. Dane trafiaja do ekstentow, wiec zapytania sa szybkie."""
        csl = (f".ingest async into table {table} (h'{url};impersonate') "
               f"with (format='json', ingestionMappingReference='{mapping_name}')")
        return self.mgmt(csl)["Tables"][0]["Rows"][0][0]

    def wait_for_operation(self, operation_id: str, timeout_s: int = 900) -> str:
        """Czeka na zakonczenie operacji. Kolumne State szukamy po nazwie,
        bo kolejnosc kolumn w .show operations nie jest gwarantowana."""
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            table = self.mgmt(f".show operations {operation_id}")["Tables"][0]
            names = [c["ColumnName"] for c in table["Columns"]]
            if "State" not in names:
                raise SystemExit(f".show operations nie zwrocilo kolumny State: {names}")
            idx = names.index("State")
            rows = table["Rows"]
            if rows:
                state = rows[-1][idx]
                if state not in ("InProgress", "Scheduled"):
                    return state
            time.sleep(3)
        return "Timeout"

    def delete_from(self, table: str, cutoff_iso: str):
        csl = f".delete table {table} records <| {table} | where timestamp >= datetime({cutoff_iso})"
        self.mgmt(csl)


# --- rownolegla wysylka -----------------------------------------------------

class IngestPool:
    """Pula watkow wysylajacych partie do Eventhouse.

    Pojedyncze zadanie HTTP kosztuje ok. 100 ms, wiec przy szeregowej wysylce
    przepustowosc spada do ~250 zdarzen/s. Scenariusz w tempie 3600x wymaga
    ok. 1850 zdarzen/s, dlatego partie ida rownolegle.
    """

    def __init__(self, client: "KustoClient", workers: int = 8, max_queue: int = 64):
        self.client = client
        self.queue: "queue.Queue" = queue.Queue(maxsize=max_queue)
        self.sent = 0
        self.error = None
        self._lock = threading.Lock()
        self._threads = [threading.Thread(target=self._worker, daemon=True) for _ in range(workers)]
        for t in self._threads:
            t.start()

    def _worker(self):
        while True:
            item = self.queue.get()
            try:
                if item is None:
                    return
                table, rows = item
                try:
                    self.client.ingest(table, "\n".join(rows))
                    with self._lock:
                        self.sent += len(rows)
                except BaseException as exc:  # noqa: BLE001 - blad watku musi dotrzec do glownego
                    with self._lock:
                        self.error = self.error or str(exc)
            finally:
                self.queue.task_done()

    def submit(self, table: str, rows):
        if self.error:
            raise SystemExit(f"Blad wysylki: {self.error}")
        self.queue.put((table, rows))

    def drain(self):
        self.queue.join()
        if self.error:
            raise SystemExit(f"Blad wysylki: {self.error}")

    def close(self):
        for _ in self._threads:
            self.queue.put(None)
        for t in self._threads:
            t.join(timeout=30)


# --- odtwarzanie ------------------------------------------------------------

def parse_ts(value: str) -> datetime:
    ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return ts.replace(tzinfo=timezone.utc) if ts.tzinfo is None else ts


def load_config(path: Path) -> dict:
    if not path.exists():
        raise SystemExit(f"Brak {path}. Uruchom scenario\\run_scenario.ps1, ktory go tworzy.")
    return json.loads(path.read_text(encoding="utf-8"))


def load_events(streams, start, end):
    """Wczytuje i scala strumienie, sortujac po czasie zdarzenia."""
    events = []
    for stream in streams:
        path = DATASETS / f"{stream}.jsonl"
        if not path.exists():
            print(f"  [pomijam] brak {path.name}")
            continue
        count = 0
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                ts = parse_ts(ev["timestamp"])
                if start and ts < start:
                    continue
                if end and ts > end:
                    continue
                events.append((ts, stream, ev))
                count += 1
        print(f"  {stream}: {count} zdarzen")
    events.sort(key=lambda item: item[0])
    return events


def reset_tables(client: KustoClient, streams):
    print("=== Reset: czyszczenie tabel strumieniowych")
    # Czyszczenie potrafi sie nie udac, gdy trwa jeszcze poprzednia ingestia.
    # Bez ponowienia tlo doladowaloby sie na istniejace dane i liczby bylyby podwojone.
    for stream in streams:
        cleared = False
        for attempt in range(6):
            try:
                client.mgmt(f".clear table {stream} data")
                if client.scalar(f"{stream} | count") == 0:
                    cleared = True
                    break
            except SystemExit:
                pass
            time.sleep(10 * (attempt + 1))
            print(f"  [ponawiam] {stream}")
        if not cleared:
            raise SystemExit(f"Nie udalo sie wyczyscic tabeli {stream}. Poczekaj i uruchom ponownie.")
        print(f"  [OK] wyczyszczono {stream}")
    # hydro_readings_rt jest destynacja Eventstreamu i bywa zablokowana - jest opcjonalna.
    try:
        client.mgmt(".clear table hydro_readings_rt data")
        print("  [OK] wyczyszczono hydro_readings_rt")
    except SystemExit:
        print("  [POMINIETO] hydro_readings_rt (destynacja Eventstreamu)")


def bulk_load(client: KustoClient, streams, base_url: str, cutoff: datetime):
    """Wczytuje tlo scenariusza ingestia wsadowa i obcina je do momentu startu fazy live.

    Ingestia wsadowa buduje ekstenty, dzieki czemu zapytania kafelkow sa szybkie.
    Streaming ingestion trzyma dane w buforze i przy setkach tysiecy wierszy
    zapytania zauwazalnie zwalniaja - dlatego strumieniowo idzie wylacznie okno live.
    """
    cutoff_iso = cutoff.isoformat()
    print(f"=== Tlo scenariusza: ingestia wsadowa do {cutoff_iso}")
    # Ingestie ida sekwencyjnie: dziewiec rownoleglych zadan przekracza limit
    # wspolbieznosci pojemnosci F8 i konczy sie stanem Throttled.
    for stream in streams:
        url = f"{base_url.rstrip('/')}/{stream}.jsonl"
        loaded = 0
        state = "NieUruchomiono"
        for attempt in range(5):
            operation = client.ingest_from_onelake(stream, url)
            state = client.wait_for_operation(operation)
            loaded = client.scalar(f"{stream} | count")
            if state == "Completed" and loaded:
                break
            wait_s = 15 * (attempt + 1)
            print(f"  [ponawiam za {wait_s}s] {stream}: stan={state}")
            time.sleep(wait_s)
        if state != "Completed" or not loaded:
            raise SystemExit(f"Ingestia wsadowa {stream} nie powiodla sie: stan={state}, wierszy={loaded}")
        print(f"  [OK] {stream}: {loaded} wierszy")
    print("=== Obcinanie tla do okna live")
    for stream in streams:
        client.delete_from(stream, cutoff_iso)
        rows = client.scalar(f"{stream} | count")
        print(f"  [OK] {stream}: {rows} wierszy tla")


def run(args):
    cfg = load_config(CONFIG)
    streams = args.streams.split(",") if args.streams else cfg["streams"]
    client = KustoClient(cfg["cluster"], cfg["database"], TokenCache())

    if args.reset:
        reset_tables(client, streams)
        if args.reset_only:
            print("Gotowe: tabele puste, scenariusz mozna uruchomic od zera.")
            return

    print("=== Przygotowanie mapowan ingestii")
    columns = {}
    for stream in streams:
        cols = client.table_columns(stream)
        client.ensure_mapping(stream, cols)
        columns[stream] = set(cols)
        print(f"  [OK] {stream} ({len(cols)} kolumn)")

    live_start = parse_ts(args.from_ts or cfg["liveStart"])
    live_end = parse_ts(args.to_ts) if args.to_ts else live_start + timedelta(hours=args.live_hours)

    if args.bulk:
        bulk_load(client, streams, cfg["onelake"], live_start)

    print("=== Wczytywanie okna live")
    events = load_events(streams, live_start, live_end)
    if not events:
        raise SystemExit("Brak zdarzen do odtworzenia.")

    t0, t1 = events[0][0], events[-1][0]
    span = (t1 - t0).total_seconds()
    offset = datetime.now(timezone.utc) - t0 if args.time_mode == "now" else None

    print(f"  zdarzen: {len(events)}")
    print(f"  okno live: {t0.isoformat()} .. {t1.isoformat()} ({span / 3600:.1f} h)")
    print(f"  mnoznik czasu: {args.speed}x  ->  odtwarzanie potrwa ok. {span / args.speed / 60:.1f} min")
    print(f"  znaczniki czasu: {'przesuniete na teraz' if offset else 'oryginalne'}")
    if args.dry_run:
        print("DRY-RUN: nic nie wysylam.")
        return

    print("=== Odtwarzanie (Ctrl+C przerywa)")
    pool = IngestPool(client, workers=args.workers)
    wall_start = time.monotonic()
    buffers = defaultdict(list)
    buffered = 0

    def flush():
        nonlocal buffers, buffered
        for table, rows in buffers.items():
            if rows:
                pool.submit(table, rows)
        buffers = defaultdict(list)
        buffered = 0

    last_log = wall_start
    try:
        for ts, stream, ev in events:
            # tempo: czas sceny podzielony przez mnoznik to czas zegarowy
            due = (ts - t0).total_seconds() / args.speed
            behind = due - (time.monotonic() - wall_start)
            if behind > 0:
                flush()
                time.sleep(min(behind, args.tick))
            if offset:
                ev = dict(ev)
                ev["timestamp"] = (ts + offset).isoformat().replace("+00:00", "Z")
            payload = {k: v for k, v in ev.items() if k in columns[stream]}
            buffers[stream].append(json.dumps(payload, ensure_ascii=False))
            buffered += 1
            if buffered >= args.batch:
                flush()
            now = time.monotonic()
            if now - last_log >= args.log_every:
                elapsed = now - wall_start
                scene = t0 + timedelta(seconds=elapsed * args.speed)
                pct = 100.0 * pool.sent / len(events)
                print(f"  [{elapsed / 60:6.1f} min] czas sceny {scene:%Y-%m-%d %H:%M} | "
                      f"wyslano {pool.sent}/{len(events)} ({pct:.1f}%)", flush=True)
                last_log = now
        flush()
        pool.drain()
    except KeyboardInterrupt:
        print(f"\nPrzerwano. Wyslano {pool.sent} zdarzen.")
        return
    finally:
        pool.close()

    elapsed = time.monotonic() - wall_start
    print(f"=== Zakonczono: {pool.sent} zdarzen w {elapsed / 60:.1f} min")
    for stream in streams:
        print(f"  {stream}: {client.scalar(f'{stream} | count')} wierszy w Eventhouse")


def main():
    p = argparse.ArgumentParser(description="Odtwarzanie scenariusza COP-24 do Eventhouse")
    p.add_argument("--speed", type=float, default=300.0,
                   help="ile sekund scenariusza przypada na sekunde zegara (300 = 5 minut na sekunde)")
    p.add_argument("--reset", action="store_true", help="wyczysc tabele przed startem")
    p.add_argument("--reset-only", action="store_true", help="tylko wyczysc i zakoncz")
    p.add_argument("--bulk", action="store_true",
                   help="zaladuj tlo scenariusza ingestia wsadowa z OneLake przed faza live")
    p.add_argument("--live-hours", type=float, default=24.0,
                   help="dlugosc okna odtwarzanego strumieniowo, w godzinach scenariusza")
    p.add_argument("--streams", help="lista strumieni po przecinku; domyslnie wszystkie z scenario.json")
    p.add_argument("--from", dest="from_ts", help="poczatek okna live; domyslnie liveStart z scenario.json")
    p.add_argument("--to", dest="to_ts", help="koniec okna live; domyslnie poczatek + live-hours")
    p.add_argument("--time-mode", choices=("source", "now"), default="source",
                   help="source = oryginalne znaczniki, now = przesuniete tak, by scenariusz zaczynal sie teraz")
    p.add_argument("--batch", type=int, default=4000, help="maks. liczba zdarzen w jednej partii")
    p.add_argument("--workers", type=int, default=8, help="liczba rownoleglych watkow wysylajacych")
    p.add_argument("--tick", type=float, default=0.5, help="maks. dlugosc pojedynczego uspienia w sekundach")
    p.add_argument("--log-every", type=float, default=10.0, help="co ile sekund raportowac postep")
    p.add_argument("--dry-run", action="store_true", help="policz i pokaz plan bez wysylania")
    run(p.parse_args())


if __name__ == "__main__":
    main()
