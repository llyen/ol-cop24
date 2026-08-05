# Pulpit RZZK — Fabric App (Rayfin)

Aplikacja decyzyjna dla scenariusza **COP-24 — Wspólny Obraz Sytuacji Kryzysowej**.
Odpowiada na pytanie, na które sam dashboard nie odpowiada: *na jakim szczeblu i kiedy
podjąć decyzję o eskalacji, na jakiej podstawie i kto za nią odpowiada.*

Dashboard w czasie rzeczywistym (Real-Time Dashboard w Fabric) pokazuje **strumień**.
Ta aplikacja pokazuje **proces decyzyjny** na powtarzalnej, deterministycznej scenie
14 dób (2026-09-12 … 2026-09-25, D0 = 2026-09-15) — z suwakiem czasu i odtwarzaniem
od zera, żeby demo dało się prowadzić wielokrotnie z identycznym przebiegiem.

## Identyfikatory wdrożenia

| Element | Wartość |
|---|---|
| Aplikacja (URL) | https://key-horn-c1ee0f1637-westeurope.webapp.fabricapps.net |
| Rayfin Item ID | `8dd3360a-512e-46a8-8bd3-8eab3be64d73` |
| Workspace | `OL-ZK-Demo-COP24` = `8ea0556f-7368-4b36-ad84-adf995e19a80` |
| Tenant | `7ada8cf4-c4be-488f-a844-6d37ee64849e` (CRM262738) |
| Pojemność | `fcdemo` (rg-fabric-cap-demo, West Europe) |
| Portal | https://app.fabric.microsoft.com/groups/8ea0556f-7368-4b36-ad84-adf995e19a80/appbackends/8dd3360a-512e-46a8-8bd3-8eab3be64d73 |

## Ekrany

| Ekran | Rola w narracji |
|---|---|
| **Obraz sytuacji** | Krajowe KPI, mapa gmin wg KIS, kaskada wieloresortowa, propagacja fali, tabela województw |
| **Województwo** | Zejście na poziom gmin, rozbicie KIS na 6 składowych (wyjaśnialność), siły i środki, zamówienie briefu |
| **Rekomendacje** | Próg algorytmiczny vs. przesłanki; zapis decyzji z uzasadnieniem odstępstwa |
| **Rejestr decyzji** | Wersjonowany dziennik decyzji, zadania SPO, briefy, powiadomienia, eksport CSV |
| **Zwołanie RZZK** | Argumenty za/przeciw, proponowany skład, generator zawiadomienia i rejestracja wysyłki |

## Architektura danych

```
datasets/*.jsonl  ──►  tools/build_scene.py  ──►  public/data/scene.json (810 KB)
                                                        │  fetch()
                                                        ▼
                                              src/data/model.ts (funkcje czyste)
                                                        │
                        write-back ◄──── Rayfin Data (mssql) ◄─── src/services/decisions.ts
```

- **Odczyt:** statyczna scena `public/data/scene.json`, pobierana `fetch`em. Nie `import` —
  810 KB wkompilowane w bundle spowalnia `tsc` i puchnie paczkę.
- **Zapis:** Rayfin Data (SQL) — `DecisionLog` (wersjonowany, bez `delete`), `SpoActionLog`,
  `BriefRequest`, `NotificationLog`. Każda encja z RLS.
- **Bez Eventhouse.** Eventhouse zawiera tylko okno ostatniego odtwarzania symulatora;
  aplikacja potrzebuje pełnych 14 dób, więc czyta scenę zbudowaną z `datasets/`.

### Przebudowa sceny

Po każdej zmianie `datasets/` uruchom:

```bash
python tools/build_poland_geo.py   # tylko raz - granice wojewodztw
python tools/build_scene.py
```

Skrypt powtarza formułę KIS z `notebooks/02_situation_index.py` (wagi: hydro 30%,
incydenty 25%, energia 15%, telekom 10%, ewakuacja 10%, siły i środki 10%) i progi
eskalacji z `notebooks/03_escalation_recommendation.py` (≥85 RZZK, ≥65 minister wiodący,
≥45 wojewoda, ≥25 powiat). Test regresyjny w `src/__tests__/model.test.ts` pilnuje
zgodności progów w `model.ts` z notatnikiem. **Dzielniki normalizacji muszą pozostać
zgodne w obu miejscach** — patrz sekcja „Kalibracja KIS".

## Mapa

Mapa (`src/components/CountryMap.tsx`) rysuje granice 16 województw i pozwala ją
przeglądać: kółko myszy lub gest szczypania przybliża w miejscu kursora, przeciągnięcie
przesuwa, dwuklik przybliża dwukrotnie, przyciski w rogu i klawisze `+`, `−`, `0` oraz
strzałki robią to samo z klawiatury. Maksymalne przybliżenie to 14×. Znaczniki, linie
i napisy są dzielone przez współczynnik przybliżenia, więc na ekranie zachowują stałą
wielkość — przybliża się mapa, a nie symbole.

Granice pochodzą z [polska-geojson](https://github.com/ppatrzyk/polska-geojson) (dane GUS,
licencja MIT). `tools/build_poland_geo.py` upraszcza je z 76 881 do 6 960 wierzchołków
i **wstępnie rzutuje** na tę samą siatkę 0..100, której używa `project` w `model.ts`,
zapisując wynik do `src/data/poland.ts` (83 kB). Dzięki temu warstwa granic i warstwa
punktów zawsze się pokrywają, a przeglądarka nie liczy rzutu przy każdej klatce
przesuwania.

**Trzy miejsca muszą mieć identyczne `BOUNDS`**: `model.ts`, `CountryMap.tsx` i
`build_poland_geo.py`. Rozjazd przesunie punkty względem granic — to jedyny sposób,
w jaki ta mapa może zepsuć się po cichu.

### Korekta współrzędnych

`generate_datasets.py` rozrzuca gminy i wodowskazy losowym odchyleniem wokół środka
województwa, bez sprawdzania granic. Dopóki mapa rysowała samą siatkę, nie było tego
widać. Po naniesieniu prawdziwych granic **69 gmin i 13 wodowskazów lądowało poza
krajem**, a znacznie więcej w sąsiednim województwie.

`build_scene.py` przyciąga takie punkty do własnego województwa — do najbliższego
wierzchołka granicy, przesuniętego w stronę środka wielokąta. Dzieje się to **wyłącznie
przy budowie sceny**: zbiory źródłowe, pliki `derived/`, notatniki, Eventhouse i model
semantyczny zostają nietknięte, więc żaden wskaźnik się nie zmienia.

Dwie pułapki, na które natrafiliśmy:

- **Zaokrąglanie do dwóch miejsc (~1 km) przenosiło punkt przygraniczny na drugą stronę
  granicy.** Współrzędne mają teraz trzy miejsca (~100 m), a poprawność sprawdzana jest
  na wartości już zaokrąglonej — tej, która faktycznie trafia na mapę.
- **Pojedyncze zanurzenie w głąb wielokąta nie wystarcza przy kształtach wklęsłych.**
  Przyciąganie zwiększa zanurzenie (6% → 12% → 25% → 50%), aż punkt naprawdę znajdzie
  się w środku.

`src/__tests__/geography.test.ts` sprawdza to na stałe: każda gmina w swoim województwie,
każdy wodowskaz w województwie swojej gminy, żadna siedziba WCZK poza krajem. Test czyta
kontury z `poland.ts`, czyli dokładnie z tego, co rysuje aplikacja.

## Reguły uprawnień

| Rola | Uprawnienia |
|---|---|
| Dyrektor RCB, minister wiodący | zatwierdzanie decyzji, zakres krajowy |
| Wojewoda | decyzje tylko dla własnego województwa, bez zakresu krajowego |
| Analityk / dyżurny | zapis propozycji, bez zatwierdzania |

Treść decyzji min. 20 znaków. Decyzje nie są usuwalne — korekta tworzy nową wersję.

## Uruchomienie lokalne / wdrożenie

```bash
npm run dev                       # dev server
npm run test                      # 31 testów (vitest)
npm run lint
npx rayfin login -t 7ada8cf4-c4be-488f-a844-6d37ee64849e
npx rayfin up -y                  # deploy backend + static hosting
npx rayfin up db apply --force    # migracja schematu
```

## Napotkane problemy

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| 404 „workspace not found" przy `rayfin up` | logowanie do domyślnego tenanta Microsoft corp | `npx rayfin login -t 7ada8cf4-…` |
| To samo, mimo poprawnego tenanta | wstrzymana pojemność `fcdemo` | `az resource invoke-action --ids <capacity> --action resume` |
| To samo, po poprawnej pojemności | brak przypięcia workspace | `npx rayfin up switch --workspace-id 8ea0556f-…` |
| `rayfin up db apply` odmawia migracji | porzucenie tabeli szablonowej `Todos` | flaga `--force` |
| GraphQL psuje się na polu tekstowym | `@text()` bez `max` → `NVARCHAR(MAX)` | zawsze podawać `max` |
| Polityka RLS ignorowana | dokumentacja podaje opcję `check` | poprawna nazwa to `policy` |
| `build_scene.py` wywala się na `wave_delay_h` | puste stringi w JSONL | `float(x) if x else 0.0` |

## Kalibracja KIS i liczby scenariusza

Normalizacja składowych KIS została skalibrowana 2026-08-04 na faktycznym rozkładzie
danych (`notebooks/_calibrate.py`). Wcześniejsze dzielniki pochodziły z wcześniejszej,
większej wersji zbioru i po regeneracji danych zaniżały indeks — maksimum zatrzymywało
się na 65,4, więc algorytm **nigdy** nie rekomendował zwołania RZZK.

Obowiązujące dzielniki (poziom, przy którym składowa osiąga 100 pkt) — zdefiniowane
raz w `tools/build_scene.py` i powtórzone w `notebooks/02_situation_index.py`:

| Składowa | Dzielnik | Uzasadnienie z danych |
|---|---|---|
| incydenty | 5 zgłoszeń / gmina / doba | p95 = 4, max = 8 |
| energia | 1 200 odbiorców / gmina / doba | mediana 1 027, max 10 749 |
| ewakuacja | 250 osób / gmina / doba | p90 = 414, max 604 |
| siły i środki | 900 pkt obciążenia / woj. / doba | mediana 132, max 2 390 |

Składowa „siły i środki" przestała być stałą 20 pkt — liczona jest z faktycznego
`resource_deployment` (PSP ×3, WOT ×0,4, pompy ×5, agregaty ×4, śmigłowce ×25).

Efekt: **maks. lokalny KIS 86,3 w dobie 2026-09-17** — próg 85 przebity punktowo,
w jednej gminie i jednej dobie, bez zalewania mapy czerwienią. Rozkład rekomendacji
wojewódzkich w całej scenie: 26 × powiat, 7 × wojewoda, 5 × minister wiodący, **1 × RZZK**.
Test `prog RZZK jest przekraczany punktowo` pilnuje, żeby kolejna regeneracja danych
tego nie zepsuła w żadną stronę.

### Aktualne liczby scenariusza

Źródło prawdy: `datasets/derived/demo_metrics.json`, generowany przez `compute_metrics.py`
w katalogu głównym repozytorium. Uruchamiać po każdej regeneracji danych.

| Miara | Wartość |
|---|---|
| Maks. lokalny KIS | **86,3** (2026-09-17) |
| Gminy w alarmie | **10** |
| Incydenty łącznie | **1 714** (w tym 495 priorytetu 1) |
| Szczyt bez prądu | **14 168** odbiorców w godzinie, **139 539** w dobie |
| Ewakuowani (ostatnie statusy) | **15 445** osób |
| Sygnały medialne / dezinformacja | **3 044** / **335** |
| Min. pokrycie telekomunikacyjne | **22,6 %** |

### Narracja demo

Ekran „Zwołanie RZZK" nie opiera się wyłącznie na progu. Obok wartości KIS buduje
osobne przesłanki — kaskadę wieloresortową (woda + energia + łączność + ewakuacja)
i zasięg dwóch województw. Dzięki temu demo działa w obie strony:

- **w dobie kulminacji** próg i przesłanki mówią to samo — decyzja jest oczywista,
- **w dobach 2026-09-15/16/18** przesłanki są spełnione, ale próg jeszcze nie —
  decydent może zwołać RZZK **wcześniej niż algorytm**, a aplikacja wymusi
  uzasadnienie odstępstwa i zapisze je w rejestrze.

To najmocniejszy moment demo: system wspiera decydenta, a nie zastępuje go.
