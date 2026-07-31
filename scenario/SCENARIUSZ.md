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
  prosto z OneLake, a następnie jednym poleceniem `.set-or-replace` jest obcinane do tego
  momentu i przenoszone na oś czasu zegarowego. Dane trafiają do ekstentów, więc kafelki
  odpowiadają w ok. 200 ms.
- **Faza 2 — live.** Wyłącznie okno narracyjne (domyślnie doba D0, ok. 45 tys. zdarzeń)
  idzie przez streaming ingestion w tempie demo. Widać, jak sytuacja narasta.

Dlaczego nie wszystko strumieniowo: streaming ingestion trzyma dane w buforze, zanim
zbuduje ekstenty. Przy 578 tys. wierszy tabela `hydro_readings` miała `TotalExtents = 0`
i kafelki ładowały się zauważalnie wolniej. Podział na fazy usuwa ten problem.

## Skąd bierze się efekt czasu rzeczywistego

To najważniejsza część konstrukcji i warto ją rozumieć, bo naiwne podejście nie działa.

Scena rozgrywa się we wrześniu 2026, ale demo pokazujemy dziś. Gdyby zdarzenia zachowały
oryginalne znaczniki, dashboard patrzący na „ostatnie dwie godziny" byłby zawsze pusty,
a przy sztywnym zakresie dat nic by się nie ruszało. Dlatego cała scena jest
**skompresowana mnożnikiem tempa i przypięta do bieżącego zegara**:

```
znacznik zdarzenia = chwila startu + (czas sceny − początek okna live) / tempo
```

Przy tempie 60x trzy doby tła zajmują ostatnie ~72 minuty zegara, a doba D0 płynie przez
kolejne ~24 minuty. Zdarzenie dostaje znacznik równy chwili wysłania, więc opóźnienie
strumienia utrzymuje się w granicach kilku sekund. Dzięki temu:

- **kafelki filtrują po ruchomym oknie** `_startTime .. _endTime` (domyślnie ostatnie 15 min)
  — bez tego filtru każdy kafelek agregował całą tabelę i nic się nie zmieniało;

> **Okno musi być krótsze niż jeden cykl odtwarzania.** Wcześniejsze ustawienia (tempo 300x,
> okno 2 h) mieściły w kadrze całą 14-dniową scenę naraz: w oknie leżało ponad 480 tys.
> odczytów hydrologicznych, nowe punkty ginęły w masie i dashboard wyglądał na zamrożony,
> mimo że opóźnienie strumienia wynosiło 2 s. Przy tempie 60x cykl trwa 24 min, a okno 15 min
> obejmuje ok. 2,1 tys. odczytów i widać przyrost między odświeżeniami.

- dashboard odświeża się co 10 s i widać przyrost danych;
- kafelek **„Świeżość danych"** pokazuje opóźnienie strumienia w sekundach, co jest
  najprostszym dowodem, że demo naprawdę żyje.

### Tryb ciągły — demo gotowe o dowolnej porze

Pojedynczy przebieg kończy się po kilku minutach i po godzinie dashboard znów byłby pusty.
Wariant `ciagly` zapętla scenariusz bez końca: każdy kolejny przebieg startuje od bieżącej
chwili, a dane starsze niż `--prune-hours` (domyślnie 3 h) są usuwane, żeby tabele nie rosły.

```powershell
# demo, które jest na żywo niezależnie od tego, o której ktoś je otworzy
.\scenario\run_scenario.ps1 -Preset ciagly
```

### Dwie warstwy czasu — to celowe

- **Eventhouse + Real-Time Dashboard** — warstwa operacyjna, oś czasu przypięta do „teraz".
- **Lakehouse + model semantyczny + raport** — warstwa analityczna, zachowuje oryginalną
  oś scenariusza (12–25 września 2026), zgodną z narracją w `DEMO_SCRIPT.md`.

Raport pokazuje więc rozliczenie zdarzenia, a dashboard bieżącą sytuację. To odpowiada
podziałowi ról w realnym centrum zarządzania kryzysowego.

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
| `demo` (domyślny) | 60x | 24 h (D0) | ok. 24 min |
| `szybki` | 300x | 24 h (D0) | ok. 5 min — tylko smoke-test, cykl mieści się w oknie dashboardu |
| `kulminacja` | 30x | 12 h od 15.09 06:00 | ok. 24 min |
| `wolny` | 15x | 12 h | ok. 48 min |
| `ciagly` | 60x | 24 h, zapętlone | bez końca |

Uruchomienie w tle (zalecane dla trybu ciągłego):

```powershell
.\scenario\run_scenario.ps1 -Preset ciagly -Background   # PID w scenario\_ciagly.pid
.\scenario\run_scenario.ps1 -Stop                        # zatrzymanie
```

### Tryb znaczników czasu

- `-TimeMode wall` (domyślny) — cała scena skompresowana i przypięta do bieżącego zegara.
  Jedyny tryb dający prawdziwy efekt czasu rzeczywistego; działa o dowolnej porze dnia.
- `-TimeMode source` — zachowuje oryginalne znaczniki scenariusza (wrzesień 2026).
  Przydatne, gdy chcemy odtworzyć dane pod raport analityczny.
- `-TimeMode now` — stały offset od pierwszego zdarzenia; tryb historyczny, bez kompresji.

Dashboard ma włączone auto-odświeżanie co 10 s, więc w trakcie odtwarzania kafelki
aktualizują się samoczynnie.

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
