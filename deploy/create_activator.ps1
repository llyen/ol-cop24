<#
.SYNOPSIS
    Tworzy Activator COP-24 i wdraża reguły alertowe jako funkcje KQL.

.DESCRIPTION
    Skrypt jest idempotentny:
      - wyszukuje albo tworzy element Reflex/Activator OL_COP24_Activator,
      - zapisuje w definicji Reflex źródło Eventstream OL_COP24_Eventstream,
      - tworzy/aktualizuje funkcje KQL alert_* w Eventhouse,
      - weryfikuje liczbę trafień i wypisuje przykładowe rekordy.

    Publiczny REST API Fabric pozwolił automatycznie utworzyć Activator i
    podpiąć źródło Eventstream. Reguły Activator trzeba dokończyć w UI; do
    czasu pełnego wsparcia API działający mechanizm demo zapewniają funkcje KQL.

.EXAMPLE
    .\deploy\create_activator.ps1 -WorkspaceName OL-ZK-Demo-COP24
#>
[CmdletBinding()]
param(
    [string]$WorkspaceName = 'OL-ZK-Demo-COP24',
    [string]$ActivatorName = 'OL_COP24_Activator',
    [string]$WorkspaceId = '8ea0556f-7368-4b36-ad84-adf995e19a80',
    [string]$EventstreamId = 'c964c29e-bdd7-46b6-b59f-89b3a49d3338',
    [string]$ClusterUri = 'https://trd-tmsdqpz0s6cg6aewj9.z3.kusto.fabric.microsoft.com',
    [string]$KqlDatabaseName = 'OL_COP24_Eventhouse'
)

$ErrorActionPreference = 'Stop'
$FabricApi = 'https://api.fabric.microsoft.com/v1'

function Write-Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Warn($msg) { Write-Host "  [UWAGA] $msg" -ForegroundColor Yellow }

function Get-Token([string]$resource) {
    az account get-access-token --resource $resource --query accessToken -o tsv
}

function Get-FabricHeaders {
    @{ Authorization = "Bearer $(Get-Token 'https://api.fabric.microsoft.com')"; 'Content-Type' = 'application/json' }
}

function Get-KustoHeaders {
    @{ Authorization = "Bearer $(Get-Token 'https://kusto.kusto.windows.net')"; 'Content-Type' = 'application/json' }
}

function Resolve-Workspace {
    $headers = Get-FabricHeaders
    $ws = (Invoke-RestMethod -Uri "$FabricApi/workspaces" -Headers $headers).value |
          Where-Object displayName -eq $WorkspaceName | Select-Object -First 1
    if ($ws) { return $ws.id }
    if ($WorkspaceId) {
        Write-Warn "Nie znaleziono workspace '$WorkspaceName' po nazwie; używam id $WorkspaceId."
        return $WorkspaceId
    }
    throw "Nie znaleziono workspace '$WorkspaceName'."
}

function ConvertTo-Base64Utf8([string]$text) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
}

function Invoke-FabricWebRequest([string]$method, [string]$uri, $body = $null) {
    $json = if ($null -ne $body) { $body | ConvertTo-Json -Depth 100 } else { $null }
    $response = Invoke-WebRequest -Method $method -Uri $uri -Headers (Get-FabricHeaders) -Body $json -ContentType 'application/json' -SkipHttpErrorCheck
    if ($response.StatusCode -eq 202) {
        $operationUrl = $response.Headers.Location | Select-Object -First 1
        if ($operationUrl) {
            do {
                Start-Sleep -Seconds 5
                $operation = Invoke-RestMethod -Method Get -Uri $operationUrl -Headers (Get-FabricHeaders)
                Write-Info "operacja Fabric: $($operation.status)"
            } while ($operation.status -in 'NotStarted', 'Running')
            if ($operation.status -notin 'Succeeded', 'Completed') {
                throw "Operacja Fabric nie powiodła się: $($operation | ConvertTo-Json -Depth 20)"
            }
        }
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Fabric REST $method $uri zwrócił $($response.StatusCode): $($response.Content)"
    }
    return $response
}

function Get-OrCreate-Activator([string]$workspaceId) {
    $headers = Get-FabricHeaders
    $item = (Invoke-RestMethod -Uri "$FabricApi/workspaces/$workspaceId/items" -Headers $headers).value |
            Where-Object { $_.displayName -eq $ActivatorName -and $_.type -eq 'Reflex' } |
            Select-Object -First 1
    if ($item) {
        Write-Ok "Activator już istnieje: $($item.id)"
        return $item
    }

    $response = Invoke-FabricWebRequest -method Post -uri "$FabricApi/workspaces/$workspaceId/reflexes" -body @{ displayName = $ActivatorName }
    $created = $response.Content | ConvertFrom-Json
    Write-Ok "utworzono Activator: $($created.id)"
    return $created
}

function Set-ActivatorEventstreamSource([string]$workspaceId, [string]$activatorId) {
    $entities = @(
        [ordered]@{
            uniqueIdentifier = '11111111-1111-1111-1111-111111111111'
            payload = [ordered]@{ name = 'COP-24 alerty'; type = 'kqlQueries' }
            type = 'container-v1'
        },
        [ordered]@{
            uniqueIdentifier = '22222222-2222-2222-2222-222222222222'
            payload = [ordered]@{
                name = 'OL_COP24_Eventstream'
                metadata = [ordered]@{ eventstreamArtifactId = $EventstreamId }
                parentContainer = [ordered]@{ targetUniqueIdentifier = '11111111-1111-1111-1111-111111111111' }
            }
            type = 'eventstreamSource-v1'
        }
    )
    $payload = ConvertTo-Base64Utf8 ($entities | ConvertTo-Json -Depth 50)
    $body = @{
        definition = @{
            parts = @(
                @{ path = 'ReflexEntities.json'; payload = $payload; payloadType = 'InlineBase64' }
            )
        }
    }
    Invoke-FabricWebRequest -method Post -uri "$FabricApi/workspaces/$workspaceId/items/$activatorId/updateDefinition" -body $body | Out-Null
    Write-Ok "zaktualizowano definicję Activatora: źródło Eventstream"
}

function Invoke-KustoMgmt([string]$command) {
    $body = @{ db = $KqlDatabaseName; csl = $command } | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Method Post -Uri "$ClusterUri/v1/rest/mgmt" -Headers (Get-KustoHeaders) -Body $body | Out-Null
}

function Invoke-KustoQuery([string]$query) {
    $body = @{ db = $KqlDatabaseName; csl = $query } | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Method Post -Uri "$ClusterUri/v2/rest/query" -Headers (Get-KustoHeaders) -Body $body
    $response | Where-Object TableKind -eq 'PrimaryResult'
}

$FunctionCommands = @'
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: stan alarmowy wodowskazu') alert_hydro_alarm() {
hydro_readings
| where level_cm >= alarm_level_cm
| extend alert_rule='alert_hydro_alarm', alert_severity='critical', alert_ts=timestamp, alert_key=strcat(gauge_id, ':', format_datetime(bin(timestamp, 1h), 'yyyy-MM-dd HH:mm')), current_value=todouble(level_cm), threshold_value=todouble(alarm_level_cm), spo='SPO-12;SPO-3', message=strcat('ALARM HYDRO — ', gauge_id, ', ', tostring(level_cm), ' cm przy progu ', tostring(alarm_level_cm), ' cm')
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, gauge_id, river, current_value, threshold_value, spo, message, timestamp, level_cm, alarm_level_cm
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: poziom powyżej stanu ostrzegawczego i nadal rosnący (średnia godzinowa, >= 12 cm/h)') alert_hydro_rapid_rise() {
hydro_readings
| summarize avg_level = round(avg(level_cm), 1), warning_level_cm = max(warning_level_cm), alarm_level_cm = max(alarm_level_cm)
        by gauge_id, gmina_code, river, ts = bin(timestamp, 1h)
| sort by gauge_id asc, ts asc
| serialize
| extend prev_gauge = prev(gauge_id), prev_level = prev(avg_level)
| where gauge_id == prev_gauge
| extend rise_cm_h = round(avg_level - prev_level, 1)
| where avg_level >= warning_level_cm and rise_cm_h >= 12
| extend alert_rule='alert_hydro_rapid_rise', alert_severity=iff(avg_level >= alarm_level_cm, 'critical', 'warning'), alert_ts=ts, alert_key=strcat(gauge_id, ':', format_datetime(ts, 'yyyy-MM-dd HH:mm')), current_value=todouble(rise_cm_h), threshold_value=12.0, spo='SPO-12;SPO-3', message=strcat('WEZBRANIE — ', gauge_id, ' (', river, '): ', tostring(avg_level), ' cm, wzrost +', tostring(rise_cm_h), ' cm/h, stan ostrzegawczy ', tostring(warning_level_cm), ' cm')
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, gauge_id, river, current_value, threshold_value, spo, message, avg_level, warning_level_cm, alarm_level_cm, rise_cm_h
| order by alert_ts asc
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert demo: skok zgłoszeń 112/PSP w gminie. Próg produkcyjny z RULES.md: >25/15 min; próg demo: >2/15 min, bo dane syntetyczne mają peak gminny 3.') alert_incident_spike() {
incident_reports
| summarize current_value=count(), affected_people=sum(affected_people), injured=sum(injured_count), sample_incident=any(incident_id) by alert_ts=bin(timestamp, 15m), gmina_code
| where current_value > 2
| extend alert_rule='alert_incident_spike', alert_severity='warning', alert_key=strcat(gmina_code, ':', format_datetime(alert_ts, 'yyyy-MM-dd HH:mm')), threshold_value=2.0, spo='SPO-3;SPO-12', message=strcat('SKOK ZGŁOSZEŃ 112/PSP — gmina ', gmina_code, ', ', tostring(current_value), ' zgłoszenia/15 min (próg demo 2; prod 25)')
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, current_value=todouble(current_value), threshold_value, spo, message, affected_people, injured, sample_incident
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: odbiorcy bez prądu >5000 w gminie/1h') alert_power_outage() {
power_grid_events
| summarize current_value=sum(customers_offline), sample_event=any(event_id), station=any(station), cause=any(cause) by alert_ts=bin(timestamp, 1h), gmina_code
| where current_value > 5000
| extend alert_rule='alert_power_outage', alert_severity='critical', alert_key=strcat(gmina_code, ':', format_datetime(alert_ts, 'yyyy-MM-dd HH:mm')), threshold_value=5000.0, spo='SPO-10', message=strcat('AWARIA ENERGETYCZNA — gmina ', gmina_code, ', ', tostring(current_value), ' odbiorców bez prądu/1h')
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, current_value=todouble(current_value), threshold_value, spo, message, station, cause, sample_event
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: utrata łączności, coverage <40% albo BTS down >=5') alert_telco_coverage_drop() {
telecom_events
| where coverage_pct < 40 or base_stations_down >= 5
| extend alert_rule='alert_telco_coverage_drop', alert_severity=iff(coverage_pct < 30 or base_stations_down >= 7, 'critical', 'warning'), alert_ts=timestamp, alert_key=strcat(gmina_code, ':', format_datetime(bin(timestamp, 2h), 'yyyy-MM-dd HH:mm')), current_value=todouble(coverage_pct), threshold_value=40.0, spo='SPO-10;SPO-3', message=strcat('SPADEK ŁĄCZNOŚCI — gmina ', gmina_code, ', coverage ', tostring(coverage_pct), '%, BTS down ', tostring(base_stations_down))
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, current_value, threshold_value, spo, message, operator, base_stations_down, coverage_pct, cause, event_id
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: Z20 dezinformacja, flaga true i reach >50000') alert_disinformation_z20() {
media_signals
| where disinformation_flag == true and reach > 50000
| extend alert_rule='alert_disinformation_z20', alert_severity='warning', alert_ts=timestamp, alert_key=strcat(topic, ':', channel, ':', format_datetime(bin(timestamp, 3h), 'yyyy-MM-dd HH:mm')), current_value=todouble(reach), threshold_value=50000.0, spo='SPO-3', gmina_code='', message=strcat('DEZINFORMACJA Z20 — ', topic, '/', channel, ', zasięg ', tostring(reach))
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, current_value, threshold_value, spo, message, topic, channel, sentiment, reach, signal_id
}
---NEXT---
.create-or-alter function with (folder='Activator/COP24', docstring='COP-24 alert: eskalacja do RZZK / poziom ministerialny') alert_escalation_rzzk() {
escalation_events
| where to_level =~ 'RZZK' or from_level =~ 'minister' or reason has 'RZZK'
| extend alert_rule='alert_escalation_rzzk', alert_severity='critical', alert_ts=timestamp, alert_key=strcat(area, ':', format_datetime(timestamp, 'yyyy-MM-dd HH:mm')), current_value=1.0, threshold_value=1.0, gmina_code='', spo=strcat('SPO-1;SPO-2;SPO-3;SPO-10;', recommended_spo), message=strcat('ESKALACJA RZZK — ', from_level, ' → ', to_level, ', obszar ', area, ', powód: ', reason)
| project alert_rule, alert_severity, alert_ts, alert_key, gmina_code, current_value, threshold_value, spo, message, event_id, from_level, to_level, area, hazard_code, recommended_spo, reason
}
'@ -split '---NEXT---'

Write-Step "Workspace: $WorkspaceName"
$ResolvedWorkspaceId = Resolve-Workspace
Write-Ok "workspace id = $ResolvedWorkspaceId"

Write-Step 'Activator'
$Activator = Get-OrCreate-Activator -workspaceId $ResolvedWorkspaceId
Set-ActivatorEventstreamSource -workspaceId $ResolvedWorkspaceId -activatorId $Activator.id

Write-Step 'Funkcje KQL alertów'
foreach ($command in $FunctionCommands) {
    Invoke-KustoMgmt $command.Trim()
}
Write-Ok "utworzono/zaktualizowano $($FunctionCommands.Count) funkcji"

Write-Step 'Weryfikacja trafień'
$functions = @(
    'alert_hydro_alarm',
    'alert_hydro_rapid_rise',
    'alert_incident_spike',
    'alert_power_outage',
    'alert_telco_coverage_drop',
    'alert_disinformation_z20',
    'alert_escalation_rzzk'
)
foreach ($functionName in $functions) {
    $metrics = Invoke-KustoQuery "$functionName() | summarize hits=count(), keys=dcount(alert_key), gminas=dcount(gmina_code), first_ts=min(alert_ts)"
    $sample = Invoke-KustoQuery "$functionName() | top 1 by alert_ts asc | project alert_rule, alert_severity, alert_ts, gmina_code, current_value, threshold_value, message"
    Write-Host "`n$functionName" -ForegroundColor Yellow
    Write-Host "  metrics: $($metrics.Rows[0] | ConvertTo-Json -Compress)"
    Write-Host "  sample : $($sample.Rows[0] | ConvertTo-Json -Compress)"
}

Write-Ok 'Gotowe. Reguły KQL działają; powiadomienia Activator dokończ w UI wg activator\RULES.md.'
