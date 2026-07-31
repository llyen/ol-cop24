# Raport decyzyjny COP-24

`OL_COP24_Raport` jest pięciostronicowym raportem Power BI dla kierownictwa RCB, wojewodów i RZZK. Układ odpowiada narracji `DEMO_SCRIPT.md`: od obrazu kraju, przez falę powodziową i kaskadę infrastruktury, do rozmieszczenia zasobów oraz decyzji o eskalacji.

## Warstwa wizualna

- Motyw `COP24-CommandCenter-c0242026.json`: grafitowo-granatowe tło, jasna typografia, turkus dla stanu informacyjnego, bursztyn dla ostrzeżeń i czerwień dla alarmów.
- Każda strona ma pasek tytułowy, jedno zdanie decyzyjne, rząd dużych KPI i dominującą wizualizację.
- Panele mają zaokrąglone obramowania, kontrolowany kontrast i spójne formatowanie.
- Stosowane są wyłącznie wizualizacje wbudowane Power BI.
- Model ma kulturę `pl-PL`; miary korzystają z polskich separatorów i jednostek w etykietach.

## 1. Obraz kraju

**Pytanie decyzyjne:** jaka jest skala kryzysu i gdzie wymagana jest eskalacja?

- KPI: KIS krajowy, maksymalny KIS lokalny, wodowskazy w alarmie, incydenty.
- Mapa bąbelkowa gmin: położenie oraz wielkość KIS.
- Ranking województw: średni i maksymalny KIS.
- Wykres warstwowy: narastanie incydentów w osi scenariusza.
- Kolumny: liczba gmin według rekomendowanego poziomu eskalacji.

## 2. Hydrologia i fala

**Pytanie decyzyjne:** gdzie fala przekracza progi i w jakim kierunku się przemieszcza?

- KPI: alarm hydro, stan ostrzegawczy, udział gmin w alarmie, osoby dotknięte.
- Mapa bąbelkowa 120 wodowskazów z poziomem wody.
- Małe multiplikatory poziomu wody według rzeki.
- Wykres kombi: przepływ w kolumnach i poziom wody na linii.
- Macierz wodowskazów z progami oraz paskami danych.

## 3. Infrastruktura krytyczna

**Pytanie decyzyjne:** czy presja hydrologiczna tworzy wielosektorową kaskadę skutków?

- KPI: odbiorcy bez prądu, minimalne pokrycie telco, gminy poniżej 50% pokrycia, incydenty priorytetu 4+.
- Wykres punktowy: hydro na osi X, energia na osi Y, wielkość bąbla jako skutek telekomunikacyjny.
- Wykres warstwowy awarii energetycznych.
- Małe multiplikatory pokrycia według operatora.
- Macierz gmin z paskami danych dla hydro, energii, telco i KIS.

## 4. Siły, środki i ewakuacja

**Pytanie decyzyjne:** czy mobilizacja zasobów nadąża za ewakuacją?

- KPI: ewakuowani, PSP, WOT, pompy, agregaty.
- Skumulowane słupki zasobów według województwa.
- Skumulowany wykres warstwowy ewakuacji według statusu.
- Wykres kombi mobilizacji PSP i WOT.
- Macierz bilansu zasobów z paskami danych.

## 5. Eskalacja, SPO i dezinformacja

**Pytanie decyzyjne:** jakie działania i komunikacja powinny trafić na stół RZZK?

- KPI: rekomendacje RZZK, gminy z KIS ≥ 85, sygnały Z20, zasięg Z20, czas reakcji.
- Wykres warstwowy zasięgu dezinformacji.
- Jedyny wykres pierścieniowy: kanały sygnałów Z20.
- Kolumny eskalacji według poziomu docelowego.
- Ranking rekomendowanych procedur SPO.
- Macierz decyzji: poziom, gmina, KIS, SPO i uzasadnienie.

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
