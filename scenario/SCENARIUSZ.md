# Scenariusz demonstracyjny: powódź w dorzeczu Nysy Kłodzkiej

Scenariusz jest **odtwarzalny od zera dowolną liczbę razy**. Każde uruchomienie czyści
tabele strumieniowe w Eventhouse i odtwarza 13 dób sytuacji kryzysowej w tempie
przyspieszonym, zasilając Real-Time Dashboard na oczach widowni.

## Jak to działa

Scenariusz ma **dwie fazy**, bo to warunek zarówno szybkości, jak i wiarygodnego efektu „na żywo":

```
                    FAZA 1 — TŁO (wsadowo)              FAZA 2 — LIVE (strumieniowo)
OneLake Files/streams/*.jsonl                    datasets/*.jsonl
        │                                                │
        │ .ingest async into (impersonate)               │ streaming ingestion REST
        ▼                                                ▼
   ekstenty Eventhouse  ──────────────────────────►  Eventhouse  ──►  Real-Time Dashboard
   (zapytania ~200 ms)                                                (auto-odświeżanie 30 s)
```

- **Faza 1 — tło.** Wszystko sprzed momentu startu narracji ląduje ingestią wsadową
  prosto z OneLake, a następnie jest obcinane do tego momentu (`.delete`). Dane trafiają
  do ekstentów, więc kafelki odpowiadają w ok. 200 ms.
- **Faza 2 — live.** Wyłącznie okno narracyjne (domyślnie doba D0, ok. 45 tys. zdarzeń)
  idzie przez streaming ingestion w tempie demo. Widać, jak sytuacja narasta.

Dlaczego nie wszystko strumieniowo: streaming ingestion trzyma dane w buforze, zanim
zbuduje ekstenty. Przy 578 tys. wierszy tabela `hydro_readings` miała `TotalExtents = 0`
i kafelki ładowały się zauważalnie wolniej. Podział na fazy usuwa ten problem.

## Uruchomienie

```powershell
# pełny scenariusz od zera: tło + doba D0 odtworzona w ok. 5 minut
.\scenario\run_scenario.ps1

# kulminacja rozciągnięta na dłużej, do narracji na żywo
.\scenario\run_scenario.ps1 -Preset kulminacja

# samo wyczyszczenie środowiska przed prezentacją
.\scenario\run_scenario.ps1 -ResetOnly
```

Każde uruchomienie daje **te same liczby** — reset jest weryfikowany, a ingestia wsadowa
ponawiana przy przeciążeniu pojemności.

### Warianty

| Wariant | Tempo | Okno live | Czas trwania fazy live |
|---|---|---|---|
| `demo` (domyślny) | 300x | 24 h (D0) | ok. 4,8 min |
| `szybki` | 900x | 24 h (D0) | ok. 1,6 min |
| `kulminacja` | 120x | 12 h od 15.09 06:00 | ok. 6 min |
| `wolny` | 60x | 12 h | ok. 12 min |

### Tryb znaczników czasu

- `-TimeMode source` (domyślny) — zachowuje oryginalne znaczniki scenariusza.
  Zakres czasu dashboardu jest do nich dopasowany, kafelki wypełniają się w miarę napływu.
- `-TimeMode now` — przesuwa scenariusz tak, by zaczynał się w chwili uruchomienia.
  Przydatne przy filtrach typu „ostatnia godzina".

Dashboard ma włączone auto-odświeżanie co 30 s (minimum 10 s), więc w trakcie
odtwarzania kafelki aktualizują się samoczynnie.

## Przebieg scenariusza — narracja

| Faza | Czas scenariusza | Co widać w dashboardzie |
|---|---|---|
| **D-3** | 12–13.09 | Stany normalne. Prognoza opadów rośnie w Kotlinie Kłodzkiej. Zgłoszenia na poziomie tła. |
| **D-2** | 13–14.09 | Pierwsze przekroczenia stanów ostrzegawczych na górnej Nysie Kłodzkiej. Wskaźnik sytuacji zaczyna rosnąć. |
| **D-1** | 14–15.09 | Kaskada: Kłodzko → Bardo → Nysa. Pierwsze awarie energetyczne, spadek pokrycia telco. Aktywacja SPO. |
| **D0** | 15–16.09 | **Kulminacja.** Stany alarmowe na 10 wodowskazach, zgłoszenia 112/PSP rosną kilkukrotnie, ewakuacje, szczyt dezinformacji Z20. |
| **D+1…D+3** | 16–19.09 | Fala przesuwa się na Opolszczyznę i do Wrocławia. Napływ sił i środków (PSP, WOT, pompy, agregaty). |
| **D+4…D+9** | 19–25.09 | Opadanie fali, przywracanie zasilania i łączności, powrót ewakuowanych. |

## Co pokazać w trakcie odtwarzania

1. **Obraz kraju** — mapa intensywności zgłoszeń w gminach zapala się w Kotlinie Kłodzkiej,
   heatmapa województwo × doba pokazuje ognisko, krzywa narastająca łamie się w D0.
2. **Hydrologia** — mapa wodowskazów zmienia kolory wraz z przekraczaniem progów;
   wykres fali pokazuje przesuwanie się kulminacji w dół rzeki.
3. **Infrastruktura krytyczna** — korelacja hydro → energia → telco: awarie pojawiają się
   z opóźnieniem względem przekroczeń stanów alarmowych.
4. **RZZK i SPO** — rekomendacje eskalacji i uruchamiane standardowe procedury operacyjne.
5. **Z20 Dezinformacja** — pierścień udziału kanałów, szczyt zasięgu tuż po kulminacji.

## Przywrócenie stanu wyjściowego

Reset jest bezpieczny: dane źródłowe pozostają w `datasets/*.jsonl` oraz w OneLake,
a tabele Delta w Lakehouse (podstawa modelu semantycznego i raportu Power BI)
nie są ruszane. Warstwa Eventhouse to warstwa „na żywo", warstwa Lakehouse to
warstwa analityczna.

## Parametry zaawansowane

```powershell
# własne tempo i wybrane strumienie
python scenario\replay.py --speed 1800 --streams hydro_readings,incident_reports

# wycinek czasowy
python scenario\replay.py --reset --from 2026-09-15T00:00:00+02:00 --to 2026-09-16T00:00:00+02:00

# plan bez wysyłki
python scenario\replay.py --dry-run
```

| Parametr | Domyślnie | Znaczenie |
|---|---|---|
| `--speed` | 3600 | sekund scenariusza na sekundę zegara |
| `--batch` | 4000 | maksymalny rozmiar partii wysyłanej jednym żądaniem |
| `--workers` | 8 | równoległe wątki wysyłające |
| `--time-mode` | source | `source` lub `now` |

Przy tempie 3600x scenariusz wymaga ok. 1850 zdarzeń/s. Szeregowa wysyłka daje
ok. 250 zdarzeń/s, dlatego partie idą przez pulę wątków — z ośmioma wątkami
i partiami po 4000 zdarzeń wysyłka nadąża za czasem sceny.

## Konfiguracja

`scenario/scenario.json` wskazuje klaster Eventhouse, bazę i listę strumieni.
Po odtworzeniu środowiska w innym workspace wystarczy podmienić `cluster` i `database`.
