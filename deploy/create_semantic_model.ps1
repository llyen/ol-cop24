[CmdletBinding()]
param(
    [string]$WorkspaceName = 'OL-ZK-Demo-COP24',
    [string]$WorkspaceId = '8ea0556f-7368-4b36-ad84-adf995e19a80',
    [string]$LakehouseId = '2d840a79-be01-4f82-be45-d4d45e0992ea',
    [string]$LakehouseName = 'OL_COP24_Lakehouse',
    [string]$SemanticModelName = 'OL_COP24_SemanticModel',
    [string]$ReportName = 'OL_COP24_Raport',
    [switch]$SkipReport
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$OutRoot = Join-Path $RepoRoot 'semantic-model\generated'
$ReportOutRoot = Join-Path $RepoRoot 'semantic-model\report'
New-Item -ItemType Directory -Force -Path $OutRoot, $ReportOutRoot | Out-Null

function Get-AccessToken([string]$Resource) {
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if (-not $token) { throw "Nie udało się pobrać tokenu dla $Resource. Uruchom az login." }
    return $token
}

function New-AuthHeaders([string]$Token) {
    return @{
        Authorization = "Bearer $Token"
        'Content-Type' = 'application/json; charset=utf-8'
    }
}

function Invoke-FabricJson {
    param(
        [ValidateSet('GET','POST','PATCH','DELETE')] [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        $Body = $null
    )
    try {
        $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 100 -Compress } else { $null }
        if ($json) {
            return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers -Body $json
        }
        return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'n/a' }
        $details = $_.ErrorDetails.Message
        if (-not $details) { $details = $_.Exception.Message }
        throw "REST $Method $Uri nie powiódł się ($status): $details"
    }
}

function Wait-FabricOperation {
    param([Microsoft.PowerShell.Commands.WebResponseObject]$Response, [hashtable]$Headers)
    if ([int]$Response.StatusCode -ne 202) { return }
    $location = @($Response.Headers.Location) | Select-Object -First 1
    if (-not $location) { return }
    do {
        Start-Sleep -Seconds 5
        $op = Invoke-FabricJson -Method GET -Uri $location -Headers $Headers
        $body = if ($op.Content) { $op.Content | ConvertFrom-Json } else { $null }
        $status = $body.status
        Write-Host "Operacja Fabric: $status"
        if ($status -eq 'Failed') {
            $code = $body.error.errorCode
            $msg = $body.error.message
            throw "Operacja Fabric zakończona błędem: $code $msg"
        }
    } while ($status -in @('Running','NotStarted'))
}

function ConvertTo-InlineBase64([string]$Text) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function New-Part([string]$Path, [string]$Text) {
    return @{ path = $Path; payload = (ConvertTo-InlineBase64 $Text); payloadType = 'InlineBase64' }
}

function Save-DefinitionPart([string]$Root, [string]$Path, [string]$Text) {
    $full = Join-Path $Root $Path
    $dir = Split-Path -Parent $full
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path $full -Value $Text -Encoding utf8
}

function Get-Items([hashtable]$Headers) {
    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items"
    return (Invoke-FabricJson -Method GET -Uri $uri -Headers $Headers).Content | ConvertFrom-Json
}

function Find-Item([hashtable]$Headers, [string]$DisplayName, [string]$Type) {
    $items = Get-Items $Headers
    return @($items.value | Where-Object { $_.displayName -eq $DisplayName -and $_.type -eq $Type }) | Select-Object -First 1
}

function Get-LakehouseProperties([hashtable]$Headers) {
    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses/$LakehouseId"
    return ((Invoke-FabricJson -Method GET -Uri $uri -Headers $Headers).Content | ConvertFrom-Json).properties
}

$ColumnMap = [ordered]@{
    dim_voivodeship = @(
        @('voivodeship_code','string'), @('voivodeship_name','string'), @('population','string'), @('wczk_seat','string'), @('lat','string'), @('lon','string'), @('ingested_at','dateTime')
    )
    dim_powiat = @(
        @('powiat_code','string'), @('powiat_name','string'), @('voivodeship_code','string'), @('population','string'), @('area_km2','string'), @('lat','string'), @('lon','string'), @('ingested_at','dateTime')
    )
    dim_gmina = @(
        @('gmina_code','string'), @('gmina_name','string'), @('powiat_code','string'), @('gmina_type','string'), @('population','string'), @('lat','string'), @('lon','string'), @('ingested_at','dateTime')
    )
    dim_hazard = @(
        @('hazard_code','string'), @('hazard_name','string'), @('lead_minister','string'), @('cooperating_ministers','string'), @('ingested_at','dateTime')
    )
    dim_institution = @(
        @('institution_id','string'), @('institution_code','string'), @('institution_name','string'), @('level','string'), @('seat','string'), @('ingested_at','dateTime')
    )
    dim_spo = @(
        @('spo_code','string'), @('spo_name','string'), @('ingested_at','dateTime')
    )
    dim_river_gauge = @(
        @('gauge_id','string'), @('gauge_name','string'), @('river','string'), @('gmina_code','string'), @('warning_level_cm','string'), @('alarm_level_cm','string'), @('lat','string'), @('lon','string'), @('wave_delay_h','string'), @('ingested_at','dateTime')
    )
    hydro_readings = @(
        @('timestamp','dateTime'), @('stream','string'), @('gauge_id','string'), @('gmina_code','int64'), @('river','string'), @('level_cm','int64'), @('flow_m3s','double'), @('trend','string'), @('warning_level_cm','int64'), @('alarm_level_cm','int64')
    )
    incident_reports = @(
        @('timestamp','dateTime'), @('stream','string'), @('incident_id','string'), @('source','string'), @('hazard_code','string'), @('event_type','string'), @('gmina_code','int64'), @('priority','int64'), @('injured_count','int64'), @('affected_people','int64'), @('status','string')
    )
    power_grid_events = @(
        @('timestamp','dateTime'), @('stream','string'), @('event_id','string'), @('station','string'), @('gmina_code','int64'), @('customers_offline','int64'), @('eta_restore_min','int64'), @('cause','string')
    )
    telecom_events = @(
        @('timestamp','dateTime'), @('stream','string'), @('event_id','string'), @('operator','string'), @('gmina_code','int64'), @('base_stations_down','int64'), @('coverage_pct','double'), @('cause','string')
    )
    evacuation_status = @(
        @('timestamp','dateTime'), @('stream','string'), @('event_id','string'), @('gmina_code','int64'), @('status','string'), @('people_count','int64'), @('reception_capacity','int64'), @('spo_code','string')
    )
    resource_deployment = @(
        @('timestamp','dateTime'), @('stream','string'), @('event_id','string'), @('voivodeship_code','int64'), @('psp_units','int64'), @('wot_soldiers','int64'), @('pumps','int64'), @('generators','int64'), @('helicopters','int64')
    )
    media_signals = @(
        @('timestamp','dateTime'), @('stream','string'), @('signal_id','string'), @('topic','string'), @('sentiment','string'), @('reach','int64'), @('disinformation_flag','boolean'), @('hazard_code','string'), @('channel','string')
    )
    escalation_events = @(
        @('timestamp','dateTime'), @('stream','string'), @('event_id','string'), @('from_level','string'), @('to_level','string'), @('area','string'), @('hazard_code','string'), @('recommended_spo','string'), @('reason','string')
    )
    kis_gmina = @(
        @('gmina_code','string'), @('powiat_code','string'), @('hydro_score','double'), @('incident_score','double'), @('affected_people','int64'), @('power_score','double'), @('telecom_score','double'), @('evac_score','double'), @('resource_score','int64'), @('kis','double')
    )
    kis_powiat = @(
        @('powiat_code','string'), @('kis','double'), @('max_kis','double')
    )
    kis_voivodeship = @(
        @('voivodeship_code','string'), @('kis','double'), @('max_kis','double')
    )
    kis_country = @(
        @('kis_country','double'), @('max_local_kis','double')
    )
    escalation_recommendations = @(
        @('gmina_code','string'), @('powiat_code','string'), @('hydro_score','double'), @('incident_score','double'), @('affected_people','int64'), @('power_score','double'), @('telecom_score','double'), @('evac_score','double'), @('resource_score','int64'), @('kis','double'), @('recommended_level','string'), @('recommended_spo','string'), @('explanation','string')
    )
}

$Measures = @(
    @{Name='KIS'; Expression='AVERAGE(kis_gmina[kis])'; Format='0.0'},
    @{Name='KIS Max Lokalny'; Expression='MAX(kis_gmina[kis])'; Format='0.0'},
    @{Name='Liczba Ewakuowanych'; Expression='SUM(evacuation_status[people_count])'; Format='#,0'},
    @{Name='% Gmin w Alarmie'; Expression='DIVIDE(CALCULATE(DISTINCTCOUNT(hydro_readings[gmina_code]), hydro_readings[level_cm] >= hydro_readings[alarm_level_cm]), DISTINCTCOUNT(dim_gmina[gmina_code]))'; Format='0.0%'},
    @{Name='Odbiorcy Bez Prądu'; Expression='SUM(power_grid_events[customers_offline])'; Format='#,0'},
    @{Name='Minimalne Pokrycie Telco'; Expression='MIN(telecom_events[coverage_pct]) / 100'; Format='0.0%'},
    @{Name='Gminy Telco Ponizej 50'; Expression='CALCULATE(DISTINCTCOUNT(telecom_events[gmina_code]), telecom_events[coverage_pct] < 50)'; Format='#,0'},
    @{Name='Incydenty'; Expression='COUNTROWS(incident_reports)'; Format='#,0'},
    @{Name='Incydenty Priorytet 4 Plus'; Expression='CALCULATE(COUNTROWS(incident_reports), incident_reports[priority] >= 4)'; Format='#,0'},
    @{Name='Osoby Dotkniete'; Expression='SUM(incident_reports[affected_people])'; Format='#,0'},
    @{Name='Zgloszenia 15 Min'; Expression='COUNTROWS(incident_reports)'; Format='#,0'},
    @{Name='Sygnały Dezinformacji'; Expression='CALCULATE(COUNTROWS(media_signals), media_signals[disinformation_flag] = TRUE())'; Format='#,0'},
    @{Name='Zasieg Dezinformacji'; Expression='CALCULATE(SUM(media_signals[reach]), media_signals[disinformation_flag] = TRUE())'; Format='#,0'},
    @{Name='PSP Zastepy'; Expression='SUM(resource_deployment[psp_units])'; Format='#,0'},
    @{Name='WOT Zolnierze'; Expression='SUM(resource_deployment[wot_soldiers])'; Format='#,0'},
    @{Name='Pompy'; Expression='SUM(resource_deployment[pumps])'; Format='#,0'},
    @{Name='Agregaty'; Expression='SUM(resource_deployment[generators])'; Format='#,0'},
    @{Name='Smiglowce'; Expression='SUM(resource_deployment[helicopters])'; Format='#,0'},
    @{Name='Czas Reakcji Min'; Expression='AVERAGEX(escalation_events, DATEDIFF(escalation_events[timestamp], NOW(), MINUTE))'; Format='#,0'},
    @{Name='Rekomendacje RZZK'; Expression='CALCULATE(COUNTROWS(escalation_recommendations), escalation_recommendations[recommended_level] = "RZZK")'; Format='#,0'},
    @{Name='Gminy KIS Powiat Plus'; Expression='CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 25)'; Format='#,0'},
    @{Name='Gminy KIS Wojewoda Plus'; Expression='CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 45)'; Format='#,0'},
    @{Name='Gminy KIS RZZK'; Expression='CALCULATE(DISTINCTCOUNT(kis_gmina[gmina_code]), kis_gmina[kis] >= 85)'; Format='#,0'},
    @{Name='Alarm Hydro'; Expression='CALCULATE(DISTINCTCOUNT(hydro_readings[gauge_id]), hydro_readings[level_cm] >= hydro_readings[alarm_level_cm])'; Format='#,0'},
    @{Name='Stan Ostrzegawczy Hydro'; Expression='CALCULATE(DISTINCTCOUNT(hydro_readings[gauge_id]), hydro_readings[level_cm] >= hydro_readings[warning_level_cm], hydro_readings[level_cm] < hydro_readings[alarm_level_cm])'; Format='#,0'}
)

$Relationships = @(
    @('rel_dim_powiat_dim_voivodeship','dim_powiat.voivodeship_code','dim_voivodeship.voivodeship_code'),
    @('rel_dim_gmina_dim_powiat','dim_gmina.powiat_code','dim_powiat.powiat_code'),
    @('rel_dim_river_gauge_dim_gmina','dim_river_gauge.gmina_code','dim_gmina.gmina_code'),
    @('rel_kis_gmina_dim_gmina','kis_gmina.gmina_code','dim_gmina.gmina_code'),
    @('rel_kis_powiat_dim_powiat','kis_powiat.powiat_code','dim_powiat.powiat_code'),
    @('rel_kis_voivodeship_dim_voivodeship','kis_voivodeship.voivodeship_code','dim_voivodeship.voivodeship_code'),
    @('rel_escalation_recommendations_dim_gmina','escalation_recommendations.gmina_code','dim_gmina.gmina_code'),
    @('rel_incident_reports_dim_hazard','incident_reports.hazard_code','dim_hazard.hazard_code'),
    @('rel_media_signals_dim_hazard','media_signals.hazard_code','dim_hazard.hazard_code'),
    @('rel_evacuation_status_dim_spo','evacuation_status.spo_code','dim_spo.spo_code')
)

function Quote-TmdlName([string]$Name) {
    if ($Name -match '[\s\.=:'']') { return "'" + $Name.Replace("'","''") + "'" }
    return $Name
}

function New-TableTmdl([string]$TableName, [array]$Columns, [string]$ExpressionName, [bool]$UseSchemaName, [array]$MeasuresForTable) {
    $qTable = Quote-TmdlName $TableName
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("table $qTable")
    $lines.Add("`tsourceLineageTag: [dbo].[$TableName]")
    $lines.Add("")
    foreach ($c in $Columns) {
        $name = $c[0]; $type = $c[1]
        $qCol = Quote-TmdlName $name
        $lines.Add("`tcolumn $qCol")
        $lines.Add("`t`tdataType: $type")
        if ($type -eq 'int64') { $lines.Add("`t`tformatString: 0") }
        $summ = if ($type -in @('string','dateTime','boolean')) { 'none' } else { 'sum' }
        $lines.Add("`t`tsourceLineageTag: $name")
        $lines.Add("`t`tsummarizeBy: $summ")
        $lines.Add("`t`tsourceColumn: $name")
        $lines.Add("")
    }
    foreach ($m in $MeasuresForTable) {
        $qMeasure = Quote-TmdlName $m.Name
        $lines.Add("`tmeasure $qMeasure = $($m.Expression)")
        $lines.Add("`t`tformatString: $($m.Format)")
        $lines.Add("")
    }
    $lines.Add("`tpartition $qTable = entity")
    $lines.Add("`t`tmode: directLake")
    $lines.Add("`t`tsource")
    $lines.Add("`t`t`tentityName: $TableName")
    if ($UseSchemaName) { $lines.Add("`t`t`tschemaName: dbo") }
    $lines.Add("`t`t`texpressionSource: $(Quote-TmdlName $ExpressionName)")
    return ($lines -join "`r`n")
}

function New-SemanticDefinition([string[]]$Tables, [string]$ExpressionName, [string]$SourceUrl, [bool]$UseSchemaName, [string]$SourceKind = 'OneLake', [string]$SqlServer = '') {
    $parts = [System.Collections.Generic.List[object]]::new()
    $db = "database`r`n`tcompatibilityLevel: 1604`r`n"
    $modelLines = [System.Collections.Generic.List[string]]::new()
    $modelLines.Add("model Model")
    $modelLines.Add("`tculture: pl-PL")
    $modelLines.Add("`tdefaultPowerBIDataSourceVersion: powerBI_V3")
    $modelLines.Add("`tsourceQueryCulture: pl-PL")
    $modelLines.Add("`tdataAccessOptions")
    $modelLines.Add("`t`tlegacyRedirects")
    $modelLines.Add("`t`treturnErrorValuesAsNull")
    $modelLines.Add("")
    $modelLines.Add("annotation PBI_QueryOrder = [""$ExpressionName""]")
    $modelLines.Add("")
    $modelLines.Add("annotation __PBI_TimeIntelligenceEnabled = 1")
    $modelLines.Add("")
    $modelLines.Add("annotation PBI_ProTooling = [""DirectLakeOnOneLakeInWeb""]")
    $modelLines.Add("")
    foreach ($t in $Tables) { $modelLines.Add("ref table $(Quote-TmdlName $t)") }
    $model = $modelLines -join "`r`n"

    if ($SourceKind -eq 'SqlEndpoint') {
        $expr = @"
expression $(Quote-TmdlName $ExpressionName) =
		let
		    Source = Sql.Database("$SqlServer", "$LakehouseName")
		in
		    Source

	annotation PBI_IncludeFutureArtifacts = False
"@
    }
    else {
        $expr = @"
expression $(Quote-TmdlName $ExpressionName) =
		let
		    Source = AzureStorage.DataLake("$SourceUrl", [HierarchicalNavigation=true])
		in
		    Source

	annotation PBI_IncludeFutureArtifacts = False
"@
    }

    $relLines = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $Relationships) {
        $fromTable = $r[1].Split('.')[0]
        $toTable = $r[2].Split('.')[0]
        if ($Tables -contains $fromTable -and $Tables -contains $toTable) {
            $relLines.Add("relationship $($r[0])")
            $relLines.Add("`tfromColumn: $($r[1])")
            $relLines.Add("`ttoColumn: $($r[2])")
            $relLines.Add("")
        }
    }
    $relationships = $relLines -join "`r`n"

    $parts.Add((New-Part 'definition/database.tmdl' $db))
    Save-DefinitionPart $OutRoot 'definition\database.tmdl' $db
    $parts.Add((New-Part 'definition/model.tmdl' $model))
    Save-DefinitionPart $OutRoot 'definition\model.tmdl' $model
    $parts.Add((New-Part 'definition/expressions.tmdl' $expr))
    Save-DefinitionPart $OutRoot 'definition\expressions.tmdl' $expr
    if ($relationships.Trim()) {
        $parts.Add((New-Part 'definition/relationships.tmdl' $relationships))
        Save-DefinitionPart $OutRoot 'definition\relationships.tmdl' $relationships
    }
    foreach ($t in $Tables) {
        # Miary umieszczamy w tabeli kis_country, aby nie kolidowały z kolumną kis w kis_gmina.
        $meas = if ($t -eq 'kis_country') { $Measures } else { @() }
        if (-not ($Tables -contains 'hydro_readings')) {
            $meas = @($meas | Where-Object { $_.Expression -notmatch 'hydro_readings' })
        }
        if (-not ($Tables -contains 'telecom_events')) {
            $meas = @($meas | Where-Object { $_.Expression -notmatch 'telecom_events' })
        }
        $text = New-TableTmdl -TableName $t -Columns $ColumnMap[$t] -ExpressionName $ExpressionName -UseSchemaName $UseSchemaName -MeasuresForTable $meas
        $parts.Add((New-Part "definition/tables/$t.tmdl" $text))
        Save-DefinitionPart $OutRoot "definition\tables\$t.tmdl" $text
    }
    $pbism = @{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json'
        version = '5.0'
        settings = @{ qnaEnabled = $false }
    } | ConvertTo-Json -Depth 10
    $platform = @{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
        metadata = @{ type = 'SemanticModel'; displayName = $SemanticModelName }
        config = @{ version = '2.0'; logicalId = ([guid]::NewGuid().ToString()) }
    } | ConvertTo-Json -Depth 10
    $parts.Add((New-Part 'definition.pbism' $pbism))
    Save-DefinitionPart $OutRoot 'definition.pbism' $pbism
    $parts.Add((New-Part '.platform' $platform))
    Save-DefinitionPart $OutRoot '.platform' $platform
    return @{ format = 'TMDL'; parts = @($parts) }
}

function Upsert-SemanticModel([hashtable]$Headers) {
    $existing = Find-Item -Headers $Headers -DisplayName $SemanticModelName -Type 'SemanticModel'
    $lakePropsForSql = Get-LakehouseProperties $Headers
    $sqlServer = $lakePropsForSql.sqlEndpointProperties.connectionString
    $minimalTables = @('dim_gmina','kis_gmina','incident_reports')
    $fullTables = @(
        'dim_voivodeship','dim_powiat','dim_gmina','dim_hazard','dim_institution','dim_spo','dim_river_gauge',
        'hydro_readings','incident_reports','power_grid_events','telecom_events','evacuation_status','resource_deployment','media_signals','escalation_events',
        'kis_gmina','kis_powiat','kis_voivodeship','kis_country','escalation_recommendations'
    )
    $candidates = @(
        @{ ExpressionName='DirectLake - OL_COP24_Lakehouse'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId"; UseSchemaName=$true; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLake - OL_COP24_Lakehouse'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId"; UseSchemaName=$false; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLakeConnection'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId"; UseSchemaName=$true; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLakeConnection'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId"; UseSchemaName=$false; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLake - OL_COP24_Lakehouse'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId/Tables"; UseSchemaName=$true; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLake - OL_COP24_Lakehouse'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId/Tables"; UseSchemaName=$false; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLakeConnection'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId/Tables"; UseSchemaName=$true; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLakeConnection'; SourceUrl="https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId/Tables"; UseSchemaName=$false; SourceKind='OneLake'; SqlServer='' },
        @{ ExpressionName='DirectLakeSqlEndpoint'; SourceUrl=''; UseSchemaName=$false; SourceKind='SqlEndpoint'; SqlServer=$sqlServer }
    )
    $successCandidate = $null
    if (-not $existing) {
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $c = $candidates[$i]
            Write-Host "Próba Direct Lake $($i+1)/8: minimalny model, source=$($c.SourceUrl), schemaName=$($c.UseSchemaName), expression=$($c.ExpressionName)"
            try {
                $definition = New-SemanticDefinition -Tables $minimalTables -ExpressionName $c.ExpressionName -SourceUrl $c.SourceUrl -UseSchemaName $c.UseSchemaName -SourceKind $c.SourceKind -SqlServer $c.SqlServer
                $body = @{ displayName = $SemanticModelName; description = 'Model semantyczny Direct Lake COP-24 utworzony przez Fabric REST API'; definition = $definition }
                $resp = Invoke-FabricJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/semanticModels" -Headers $Headers -Body $body
                Wait-FabricOperation -Response $resp -Headers $Headers
                Start-Sleep -Seconds 8
                $existing = Find-Item -Headers $Headers -DisplayName $SemanticModelName -Type 'SemanticModel'
                if (-not $existing) { throw 'Model nie pojawił się na liście elementów po utworzeniu.' }
                $successCandidate = $c
                break
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
    }
    else {
        # Jeśli model już istnieje, użyj stabilnego wariantu Direct Lake on SQL przez SQL endpoint Lakehouse.
        $successCandidate = $candidates[8]
        Write-Host "Model $SemanticModelName już istnieje: $($existing.id). Używam updateDefinition."
    }
    if (-not $existing -or -not $successCandidate) { throw 'Nie udało się utworzyć minimalnego modelu Direct Lake po 8 próbach.' }

    Write-Host "Aktualizacja do pełnego modelu: $($fullTables.Count) tabel."
    $fullDefinition = New-SemanticDefinition -Tables $fullTables -ExpressionName $successCandidate.ExpressionName -SourceUrl $successCandidate.SourceUrl -UseSchemaName $successCandidate.UseSchemaName -SourceKind $successCandidate.SourceKind -SqlServer $successCandidate.SqlServer
    try {
        $body = @{ definition = $fullDefinition }
        $resp = Invoke-FabricJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition?updateMetadata=True" -Headers $Headers -Body $body
        Wait-FabricOperation -Response $resp -Headers $Headers
    }
    catch {
        Write-Warning "Pełny model z hydro_readings nie powiódł się: $($_.Exception.Message)"
        $reducedTables = @($fullTables | Where-Object { $_ -ne 'hydro_readings' })
        Write-Host "Ponawiam pełny zakres bez dużej tabeli hydro_readings: $($reducedTables.Count) tabel."
        $fullDefinition = New-SemanticDefinition -Tables $reducedTables -ExpressionName $successCandidate.ExpressionName -SourceUrl $successCandidate.SourceUrl -UseSchemaName $successCandidate.UseSchemaName -SourceKind $successCandidate.SourceKind -SqlServer $successCandidate.SqlServer
        $body = @{ definition = $fullDefinition }
        $resp = Invoke-FabricJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition?updateMetadata=True" -Headers $Headers -Body $body
        Wait-FabricOperation -Response $resp -Headers $Headers
    }
    return (Find-Item -Headers $Headers -DisplayName $SemanticModelName -Type 'SemanticModel')
}

function New-ReportDefinition([string]$SemanticModelId, [string]$Mode) {
    $parts = [System.Collections.Generic.List[object]]::new()
    $pbir = @{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json'
        version = '4.0'
        datasetReference = @{ byConnection = @{ connectionString = "semanticmodelid=$SemanticModelId" } }
    } | ConvertTo-Json -Depth 10
    $platform = @{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
        metadata = @{ type = 'Report'; displayName = $ReportName }
        config = @{ version = '2.0'; logicalId = ([guid]::NewGuid().ToString()) }
    } | ConvertTo-Json -Depth 10
    $parts.Add((New-Part 'definition.pbir' $pbir)); Save-DefinitionPart $ReportOutRoot 'definition.pbir' $pbir
    $parts.Add((New-Part '.platform' $platform)); Save-DefinitionPart $ReportOutRoot '.platform' $platform

    if ($Mode -eq 'PBIR') {
        $report = @{
            '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.1.0/schema.json'
            themeCollection = @{ baseTheme = @{ name = 'CY25SU12'; type = 'SharedResources'; reportVersionAtImport = @{ visual = '2.5.0'; page = '2.3.0'; report = '3.1.0' } } }
            settings = @{ useStylableVisualContainerHeader = $true; defaultFilterActionIsDataFilter = $true; useEnhancedTooltips = $true }
        } | ConvertTo-Json -Depth 20
        $version = @{
            '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/version/1.0.0/schema.json'
            version = '4.0'
        } | ConvertTo-Json -Depth 5
        $pageIds = @('obraz-kraju','wojewodztwo-gminy','eskalacja-spo')
        $pages = @{ pageOrder = $pageIds; activePage = $pageIds[0] } | ConvertTo-Json -Depth 10
        $parts.Add((New-Part 'definition/report.json' $report)); Save-DefinitionPart $ReportOutRoot 'definition\report.json' $report
        $parts.Add((New-Part 'definition/version.json' $version)); Save-DefinitionPart $ReportOutRoot 'definition\version.json' $version
        $parts.Add((New-Part 'definition/pages/pages.json' $pages)); Save-DefinitionPart $ReportOutRoot 'definition\pages\pages.json' $pages
        $titles = @{
            'obraz-kraju' = 'Obraz kraju'
            'wojewodztwo-gminy' = 'Województwo i gminy'
            'eskalacja-spo' = 'Eskalacja i SPO'
        }
        foreach ($p in $pageIds) {
            $page = @{
                '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.0.0/schema.json'
                name = $p
                displayName = $titles[$p]
                displayOption = 'FitToPage'
                height = 720
                width = 1280
            } | ConvertTo-Json -Depth 10
            $parts.Add((New-Part "definition/pages/$p/page.json" $page))
            Save-DefinitionPart $ReportOutRoot "definition\pages\$p\page.json" $page
        }
        return @{ format = 'PBIR'; parts = @($parts) }
    }

    $legacy = @{
        config = '{}'
        layoutOptimization = 0
        resourcePackages = @()
        sections = @(
            @{ name = 'ReportSectionObrazKraju'; displayName = 'Obraz kraju'; displayOption = 'FitToPage'; height = 720; width = 1280; visualContainers = @() },
            @{ name = 'ReportSectionWojGminy'; displayName = 'Województwo i gminy'; displayOption = 'FitToPage'; height = 720; width = 1280; visualContainers = @() },
            @{ name = 'ReportSectionEskalacjaSpo'; displayName = 'Eskalacja i SPO'; displayOption = 'FitToPage'; height = 720; width = 1280; visualContainers = @() }
        )
    } | ConvertTo-Json -Depth 20
    $parts.Add((New-Part 'report.json' $legacy)); Save-DefinitionPart $ReportOutRoot 'report.json' $legacy
    return @{ format = 'PBIR-Legacy'; parts = @($parts) }
}

function Upsert-Report([hashtable]$Headers, [string]$SemanticModelId) {
    $existing = Find-Item -Headers $Headers -DisplayName $ReportName -Type 'Report'
    foreach ($mode in @('PBIR','PBIR-Legacy')) {
        try {
            Write-Host "Tworzenie/aktualizacja raportu w formacie $mode."
            $definition = New-ReportDefinition -SemanticModelId $SemanticModelId -Mode $mode
            if ($existing) {
                $body = @{ definition = $definition }
                $resp = Invoke-FabricJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition?updateMetadata=True" -Headers $Headers -Body $body
            }
            else {
                $body = @{ displayName = $ReportName; description = 'Raport Power BI COP-24 utworzony przez Fabric REST API'; definition = $definition }
                $resp = Invoke-FabricJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/reports" -Headers $Headers -Body $body
            }
            Wait-FabricOperation -Response $resp -Headers $Headers
            Start-Sleep -Seconds 5
            return (Find-Item -Headers $Headers -DisplayName $ReportName -Type 'Report')
        }
        catch {
            Write-Warning "Raport $mode nie powiódł się: $($_.Exception.Message)"
        }
    }
    throw "Nie udało się wdrożyć raportu przez API. Pełna definicja jest zapisana lokalnie w $ReportOutRoot."
}

function Get-DefinitionStats([hashtable]$Headers, [string]$ItemId, [string]$Format) {
    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$ItemId/getDefinition"
    if ($Format) { $uri += "?format=$Format" }
    $resp = Invoke-FabricJson -Method POST -Uri $uri -Headers $Headers -Body @{}
    if ([int]$resp.StatusCode -eq 202) {
        $location = @($resp.Headers.Location) | Select-Object -First 1
        do {
            Start-Sleep -Seconds 3
            $op = Invoke-FabricJson -Method GET -Uri $location -Headers $Headers
            $body = if ($op.Content) { $op.Content | ConvertFrom-Json } else { $null }
            $status = $body.status
            $nextLocation = @($op.Headers.Location) | Select-Object -First 1
            if ($nextLocation) { $location = $nextLocation }
            if ($status -eq 'Failed') { throw "getDefinition failed: $($body.error.errorCode) $($body.error.message)" }
        } while ($status -in @('Running','NotStarted'))
        $result = Invoke-FabricJson -Method GET -Uri $location -Headers $Headers
        if (-not $result.Content) { return $null }
        return $result.Content | ConvertFrom-Json
    }
    if (-not $resp.Content) { return $null }
    return $resp.Content | ConvertFrom-Json
}

function Invoke-DaxCheck([string]$SemanticModelId) {
    $pbiToken = Get-AccessToken 'https://analysis.windows.net/powerbi/api'
    $headers = New-AuthHeaders $pbiToken
    $body = @{
        queries = @(@{ query = 'EVALUATE ROW("n", COUNTROWS(dim_gmina))' })
        serializerSettings = @{ includeNulls = $true }
    }
    $uri = "https://api.powerbi.com/v1.0/myorg/datasets/$SemanticModelId/executeQueries"
    $resp = Invoke-FabricJson -Method POST -Uri $uri -Headers $headers -Body $body
    return $resp.Content | ConvertFrom-Json
}

$fabricToken = Get-AccessToken 'https://api.fabric.microsoft.com'
$headers = New-AuthHeaders $fabricToken
$lakeProps = Get-LakehouseProperties $headers
Write-Host "Workspace: $WorkspaceName ($WorkspaceId)"
Write-Host "Lakehouse: $LakehouseName ($LakehouseId)"
Write-Host "SQL endpoint: $($lakeProps.sqlEndpointProperties.connectionString)"

$semantic = Upsert-SemanticModel $headers
Write-Host "Model semantyczny: $($semantic.displayName) id=$($semantic.id)"

$report = $null
if (-not $SkipReport) {
    $report = Upsert-Report -Headers $headers -SemanticModelId $semantic.id
    Write-Host "Raport: $($report.displayName) id=$($report.id)"
}

Start-Sleep -Seconds 10
$items = Get-Items $headers
$models = @($items.value | Where-Object type -eq 'SemanticModel')
$reports = @($items.value | Where-Object type -eq 'Report')
$semDef = Get-DefinitionStats -Headers $headers -ItemId $semantic.id -Format 'TMDL'
$semParts = @($semDef.definition.parts)
$tableCount = @($semParts | Where-Object { $_.path -like 'definition/tables/*.tmdl' }).Count
$relPart = @($semParts | Where-Object { $_.path -eq 'definition/relationships.tmdl' }) | Select-Object -First 1
$relCount = 0
if ($relPart) {
    $relText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($relPart.payload))
    $relCount = ([regex]::Matches($relText, '(?m)^relationship\s+')).Count
}
$measureCount = 0
foreach ($p in @($semParts | Where-Object { $_.path -like 'definition/tables/*.tmdl' })) {
    $txt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p.payload))
    $measureCount += ([regex]::Matches($txt, '(?m)^\s*measure\s+')).Count
}
$pageCount = 0
if ($report) {
    try {
        $repDef = Get-DefinitionStats -Headers $headers -ItemId $report.id -Format 'PBIR'
    }
    catch {
        $repDef = Get-DefinitionStats -Headers $headers -ItemId $report.id -Format ''
    }
    if ($repDef) {
        $pageCount = @($repDef.definition.parts | Where-Object { $_.path -match '^definition/pages/.+/page\.json$' }).Count
        if ($pageCount -eq 0) {
            $legacyPart = @($repDef.definition.parts | Where-Object { $_.path -eq 'report.json' }) | Select-Object -First 1
            if ($legacyPart) {
                $legacyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($legacyPart.payload))
                $pageCount = @(($legacyText | ConvertFrom-Json).sections).Count
            }
        }
    }
}

$daxResult = $null
try {
    $daxResult = Invoke-DaxCheck $semantic.id
    $row = $daxResult.results[0].tables[0].rows[0]
    $n = $row.PSObject.Properties['[n]'].Value
    if ($null -eq $n) { $n = $row.n }
    Write-Host "DAX OK: COUNTROWS(dim_gmina) = $n"
}
catch {
    Write-Warning "Weryfikacja DAX nie powiodła się: $($_.Exception.Message)"
}

[pscustomobject]@{
    SemanticModelId = $semantic.id
    ReportId = if ($report) { $report.id } else { $null }
    DirectLake = $true
    Tables = $tableCount
    Relationships = $relCount
    Measures = $measureCount
    ReportPages = $pageCount
    DaxCountRowsDimGmina = if ($daxResult) { $daxResult.results[0].tables[0].rows[0].PSObject.Properties['[n]'].Value } else { $null }
    LocalSemanticDefinition = $OutRoot
    LocalReportDefinition = $ReportOutRoot
    SemanticModelsInWorkspace = @($models).Count
    ReportsInWorkspace = @($reports).Count
} | ConvertTo-Json -Depth 10
