# Raport decyzyjny COP-24

`OL_COP24_Raport` jest pięciostronicowym raportem Power BI dla kierownictwa RCB, wojewodów i RZZK. Układ odpowiada narracji `DEMO_SCRIPT.md` i prowadzi odbiorcę pięcioma krokami: co się dzieje → skąd nadchodzi → co się sypie → czy nadążamy → co robimy.

## Warstwa wizualna

Raport jest utrzymany w konwencji dokumentu urzędowego, nie ekranu centrum dowodzenia. Wynika to z odbiorcy: materiał ma być czytelny na spotkaniu sztabowym, na projektorze i po wydrukowaniu.

- Motyw `COP24-Rzadowy-c0242026.json`: jasne tło stron `#EEF2F7`, białe panele, granat instytucjonalny `#12325B` jako kolor nagłówków i tabel.
- Kolor niesie znaczenie, nie dekorację: czerwień `#B3261E` = alarm, bursztyn `#B26B00` = ostrzeżenie, granat `#1B4A8B` = stan neutralny, morski `#0F6E6E` = zasoby własne, fiolet `#5B4B8A` = warstwa informacyjna.
- Każda strona ma ten sam szkielet: granatowy pasek nagłówka z numerem kroku, cztery karty KPI, dwa panele główne, jeden pas dolny i stopkę ze źródłem danych.
- Każdy panel ma tytuł w formie pytania lub tezy oraz podtytuł, który mówi wprost, co z danych wynika. To zastępuje komentarz prowadzącego.
- Trzy z czterech tabel usunięto — zostaje jedna, na stronie 5, gdzie potrzebna jest wartość co do jednostki do protokołu.
- Siatka: margines 32 px, odstępy 20–24 px, siedem obiektów danych na stronę zamiast dziesięciu.
- Stosowane są wyłącznie wizualizacje wbudowane Power BI. Model ma kulturę `pl-PL`.

## 1. Obraz kraju — krok 1 z 5: co się dzieje

**Pytanie decyzyjne:** jaka jest skala kryzysu i gdzie się koncentruje?

- KPI: KIS krajowy, najwyższy KIS lokalny, osoby dotknięte, zgłoszone incydenty.
- Mapa gmin (bąbel = KIS) — gdzie leży ciężar kryzysu.
- Ranking województw: rozjazd między średnią a maksimum wskazuje kryzys punktowy, nie rozlany.
- Pas dolny: tempo narastania zdarzeń; punkt przegięcia to moment, w którym reagowanie lokalne przestaje wystarczać.

## 2. Hydrologia i fala — krok 2 z 5: skąd nadchodzi

**Pytanie decyzyjne:** gdzie fala przekracza progi i ile mamy czasu?

- KPI: wodowskazy w alarmie, stan ostrzegawczy, udział gmin w alarmie, osoby dotknięte.
- Mapa 120 wodowskazów: kolor = rzeka, wielkość = średni poziom wody.
- Propagacja fali w czasie według rzeki — przesunięcie szczytów to realne wyprzedzenie decyzyjne.
- Pas dolny: przepływ kontra poziom wody; przepływ rośnie pierwszy i jest najwcześniejszym sygnałem w całym zestawie danych.

## 3. Infrastruktura krytyczna — krok 3 z 5: co się sypie

**Pytanie decyzyjne:** czy powstaje wielosektorowa kaskada skutków?

- KPI: odbiorcy bez prądu, najniższe pokrycie telco, gminy poniżej 50% pokrycia, incydenty priorytetu 4+.
- Wykres punktowy kaskady: hydro na osi X, energia na osi Y, bąbel = skutek telekomunikacyjny. Prawy górny róg to gminy bez prądu i bez łączności naraz.
- Skala wyłączeń energetycznych w czasie — szczyt wypada po kulminacji fali, co wyznacza okno na dowóz agregatów.
- Pas dolny: pokrycie czterech operatorów; skorelowane spadki pokazują, że redundancja komercyjna zawodzi.

## 4. Siły, środki i ewakuacja — krok 4 z 5: czy nadążamy

**Pytanie decyzyjne:** czy mobilizacja zasobów nadąża za ewakuacją?

- KPI: osoby ewakuowane, zastępy PSP, żołnierze WOT, agregaty prądotwórcze.
- Rozmieszczenie sił i środków według województwa — do zestawienia z mapą z kroku 1.
- Przebieg ewakuacji według statusu; rosnąca warstwa „w toku" oznacza wąskie gardło transportu lub miejsc w punktach zbiórki.
- Pas dolny: tempo mobilizacji PSP i WOT; WOT wchodzi z opóźnieniem, więc decyzja o wezwaniu wojska musi wyprzedzać kulminację.

## 5. Decyzja: eskalacja i SPO — krok 5 z 5: co robimy

**Pytanie decyzyjne:** co trafia na stół RZZK?

- KPI: rekomendacje RZZK, gminy z KIS ≥ 85, sygnały dezinformacji Z20, czas reakcji.
- Zasięg dezinformacji w czasie — narracja podważająca ewakuację rozchodzi się szybciej niż komunikat urzędowy.
- Kanały dezinformacji: dominujący kanał wyznacza formę reakcji (sprostowanie, RCB Alert, wniosek do platformy).
- Pas dolny: tabela rekomendacji — poziom, gmina, KIS, procedura SPO i uzasadnienie. Jedyna tabela w raporcie.

## Odtwarzanie i walidacja

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\deploy\create_semantic_model.ps1 `
  -WorkspaceName 'OL-ZK-Demo-COP24'
```

Sam raport można odtworzyć bez ponownego wdrażania modelu:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\deploy\create_report.ps1
```

Skrypt wdraża PBIR, wykonuje zapytanie DAX dla każdej wizualizacji, sprawdza wartości kontrolne miar i potwierdza wdrożoną liczbę stron oraz wizualizacji. Manifest zapytań znajduje się w `semantic-model\report\validation\visual-dax.json`, a ostatni wynik w `semantic-model\report\validation\results.json`.

Stan ostatniego wdrożenia: 5 stron, 55 wizualizacji, 55/55 zapytań DAX i 24/24 wartości kontrolne miar.

## Uwagi techniczne

- Współrzędne `lat`/`lon` muszą być w modelu typami liczbowymi. Gdy są tekstem, mapa zwraca komunikat „Something's wrong with one or more fields". Typy ustawia się w dwóch miejscach: `notebooks/01_load_dimensions.py` (zapis do Delta) oraz `deploy/create_semantic_model.ps1` (TMDL).
- W mapach współrzędne wymagają agregacji (Średnia) obok roli Lokalizacji, inaczej Power BI prosi o usunięcie jednej z ról.
- Właściwość `subTitle` w `visualContainerObjects` nie przyjmuje klucza `background` — import raportu kończy się wtedy błędem schematu.
