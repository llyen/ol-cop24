# Scenariusz demonstracyjny: powódź w dorzeczu Nysy Kłodzkiej

Scenariusz jest **odtwarzalny od zera dowolną liczbę razy**. Każde uruchomienie czyści
tabele strumieniowe w Eventhouse i odtwarza 13 dób sytuacji kryzysowej w tempie
przyspieszonym, zasilając Real-Time Dashboard na oczach widowni.

## Jak to działa

```
datasets/*.jsonl  ──►  scenario/replay.py  ──►  streaming ingestion (REST)  ──►  Eventhouse
                            │                                                       │
                       tempo 1:3600                                        Real-Time Dashboard
                       reset + replay                                      (auto-odświeżanie)
```

Zasilanie idzie **bezpośrednio przez streaming ingestion Eventhouse**, a nie przez
Event Hub. Zaleta: brak zarządzania kluczami, typowany zapis do dziewięciu tabel
docelowych i opóźnienie poniżej sekundy między wysłaniem a widocznością w dashboardzie.

## Uruchomienie

```powershell
# pełny scenariusz od zera: 13 dób w ok. 5 minut
.\scenario\run_scenario.ps1

# doba kulminacyjna D0 rozciągnięta na ok. 4 minuty - do narracji na żywo
.\scenario\run_scenario.ps1 -Preset kulminacja

# samo wyczyszczenie środowiska przed prezentacją
.\scenario\run_scenario.ps1 -ResetOnly
```

### Warianty

| Wariant | Tempo | Zakres | Czas trwania |
|---|---|---|---|
| `demo` (domyślny) | 3600x | całe 13 dób | ok. 5 min |
| `szybki` | 10800x | całe 13 dób | ok. 2 min |
| `kulminacja` | 300x | 15–16.09 (D0) | ok. 4 min |
| `wolny` | 900x | całe 13 dób | ok. 21 min |

### Tryb znaczników czasu

- `-TimeMode source` (domyślny) — zachowuje oryginalne znaczniki 2026-09-12 … 2026-09-25.
  Zakres czasu dashboardu jest do nich dopasowany, więc kafelki wypełniają się w miarę napływu.
- `-TimeMode now` — przesuwa scenariusz tak, by zaczynał się w chwili uruchomienia.
  Przydatne, gdy chcemy pokazać kafelki z filtrem „ostatnia godzina".

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
