<#
.SYNOPSIS
    Wdrozenie demo COP-24 do Microsoft Fabric.

.DESCRIPTION
    Tworzy i konfiguruje elementy Fabric potrzebne do uruchomienia demo:
      - Lakehouse (wymiary i dane referencyjne)
      - Eventhouse / baza KQL (strumienie telemetrii)
      - tabele i mapowania JSON w bazie KQL
      - wgranie plikow danych do OneLake
      - zaladowanie strumieni JSONL do Eventhouse

    Uwierzytelnienie: Azure CLI (`az login`). Skrypt pobiera tokeny dla
    api.fabric.microsoft.com (Fabric REST), storage.azure.com (OneLake)
    oraz kusto.kusto.windows.net (Eventhouse).

.PARAMETER WorkspaceName
    Nazwa workspace w Fabric. Musi istniec albo zostanie utworzona na wskazanej pojemnosci.

.PARAMETER CapacityName
    Nazwa pojemnosci Fabric (uzywana tylko przy tworzeniu nowego workspace).

.PARAMETER Step
    Ktory etap wykonac: all | items | kql | upload | ingest | verify

.EXAMPLE
    .\deploy\deploy_fabric.ps1 -WorkspaceName OL-ZK-Demo-COP24
#>
[CmdletBinding()]
param(
    [string]$WorkspaceName = 'OL-ZK-Demo-COP24',
    [string]$CapacityName  = '',
    [ValidateSet('all', 'items', 'kql', 'upload', 'ingest', 'verify')]
    [string]$Step = 'all'
)

$ErrorActionPreference = 'Stop'
$RepoRoot       = Split-Path -Parent $PSScriptRoot
$LakehouseName  = 'OL_COP24_Lakehouse'
$EventhouseName = 'OL_COP24_Eventhouse'
$FabricApi      = 'https://api.fabric.microsoft.com/v1'

function Write-Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Warn($msg) { Write-Host "  [UWAGA] $msg" -ForegroundColor Yellow }

function Get-Token($resource) {
    az account get-access-token --resource $resource --query accessToken -o tsv
}

function Get-FabricHeaders {
    @{ Authorization = "Bearer $(Get-Token 'https://api.fabric.microsoft.com')"; 'Content-Type' = 'application/json' }
}

function Resolve-Workspace {
    $h = Get-FabricHeaders
    $ws = (Invoke-RestMethod -Uri "$FabricApi/workspaces" -Headers $h).value |
          Where-Object displayName -eq $WorkspaceName | Select-Object -First 1
    if ($ws) { return $ws }

    if (-not $CapacityName) { throw "Workspace '$WorkspaceName' nie istnieje. Podaj -CapacityName, aby go utworzyc." }
    $cap = (Invoke-RestMethod -Uri "$FabricApi/capacities" -Headers $h).value |
           Where-Object displayName -eq $CapacityName | Select-Object -First 1
    if (-not $cap) { throw "Nie znaleziono pojemnosci '$CapacityName'." }

    $body = @{ displayName = $WorkspaceName; capacityId = $cap.id } | ConvertTo-Json
    Invoke-RestMethod -Uri "$FabricApi/workspaces" -Headers $h -Method Post -Body $body
}

function New-FabricItem($workspaceId, $type, $name) {
    $h = Get-FabricHeaders
    $existing = (Invoke-RestMethod -Uri "$FabricApi/workspaces/$workspaceId/items" -Headers $h).value |
                Where-Object { $_.displayName -eq $name -and $_.type -eq $type } | Select-Object -First 1
    if ($existing) { Write-Info "$type '$name' juz istnieje"; return $existing }

    $body = @{ displayName = $name; type = $type } | ConvertTo-Json
    $r = Invoke-WebRequest -Uri "$FabricApi/workspaces/$workspaceId/items" -Headers $h -Method Post -Body $body
    if ($r.StatusCode -eq 202) {
        $op = $r.Headers.Location | Select-Object -First 1
        do {
            Start-Sleep 5
            $st = Invoke-RestMethod -Uri $op -Headers (Get-FabricHeaders)
        } while ($st.status -in 'Running', 'NotStarted')
    }
    $created = (Invoke-RestMethod -Uri "$FabricApi/workspaces/$workspaceId/items" -Headers (Get-FabricHeaders)).value |
               Where-Object { $_.displayName -eq $name -and $_.type -eq $type } | Select-Object -First 1
    Write-Ok "utworzono $type '$name'"
    return $created
}

function Invoke-KustoMgmt($clusterUri, $database, $command) {
    $h = @{ Authorization = "Bearer $(Get-Token 'https://kusto.kusto.windows.net')"; 'Content-Type' = 'application/json' }
    $body = @{ db = $database; csl = $command } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Uri "$clusterUri/v1/rest/mgmt" -Headers $h -Method Post -Body $body
}

function Invoke-KustoQuery($clusterUri, $database, $query) {
    $h = @{ Authorization = "Bearer $(Get-Token 'https://kusto.kusto.windows.net')"; 'Content-Type' = 'application/json' }
    $body = @{ db = $database; csl = $query } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Uri "$clusterUri/v1/rest/query" -Headers $h -Method Post -Body $body
}

# Dzieli plik .kql na pojedyncze komendy sterujace (kazda zaczyna sie od kropki).
function Split-KqlCommands($path) {
    $commands = @()
    $current = ''
    foreach ($line in (Get-Content $path)) {
        if ($line -match '^\s*//' -or $line.Trim() -eq '') { continue }
        if ($line -match '^\s*\.' -and $current.Trim()) { $commands += $current; $current = $line }
        else { if ($current) { $current += "`n$line" } else { $current = $line } }
    }
    if ($current.Trim()) { $commands += $current }
    return $commands
}

function Send-ToOneLake($workspaceId, $lakehouseId, $localPath, $relativePath) {
    $token = Get-Token 'https://storage.azure.com'
    $h = @{ Authorization = "Bearer $token"; 'x-ms-version' = '2021-06-08' }
    $url = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files/$relativePath"

    Invoke-RestMethod -Uri "${url}?resource=file" -Headers $h -Method Put | Out-Null

    # Duze pliki wysylamy porcjami - pojedynczy append ma limit po stronie uslugi.
    $chunkSize = 8MB
    $stream = [System.IO.File]::OpenRead($localPath)
    try {
        $buffer = New-Object byte[] $chunkSize
        $position = 0L
        $hAppend = $h.Clone(); $hAppend['Content-Type'] = 'application/octet-stream'
        while (($read = $stream.Read($buffer, 0, $chunkSize)) -gt 0) {
            $chunk = New-Object byte[] $read
            [Array]::Copy($buffer, 0, $chunk, 0, $read)
            Invoke-RestMethod -Uri "${url}?action=append&position=$position" -Headers $hAppend -Method Patch -Body $chunk | Out-Null
            $position += $read
        }
        Invoke-RestMethod -Uri "${url}?action=flush&position=$position" -Headers $h -Method Patch | Out-Null
    } finally { $stream.Dispose() }
    Write-Ok "$relativePath ($([math]::Round($position / 1MB, 1)) MB)"
}

# =========================================================================
Write-Step "Workspace: $WorkspaceName"
$ws = Resolve-Workspace
Write-Ok "workspace id = $($ws.id)"

Write-Step 'Elementy workspace'
$lakehouse  = New-FabricItem $ws.id 'Lakehouse'  $LakehouseName
$eventhouse = New-FabricItem $ws.id 'Eventhouse' $EventhouseName

$h = Get-FabricHeaders
$ehDetail   = Invoke-RestMethod -Uri "$FabricApi/workspaces/$($ws.id)/eventhouses/$($eventhouse.id)" -Headers $h
$clusterUri = $ehDetail.properties.queryServiceUri
$kqlDbName  = ((Invoke-RestMethod -Uri "$FabricApi/workspaces/$($ws.id)/kqlDatabases" -Headers $h).value |
               Where-Object id -eq $ehDetail.properties.databasesItemIds[0]).displayName
Write-Info "cluster  = $clusterUri"
Write-Info "baza KQL = $kqlDbName"

if ($Step -in 'all', 'kql') {
    Write-Step 'Tabele i mapowania w Eventhouse'
    foreach ($file in @('01_create_tables.kql', '02_update_policies.kql')) {
        $path = Join-Path $RepoRoot "kql\$file"
        if (-not (Test-Path $path)) { continue }
        foreach ($cmd in Split-KqlCommands $path) {
            $head = $cmd.Split("`n")[0]
            $head = $head.Substring(0, [Math]::Min(85, $head.Length))
            try { Invoke-KustoMgmt $clusterUri $kqlDbName $cmd | Out-Null; Write-Ok $head }
            catch { Write-Warn "$head :: $($_.Exception.Message)" }
        }
    }
}

if ($Step -in 'all', 'upload') {
    Write-Step 'Wgrywanie plikow do OneLake'
    Get-ChildItem "$RepoRoot\datasets" -Filter *.csv | ForEach-Object {
        Send-ToOneLake $ws.id $lakehouse.id $_.FullName "datasets/$($_.Name)"
    }
    Get-ChildItem "$RepoRoot\datasets" -Filter *.jsonl | ForEach-Object {
        Send-ToOneLake $ws.id $lakehouse.id $_.FullName "streams/$($_.Name)"
    }
}

if ($Step -in 'all', 'ingest') {
    Write-Step 'Ladowanie strumieni do Eventhouse'
    $map = [ordered]@{
        'hydro_readings'       = 'hydro_json'
        'weather_observations' = 'weather_json'
        'incident_reports'     = 'incident_json'
        'power_grid_events'    = 'power_json'
        'telecom_events'       = 'telecom_json'
        'evacuation_status'    = 'evacuation_json'
        'resource_deployment'  = 'resource_json'
        'media_signals'        = 'media_json'
        'escalation_events'    = 'escalation_json'
    }
    foreach ($table in $map.Keys) {
        $url = "https://onelake.dfs.fabric.microsoft.com/$($ws.id)/$($lakehouse.id)/Files/streams/$table.jsonl"
        $cmd = ".ingest into table $table ('$url;impersonate') with (format='multijson', ingestionMappingReference='$($map[$table])')"
        try { Invoke-KustoMgmt $clusterUri $kqlDbName $cmd | Out-Null; Write-Ok "zaladowano $table" }
        catch { Write-Warn "$table :: $($_.Exception.Message)" }
    }
}

if ($Step -in 'all', 'verify') {
    Write-Step 'Weryfikacja'
    $q = 'union withsource=T * | summarize Rekordy = count(), Od = min(timestamp), Do = max(timestamp) by Tabela = T | order by Tabela asc'
    $res  = Invoke-KustoQuery $clusterUri $kqlDbName $q
    $cols = $res.Tables[0].Columns.ColumnName
    $res.Tables[0].Rows | ForEach-Object {
        $row = $_; $o = [ordered]@{}
        for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
        [PSCustomObject]$o
    } | Format-Table -AutoSize
}

Write-Host "`nGotowe. Workspace: https://app.fabric.microsoft.com/groups/$($ws.id)" -ForegroundColor Cyan
