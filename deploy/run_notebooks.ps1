<#
.SYNOPSIS
    Uruchamia notatniki przeliczajace warstwe Lakehouse po regeneracji danych.

.DESCRIPTION
    Kolejnosc ma znaczenie: wymiary -> strumienie -> indeks sytuacji -> rekomendacje.
    Kazdy notatnik jest uruchamiany przez Fabric Jobs API i odpytywany az do zakonczenia.

.EXAMPLE
    .\deploy\run_notebooks.ps1
#>
[CmdletBinding()]
param(
    [string]$WorkspaceId = '8ea0556f-7368-4b36-ad84-adf995e19a80',
    [string[]]$Notebooks = @('01_load_dimensions', '01b_load_streams', '02_situation_index', '03_escalation_recommendation'),
    [int]$TimeoutMinutes = 25
)

$ErrorActionPreference = 'Stop'
$FabricApi = 'https://api.fabric.microsoft.com/v1'

$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
if (-not $token) { throw 'Brak tokenu Fabric. Uruchom az login.' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$items = (Invoke-RestMethod -Uri "$FabricApi/workspaces/$WorkspaceId/notebooks" -Headers $headers).value
$results = [System.Collections.Generic.List[object]]::new()

foreach ($name in $Notebooks) {
    $item = $items | Where-Object displayName -eq $name
    if (-not $item) { throw "Nie znaleziono notatnika '$name' w workspace." }

    Write-Host "=== $name" -ForegroundColor Cyan
    $start = Get-Date
    $run = Invoke-WebRequest -Method POST -Headers $headers `
        -Uri "$FabricApi/workspaces/$WorkspaceId/items/$($item.id)/jobs/instances?jobType=RunNotebook" -Body '{}'
    $location = @($run.Headers.Location) | Select-Object -First 1
    if (-not $location) { throw "$name : brak naglowka Location w odpowiedzi." }

    do {
        Start-Sleep -Seconds 10
        $status = (Invoke-RestMethod -Uri $location -Headers $headers).status
        $elapsed = [int]((Get-Date) - $start).TotalSeconds
        Write-Host "  $status ($elapsed s)" -ForegroundColor Gray
        if ($elapsed -gt $TimeoutMinutes * 60) { throw "$name : przekroczono limit $TimeoutMinutes min." }
    } while ($status -in @('NotStarted', 'InProgress', 'Running'))

    if ($status -ne 'Completed') { throw "$name zakonczyl sie statusem $status." }
    $results.Add([pscustomobject]@{ Notatnik = $name; Status = $status; Sekundy = [int]((Get-Date) - $start).TotalSeconds })
}

$results | Format-Table -AutoSize
