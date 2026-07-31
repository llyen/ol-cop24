"""Symulator odtwarzania strumieni COP-24 do Fabric Eventstream/Event Hub."""
from __future__ import annotations

import argparse, json, os, sys, time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATASETS = ROOT / "datasets"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

def load_env():
    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            if not line or line.strip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"'))

def parse_ts(value):
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))

def iter_events(stream, start=None, end=None):
    path = DATASETS / f"{stream}.jsonl"
    if not path.exists():
        raise FileNotFoundError(f"Brak pliku {path}")
    with path.open(encoding="utf-8") as f:
        for line in f:
            ev = json.loads(line)
            ts = parse_ts(ev.get("timestamp"))
            if start and ts < start:
                continue
            if end and ts > end:
                continue
            yield ev

def send_eventhub(events, connection_string, eventhub_name):
    from azure.eventhub import EventData, EventHubProducerClient  # lazy import for dry-run
    producer = EventHubProducerClient.from_connection_string(conn_str=connection_string, eventhub_name=eventhub_name)
    with producer:
        batch = producer.create_batch()
        for ev in events:
            data = EventData(json.dumps(ev, ensure_ascii=False))
            try:
                batch.add(data)
            except ValueError:
                producer.send_batch(batch)
                batch = producer.create_batch()
                batch.add(data)
        if len(batch) > 0:
            producer.send_batch(batch)

def main():
    p = argparse.ArgumentParser(description="Odtwarzanie strumieni COP-24 do Eventstream/Event Hub")
    p.add_argument("--stream", default="hydro_readings", help="nazwa pliku bez .jsonl albo 'all'")
    p.add_argument("--speed", type=float, default=3600.0, help="mnożnik czasu; 3600 = godzina danych w sekundę")
    p.add_argument("--from", dest="from_ts", help="ISO timestamp od")
    p.add_argument("--to", dest="to_ts", help="ISO timestamp do")
    p.add_argument("--dry-run", action="store_true", help="bez poświadczeń: wypisuje zdarzenia")
    p.add_argument("--output", help="plik JSONL dla dry-run zamiast stdout")
    p.add_argument("--config", default="config.json", help="plik konfiguracyjny JSON")
    args = p.parse_args()
    load_env()
    start, end = parse_ts(args.from_ts), parse_ts(args.to_ts)
    streams = [x.stem for x in DATASETS.glob("*.jsonl")] if args.stream == "all" else [args.stream]
    items = []
    for stream in streams:
        items.extend(iter_events(stream, start, end))
    events = sorted(items, key=lambda e: e.get("timestamp", ""))
    if args.dry_run:
        out = open(args.output, "w", encoding="utf-8") if args.output else None
        try:
            prev, count = None, 0
            for ev in events:
                ts = parse_ts(ev["timestamp"])
                if prev and args.speed > 0:
                    time.sleep(min((ts - prev).total_seconds() / args.speed, 0.05))
                print(json.dumps(ev, ensure_ascii=False), file=out or None)
                prev = ts
                count += 1
                if count >= 25 and not args.output:
                    break
            print(f"DRY_RUN_SENT={count}", file=out or None)
        finally:
            if out:
                out.close()
        return
    cfg = {}
    cfg_path = ROOT / args.config
    if cfg_path.exists():
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    conn = os.environ.get("EVENTHUB_CONNECTION_STRING") or cfg.get("eventhub_connection_string")
    hub = os.environ.get("EVENTHUB_NAME") or cfg.get("eventhub_name")
    if not conn or not hub:
        raise SystemExit("Brak EVENTHUB_CONNECTION_STRING/EVENTHUB_NAME albo config.json")
    send_eventhub(events, conn, hub)

if __name__ == "__main__":
    main()
