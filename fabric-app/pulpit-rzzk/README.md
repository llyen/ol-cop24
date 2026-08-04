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
python tools/build_scene.py
```

Skrypt powtarza formułę KIS z `notebooks/02_situation_index.py` (wagi: hydro 30%,
incydenty 25%, energia 15%, telekom 10%, ewakuacja 10%, zasoby 10%) i progi eskalacji
z `notebooks/03_escalation_recommendation.py` (≥85 RZZK, ≥65 minister wiodący,
≥45 wojewoda, ≥25 powiat). Test regresyjny w `src/__tests__/model.test.ts` pilnuje
zgodności progów w `model.ts` z notatnikiem.

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

## Uwaga o danych

`datasets/derived/*` oraz `demo_metrics.json` powstały **przed** ostatnią regeneracją
`datasets/`. Liczby cytowane w `fabric-app/RAYFIN_PROMPT.md` i `APP_SPEC.md`
(maks. KIS 100, 363 sygnały dezinformacji) **nie odpowiadają obecnym danym**.
Wartości faktyczne po przeliczeniu notatnikami 02/03:

| Miara | Wartość |
|---|---|
| Maks. lokalny KIS | **65,4** (2026-09-16) |
| Sygnały dezinformacji | **335** |
| Gminy w alarmie | **10** |
| Szczyt bez prądu (doba) | **139 539** odbiorców |
| Maks. ewakuowanych (doba) | **8 858** osób |

Ponieważ maksymalny KIS nie przekracza 65,4, **algorytm nigdy nie rekomenduje RZZK**.
Okazało się to korzystne narracyjnie: ekran „Zwołanie RZZK" buduje osobny argument —
kaskadę wieloresortową (woda + energia + łączność + ewakuacja) obejmującą dwa
województwa — który uzasadnia decyzję człowieka **wbrew progowi liczbowemu**.
To najmocniejszy moment demo: pokazuje, że system wspiera decydenta, a nie zastępuje go.
