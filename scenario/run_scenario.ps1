<#
.SYNOPSIS
    Uruchamia scenariusz kryzysowy COP-24 od zera i zasila Eventhouse w czasie rzeczywistym.

.DESCRIPTION
    Skrypt jest idempotentny: kazde uruchomienie z -Reset czysci tabele strumieniowe
    i odtwarza scenariusz powodziowy od pierwszego zdarzenia. Dashboard Real-Time
    zapelnia sie na oczach widowni, bo streaming ingestion Eventhouse pokazuje
    zdarzenia ponizej sekundy od wyslania.

.PARAMETER Preset
    demo    - 13 dob w ok. 5 min (godzina scenariusza na sekunde) - domyslny
    szybki  - 13 dob w ok. 2 min
    kulminacja - tylko doba przelomowa D0, w ok. 4 min, tempo dogodne do narracji
    wolny   - 13 dob w ok. 22 min, do prezentacji w tle

.PARAMETER Reset
    Czysci tabele strumieniowe przed startem. Domyslnie wlaczone.

.PARAMETER ResetOnly
    Tylko czysci tabele i konczy prace.

.PARAMETER TimeMode
    source - zachowuje oryginalne znaczniki czasu scenariusza (zgodne z zakresem dashboardu)
    now    - przesuwa scenariusz tak, by zaczynal sie w chwili uruchomienia

.EXAMPLE
    .\scenario\run_scenario.ps1
.EXAMPLE
    .\scenario\run_scenario.ps1 -Preset kulminacja
.EXAMPLE
    .\scenario\run_scenario.ps1 -ResetOnly
#>
[CmdletBinding()]
param(
    [ValidateSet('demo', 'szybki', 'kulminacja', 'wolny')]
    [string]$Preset = 'demo',
    [switch]$NoReset,
    [switch]$ResetOnly,
    [ValidateSet('source', 'now')]
    [string]$TimeMode = 'source',
    [double]$Speed,
    [string]$Streams
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$presets = @{
    demo       = @{ Speed = 300;  LiveHours = 24; From = $null }
    szybki     = @{ Speed = 900;  LiveHours = 24; From = $null }
    kulminacja = @{ Speed = 120;  LiveHours = 12; From = '2026-09-15T06:00:00+02:00' }
    wolny      = @{ Speed = 60;   LiveHours = 12; From = $null }
}
$selected = $presets[$Preset]
if ($PSBoundParameters.ContainsKey('Speed')) { $selected.Speed = $Speed }

Write-Host "=== Scenariusz COP-24: powodz w dorzeczu Nysy Klodzkiej" -ForegroundColor Cyan
Write-Host "  wariant:   $Preset"
Write-Host "  tempo:     $($selected.Speed)x czasu rzeczywistego"
Write-Host "  okno live: $($selected.LiveHours) h scenariusza"
Write-Host "  znaczniki: $TimeMode"

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Brak python w PATH.' }

$argv = @((Join-Path $PSScriptRoot 'replay.py'), '--speed', $selected.Speed,
          '--live-hours', $selected.LiveHours, '--time-mode', $TimeMode)
if (-not $NoReset) { $argv += @('--reset', '--bulk') }
if ($ResetOnly) { $argv += @('--reset', '--reset-only') }
if ($selected.From) { $argv += @('--from', $selected.From) }
if ($Streams) { $argv += @('--streams', $Streams) }

Push-Location $repo
try {
    & $python.Source @args
    if ($LASTEXITCODE -ne 0) { throw "replay.py zakonczyl sie kodem $LASTEXITCODE" }
}
finally {
    Pop-Location
}

if (-not $ResetOnly) {
    Write-Host ''
    Write-Host 'Dashboard: https://app.fabric.microsoft.com/groups/8ea0556f-7368-4b36-ad84-adf995e19a80' -ForegroundColor Green
    Write-Host 'Wskazowka: wlacz auto-odswiezanie na dashboardzie, aby widziec naplyw zdarzen.'
}
