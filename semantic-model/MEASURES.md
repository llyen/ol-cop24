# 📏 Miary DAX COP-24

Każda miara ma format i znaczenie biznesowe. Nazwy techniczne bez polskich znaków mogą zostać użyte w modelu, a podpisy w raporcie po polsku.

## Miary

```dax
KIS = AVERAGE(kis_gmina[kis])
```
Format: `0.0`; główny indeks sytuacji.

```dax
KIS Max Lokalny = MAX(kis_gmina[kis])
```
Format: `0.0`; pokazuje najgorszą gminę.

```dax
Liczba Ewakuowanych = SUM(evacuation_status[people_count])
```
Format: `#,0`.

```dax
% Gmin w Alarmie = DIVIDE(CALCULATE(DISTINCTCOUNT(hydro_readings[gmina_code]), hydro_readings[level_cm] >= hydro_readings[alarm_level_cm]), DISTINCTCOUNT(dim_gmina[gmina_code]))
```
Format: `0.0%`.

```dax
Odbiorcy Bez Prądu = SUM(power_grid_events[customers_offline])
```
Format: `#,0`.

```dax
Minimalne Pokrycie Telco = MIN(telecom_events[coverage_pct])
```
Format: `0.0%`.

```dax
Gminy Telco Ponizej 50 = CALCULATE(DISTINCTCOUNT(telecom_events[gmina_code]), telecom_events[coverage_pct] < 50)
```
Format: `#,0`.

```dax
Incydenty = COUNTROWS(incident_reports)
```
Format: `#,0`.

```dax
Incydenty Priorytet 4 Plus = CALCULATE(COUNTROWS(incident_reports), incident_reports[priority] >= 4)
```
Format: `#,0`.

```dax
Osoby Dotkniete = SUM(incident_reports[affected_people])
```
Format: `#,0`.

```dax
Zgloszenia 15 Min = CALCULATE(COUNTROWS(incident_reports), DATESINPERIOD('Date'[DateTime], MAX('Date'[DateTime]), -15, MINUTE))
```
Format: `#,0`.

```dax
Sygnały Dezinformacji = CALCULATE(COUNTROWS(media_signals), media_signals[disinformation_flag] = TRUE())
```
Format: `#,0`.

```dax
Zasieg Dezinformacji = CALCULATE(SUM(media_signals[reach]), media_signals[disinformation_flag] = TRUE())
```
Format: `#,0`.

```dax
PSP Zastepy = SUM(resource_deployment[psp_units])
```
Format: `#,0`.

```dax
WOT Zolnierze = SUM(resource_deployment[wot_soldiers])
```
Format: `#,0`.

```dax
Pompy = SUM(resource_deployment[pumps])
```
Format: `#,0`.

```dax
Agregaty = SUM(resource_deployment[generators])
```
Format: `#,0`.

```dax
Smiglowce = SUM(resource_deployment[helicopters])
```
Format: `#,0`.

```dax
Czas Reakcji Min = AVERAGEX(escalation_events, DATEDIFF(escalation_events[timestamp], NOW(), MINUTE))
```
Format: `#,0`; w demo interpretować ostrożnie, bo dane są historyczne.

```dax
Rekomendacje RZZK = CALCULATE(COUNTROWS(escalation_recommendations), escalation_recommendations[recommended_level] = "RZZK")
```
Format: `#,0`.

## Zasady użycia miar

Miary KIS służą do porównań operacyjnych, a nie do formalnej oceny województw. W raporcie decyzyjnym zawsze pokazuj razem `KIS`, `KIS Max Lokalny` i liczbę gmin przekraczających próg, bo średnia krajowa może być niska przy bardzo ciężkiej sytuacji lokalnej. Miary energetyczne i telekomunikacyjne traktuj jako sygnały skutków infrastrukturalnych.

```dax
Gminy KIS Powiat Plus = CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 25)
```
Format: `#,0`; liczba gmin wymagających co najmniej poziomu powiatowego.

```dax
Gminy KIS Wojewoda Plus = CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 45)
```
Format: `#,0`; liczba gmin z rekomendacją poziomu wojewody lub wyżej.

```dax
Gminy KIS RZZK = CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 85)
```
Format: `#,0`; liczba gmin z rekomendacją RZZK.

```dax
Alarm Hydro = CALCULATE(DISTINCTCOUNT(hydro_readings[gauge_id]), hydro_readings[level_cm] >= hydro_readings[alarm_level_cm])
```
Format: `#,0`; liczba wodowskazów w alarmie.

```dax
Stan Ostrzegawczy Hydro = CALCULATE(DISTINCTCOUNT(hydro_readings[gauge_id]), hydro_readings[level_cm] >= hydro_readings[warning_level_cm], hydro_readings[level_cm] < hydro_readings[alarm_level_cm])
```
Format: `#,0`; liczba wodowskazów między progami.
