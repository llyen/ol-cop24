[CmdletBinding()]
param(
    [string]$WorkspaceId = '8ea0556f-7368-4b36-ad84-adf995e19a80',
    [string]$SemanticModelId = '669a6a2b-0115-4eeb-8f63-a6e1027133b0',
    [string]$ReportId = 'a0449186-59df-49f4-a151-9ceceb06726e',
    [string]$ReportName = 'OL_COP24_Raport',
    [switch]$GenerateOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ReportRoot = Join-Path $RepoRoot 'semantic-model\report'
$ThemeFile = 'COP24-CommandCenter-c0242026.json'
$VisualSchema = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/1.0.0/schema.json'

function Get-AccessToken([string]$Resource) {
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if (-not $token) { throw "Nie udało się pobrać tokenu dla $Resource. Uruchom az login." }
    return $token
}

function New-AuthHeaders([string]$Token) {
    return @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json; charset=utf-8' }
}

function Invoke-RestJson {
    param(
        [ValidateSet('GET','POST')] [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        $Body = $null
    )
    try {
        $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 100 -Compress } else { $null }
        if ($json) { return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers -Body $json }
        return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'n/a' }
        $details = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "REST $Method $Uri nie powiódł się ($status): $details"
    }
}

function Wait-FabricOperation([Microsoft.PowerShell.Commands.WebResponseObject]$Response, [hashtable]$Headers) {
    if ([int]$Response.StatusCode -ne 202) {
        if ($Response.Content) { return $Response.Content | ConvertFrom-Json }
        return $null
    }
    $location = @($Response.Headers.Location) | Select-Object -First 1
    if (-not $location) { throw 'Fabric zwrócił 202 bez nagłówka Location.' }
    do {
        Start-Sleep -Seconds 3
        $operation = Invoke-RestJson -Method GET -Uri $location -Headers $Headers
        $body = if ($operation.Content) { $operation.Content | ConvertFrom-Json } else { $null }
        $status = $body.status
        $nextLocation = @($operation.Headers.Location) | Select-Object -First 1
        if ($nextLocation) { $location = $nextLocation }
        Write-Host "Operacja Fabric: $status"
        if ($status -eq 'Failed') { throw "Operacja Fabric zakończona błędem: $($body.error.errorCode) $($body.error.message)" }
    } while ($status -in @('Running','NotStarted'))
    $result = Invoke-RestJson -Method GET -Uri $location -Headers $Headers
    if ($result.Content) { return $result.Content | ConvertFrom-Json }
    return $body
}

function ConvertTo-InlineBase64([string]$Text) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function New-Part([string]$Path, [string]$Text) {
    return @{ path = $Path; payload = (ConvertTo-InlineBase64 $Text); payloadType = 'InlineBase64' }
}

function Save-Part([string]$Path, [string]$Text) {
    $fullPath = Join-Path $ReportRoot $Path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullPath) | Out-Null
    Set-Content -LiteralPath $fullPath -Value $Text -Encoding utf8
}

function New-Lit([string]$Value) { return @{ expr = @{ Literal = @{ Value = $Value } } } }
function New-StringLit([string]$Value) { return New-Lit ("'" + $Value.Replace("'","''") + "'") }
function New-BoolLit([bool]$Value) { return New-Lit ($(if ($Value) { 'true' } else { 'false' })) }
function New-NumLit([double]$Value) { return New-Lit ("$Value" + 'D') }
function New-Color([string]$Hex) { return @{ solid = @{ color = (New-StringLit $Hex) } } }
function New-Col([string]$Table, [string]$Column) { return @{ Column = @{ Expression = @{ SourceRef = @{ Entity = $Table } }; Property = $Column } } }
function New-Meas([string]$Table, [string]$Measure) { return @{ Measure = @{ Expression = @{ SourceRef = @{ Entity = $Table } }; Property = $Measure } } }
function New-Agg([string]$Table, [string]$Column, [int]$Function) { return @{ Aggregation = @{ Expression = (New-Col $Table $Column); Function = $Function } } }

function New-Proj($Field, [string]$QueryRef, [string]$NativeRef, [string]$DisplayName = '') {
    $projection = [ordered]@{ field = $Field; queryRef = $QueryRef; nativeQueryRef = $NativeRef; active = $true }
    if ($DisplayName) { $projection.displayName = $DisplayName }
    return $projection
}

function New-PanelVco([string]$Title, [string]$Accent = '#22D3EE', [bool]$ShowTitle = $true) {
    $vco = [ordered]@{
        background = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color '#101B2D'); transparency = (New-NumLit 2) } })
        border = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color $Accent); radius = (New-NumLit 8); width = (New-NumLit 1) } })
        dropShadow = @(@{ properties = @{ show = (New-BoolLit $false) } })
        padding = @(@{ properties = @{ top = (New-NumLit 6); bottom = (New-NumLit 6); left = (New-NumLit 8); right = (New-NumLit 8) } })
        visualHeader = @(@{ properties = @{ show = (New-BoolLit $false) } })
    }
    if ($ShowTitle) {
        $vco.title = @(@{ properties = @{
            show = (New-BoolLit $true)
            text = (New-StringLit $Title)
            fontSize = (New-NumLit 11)
            bold = (New-BoolLit $true)
            fontColor = (New-Color '#F8FAFC')
            background = (New-Color '#101B2D')
            alignment = (New-StringLit 'left')
        } })
    }
    return $vco
}

function New-DataVisual {
    param(
        [string]$Name,
        [string]$Type,
        [string]$Title,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [hashtable]$Roles,
        [string]$Accent = '#22D3EE',
        $SortField = $null,
        [ValidateSet('Ascending','Descending')] [string]$SortDirection = 'Ascending',
        $Objects = $null
    )
    $queryState = [ordered]@{}
    foreach ($role in $Roles.Keys) { $queryState[$role] = @{ projections = @($Roles[$role]) } }
    $query = [ordered]@{ queryState = $queryState }
    if ($SortField) { $query.sortDefinition = @{ sort = @(@{ field = $SortField; direction = $SortDirection }); isDefaultSort = $false } }
    $visual = [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = $X; y = $Y; z = 100; height = $Height; width = $Width; tabOrder = 100 }
        visual = [ordered]@{
            visualType = $Type
            query = $query
            visualContainerObjects = (New-PanelVco -Title $Title -Accent $Accent)
            drillFilterOtherVisuals = $true
        }
    }
    if ($Objects) { $visual.visual.objects = $Objects }
    return $visual
}

function New-CardVisual {
    param(
        [string]$Name,
        [string]$Label,
        $Field,
        [string]$QueryRef,
        [string]$NativeRef,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [string]$Accent = '#22D3EE'
    )
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = $X; y = $Y; z = 100; height = 92; width = $Width; tabOrder = 100 }
        visual = [ordered]@{
            visualType = 'cardVisual'
            query = @{ queryState = @{ Data = @{ projections = @((New-Proj $Field $QueryRef $NativeRef $Label)) } } }
            objects = @{
                value = @(@{ properties = @{ fontSize = (New-NumLit 26); bold = (New-BoolLit $true); fontColor = (New-Color '#F8FAFC') }; selector = @{ id = 'default' } })
                label = @(@{ properties = @{ show = (New-BoolLit $true); text = (New-StringLit $Label); fontSize = (New-NumLit 10); fontColor = (New-Color '#A9B8CC') }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLit $false) }; selector = @{ id = 'default' } })
                layout = @(@{ properties = @{ topOuterMargin = (New-Lit '0L'); bottomOuterMargin = (New-Lit '0L'); leftOuterMargin = (New-Lit '0L'); rightOuterMargin = (New-Lit '0L'); paddingUniform = (New-Lit '0L') }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = (New-PanelVco -Title '' -Accent $Accent -ShowTitle $false)
            drillFilterOtherVisuals = $true
        }
    }
}

function New-HeaderShape([string]$Name) {
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = 0; y = 0; z = 0; height = 62; width = 1280; tabOrder = 0 }
        visual = @{
            visualType = 'shape'
            objects = @{
                shape = @(@{ properties = @{ tileShape = (New-StringLit 'rectangle') } })
                fill = @(@{ properties = @{ fillColor = (New-Color '#08111F'); transparency = (New-NumLit 0) }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLit $false) }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLit $false) } })
                border = @(@{ properties = @{ show = (New-BoolLit $false) } })
                padding = @(@{ properties = @{ top = (New-NumLit 0); bottom = (New-NumLit 0); left = (New-NumLit 0); right = (New-NumLit 0) } })
            }
        }
    }
}

function New-HeaderTextbox([string]$Name, [string]$Title, [string]$Subtitle) {
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = 20; y = 5; z = 10; height = 52; width = 1240; tabOrder = 1 }
        visual = @{
            visualType = 'textbox'
            objects = @{
                general = @(@{ properties = @{ paragraphs = @(
                    @{ textRuns = @(@{ value = $Title; textStyle = @{ fontFamily = 'Segoe UI Semibold'; fontSize = '22px'; color = '#F8FAFC' } }); horizontalTextAlignment = 'left' },
                    @{ textRuns = @(@{ value = $Subtitle; textStyle = @{ fontFamily = 'Segoe UI'; fontSize = '10px'; color = '#93A4B8' } }); horizontalTextAlignment = 'left' }
                ) } })
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLit $false) } })
                border = @(@{ properties = @{ show = (New-BoolLit $false) } })
                padding = @(@{ properties = @{ top = (New-NumLit 0); bottom = (New-NumLit 0); left = (New-NumLit 0); right = (New-NumLit 0) } })
            }
        }
    }
}

function New-MatrixObjects([string[]]$DataBarQueryRefs = @()) {
    $columnFormatting = [System.Collections.Generic.List[object]]::new()
    foreach ($queryRef in $DataBarQueryRefs) {
        $columnFormatting.Add(@{
            properties = @{
                dataBars = @{
                    positiveColor = (New-Color '#22D3EE')
                    negativeColor = (New-Color '#EF4444')
                    axisColor = (New-Color '#64748B')
                    reverseDirection = (New-BoolLit $false)
                    hideText = (New-BoolLit $false)
                }
            }
            selector = @{ metadata = $queryRef }
        })
    }
    return @{
        columnHeaders = @(@{ properties = @{
            autoSizeColumnWidth = (New-BoolLit $true)
            columnAdjustment = (New-StringLit 'growToFit')
            fontColor = (New-Color '#F8FAFC')
            backColor = (New-Color '#17243A')
        } })
        rowHeaders = @(@{ properties = @{ fontColor = (New-Color '#E2E8F0'); backColor = (New-Color '#101B2D') } })
        values = @(@{ properties = @{
            fontColorPrimary = (New-Color '#E2E8F0')
            fontColorSecondary = (New-Color '#CBD5E1')
            backColorPrimary = (New-Color '#0D1727')
            backColorSecondary = (New-Color '#111F33')
        } })
        columnFormatting = @($columnFormatting)
    }
}

function Add-ReportPart([System.Collections.Generic.List[object]]$Parts, [string]$Path, [string]$Text) {
    $Parts.Add((New-Part $Path $Text))
    Save-Part -Path $Path -Text $Text
}

function Add-Visual {
    param(
        [System.Collections.Generic.List[object]]$Parts,
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Page,
        $Visual,
        [string]$Dax,
        [string]$Purpose
    )
    $json = $Visual | ConvertTo-Json -Depth 100
    $path = "definition/pages/$Page/visuals/$($Visual.name)/visual.json"
    Add-ReportPart -Parts $Parts -Path $path -Text $json
    $Checks.Add([ordered]@{ page = $Page; visual = $Visual.name; type = $Visual.visual.visualType; purpose = $Purpose; dax = $Dax })
}

if (Test-Path $ReportRoot) { Remove-Item -LiteralPath $ReportRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$parts = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

$theme = [ordered]@{
    name = $ThemeFile
    dataColors = @('#22D3EE','#F59E0B','#EF4444','#14B8A6','#60A5FA','#A78BFA','#F97316','#84CC16','#E879F9','#38BDF8')
    good = '#14B8A6'
    neutral = '#F59E0B'
    bad = '#EF4444'
    maximum = '#EF4444'
    center = '#F59E0B'
    minimum = '#22D3EE'
    null = '#64748B'
    firstLevelElements = '#F8FAFC'
    secondLevelElements = '#A9B8CC'
    thirdLevelElements = '#334155'
    fourthLevelElements = '#64748B'
    background = '#0B1220'
    secondaryBackground = '#101B2D'
    tableAccent = '#22D3EE'
    textClasses = @{
        callout = @{ fontSize = 26; fontFace = 'Segoe UI Semibold'; color = '#F8FAFC' }
        title = @{ fontSize = 12; fontFace = 'Segoe UI Semibold'; color = '#F8FAFC' }
        header = @{ fontSize = 11; fontFace = 'Segoe UI Semibold'; color = '#F8FAFC' }
        label = @{ fontSize = 10; fontFace = 'Segoe UI'; color = '#D5DFEA' }
    }
    visualStyles = @{
        '*' = @{
            '*' = @{
                title = @(@{ show = $true; fontFamily = 'Segoe UI Semibold'; fontSize = 11; fontColor = @{ solid = @{ color = '#F8FAFC' } }; background = @{ solid = @{ color = '#101B2D' } } })
                background = @(@{ show = $true; color = @{ solid = @{ color = '#101B2D' } }; transparency = 2 })
                border = @(@{ show = $true; color = @{ solid = @{ color = '#29405E' } }; radius = 8; width = 1 })
                visualHeader = @(@{ show = $false })
                legend = @(@{ labelColor = @{ solid = @{ color = '#CBD5E1' } }; fontFamily = 'Segoe UI'; fontSize = 9 })
                categoryAxis = @(@{ labelColor = @{ solid = @{ color = '#A9B8CC' } }; titleColor = @{ solid = @{ color = '#CBD5E1' } }; gridlineColor = @{ solid = @{ color = '#26364D' } } })
                valueAxis = @(@{ labelColor = @{ solid = @{ color = '#A9B8CC' } }; titleColor = @{ solid = @{ color = '#CBD5E1' } }; gridlineColor = @{ solid = @{ color = '#26364D' } } })
                outspacePane = @(@{ backgroundColor = @{ solid = @{ color = '#08111F' } }; foregroundColor = @{ solid = @{ color = '#F8FAFC' } }; inputBoxColor = @{ solid = @{ color = '#101B2D' } }; border = $true; borderColor = @{ solid = @{ color = '#29405E' } }; checkboxAndApplyColor = @{ solid = @{ color = '#22D3EE' } } })
                filterCard = @(
                    @{ '$id' = 'Applied'; backgroundColor = @{ solid = @{ color = '#123044' } } },
                    @{ '$id' = 'Available'; backgroundColor = @{ solid = @{ color = '#101B2D' } } }
                )
            }
        }
        cardVisual = @{
            '*' = @{
                value = @(@{ '$id' = 'default'; bold = $true; fontColor = @{ solid = @{ color = '#F8FAFC' } } })
                label = @(@{ '$id' = 'default'; show = $true; fontColor = @{ solid = @{ color = '#A9B8CC' } } })
                title = @(@{ show = $false })
                spacing = @(@{ '$id' = 'default'; verticalSpacing = -4 })
            }
        }
        tableEx = @{
            '*' = @{
                columnHeaders = @(@{ autoSizeColumnWidth = $true; columnAdjustment = 'growToFit'; fontColor = @{ solid = @{ color = '#F8FAFC' } }; backColor = @{ solid = @{ color = '#17243A' } } })
            }
        }
        pivotTable = @{
            '*' = @{
                columnHeaders = @(@{ autoSizeColumnWidth = $true; columnAdjustment = 'growToFit'; fontColor = @{ solid = @{ color = '#F8FAFC' } }; backColor = @{ solid = @{ color = '#17243A' } } })
            }
        }
    }
} | ConvertTo-Json -Depth 100

$pbir = @{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json'
    version = '4.0'
    datasetReference = @{ byConnection = @{ connectionString = "semanticmodelid=$SemanticModelId" } }
} | ConvertTo-Json -Depth 20
$platform = @{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
    metadata = @{ type = 'Report'; displayName = $ReportName }
    config = @{ version = '2.0'; logicalId = $ReportId }
} | ConvertTo-Json -Depth 20
$report = @{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.1.0/schema.json'
    themeCollection = @{
        baseTheme = @{ name = 'CY25SU12'; type = 'SharedResources'; reportVersionAtImport = @{ visual = '2.5.0'; page = '2.3.0'; report = '3.1.0' } }
        customTheme = @{ name = $ThemeFile; type = 'RegisteredResources'; reportVersionAtImport = @{ visual = '2.6.0'; page = '2.3.0'; report = '3.1.0' } }
    }
    resourcePackages = @(@{ name = 'RegisteredResources'; type = 'RegisteredResources'; items = @(@{ name = $ThemeFile; path = $ThemeFile; type = 'CustomTheme' }) })
    settings = @{ useStylableVisualContainerHeader = $true; defaultFilterActionIsDataFilter = $true; useEnhancedTooltips = $true }
} | ConvertTo-Json -Depth 30
$version = @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json'; version = '2.0.0' } | ConvertTo-Json -Depth 10
$pageIds = @('obraz-kraju','hydrologia-fala','infrastruktura-krytyczna','sily-ewakuacja','eskalacja-spo-dezinformacja')
$pages = @{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.0.0/schema.json'; pageOrder = $pageIds; activePageName = $pageIds[0] } | ConvertTo-Json -Depth 10

Add-ReportPart $parts 'definition.pbir' $pbir
Add-ReportPart $parts '.platform' $platform
Add-ReportPart $parts 'definition/report.json' $report
Add-ReportPart $parts 'definition/version.json' $version
Add-ReportPart $parts 'definition/pages/pages.json' $pages
Add-ReportPart $parts "StaticResources/RegisteredResources/$ThemeFile" $theme

$pageInfo = [ordered]@{
    'obraz-kraju' = @('Obraz kraju','Jedno spojrzenie pokazuje skalę kryzysu, jego koncentrację przestrzenną i poziom wymaganej eskalacji.')
    'hydrologia-fala' = @('Hydrologia i fala','Śledź propagację fali Kłodzko → Nysa → Opole → Wrocław oraz przekroczenia progów ostrzegawczych i alarmowych.')
    'infrastruktura-krytyczna' = @('Infrastruktura krytyczna','Powiąż presję hydrologiczną z awariami energii i utratą pokrycia telekomunikacyjnego.')
    'sily-ewakuacja' = @('Siły, środki i ewakuacja','Oceń, czy rozmieszczenie zasobów nadąża za skalą ewakuacji i potrzebami województw.')
    'eskalacja-spo-dezinformacja' = @('Eskalacja, SPO i dezinformacja','Przejdź od sygnału do decyzji: rekomendowany poziom, procedura SPO i ryzyko informacyjne Z20.')
}

foreach ($pageId in $pageIds) {
    $page = @{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.0.0/schema.json'
        name = $pageId
        displayName = $pageInfo[$pageId][0]
        displayOption = 'FitToPage'
        height = 720
        width = 1280
        objects = @{
            background = @(@{ properties = @{ color = (New-Color '#0B1220'); transparency = (New-NumLit 0) } })
            outspace = @(@{ properties = @{ color = (New-Color '#060B14'); transparency = (New-NumLit 0) } })
        }
    } | ConvertTo-Json -Depth 30
    Add-ReportPart $parts "definition/pages/$pageId/page.json" $page
    Add-Visual $parts $checks $pageId (New-HeaderShape "hdr_${pageId}") 'EVALUATE ROW("element", 1)' 'Tło nagłówka strony'
    Add-Visual $parts $checks $pageId (New-HeaderTextbox "ttl_${pageId}" $pageInfo[$pageId][0] $pageInfo[$pageId][1]) 'EVALUATE ROW("element", 1)' 'Tytuł i zdanie decyzyjne'
}

$m = @{
    KIS = New-Meas 'kis_country' 'KIS'
    KISMax = New-Meas 'kis_country' 'KIS Max Lokalny'
    Alarm = New-Meas 'kis_country' 'Alarm Hydro'
    Warning = New-Meas 'kis_country' 'Stan Ostrzegawczy Hydro'
    AlarmPct = New-Meas 'kis_country' '% Gmin w Alarmie'
    Incidents = New-Meas 'kis_country' 'Incydenty'
    Priority = New-Meas 'kis_country' 'Incydenty Priorytet 4 Plus'
    Affected = New-Meas 'kis_country' 'Osoby Dotkniete'
    Evac = New-Meas 'kis_country' 'Liczba Ewakuowanych'
    Power = New-Meas 'kis_country' 'Odbiorcy Bez Prądu'
    TelcoMin = New-Meas 'kis_country' 'Minimalne Pokrycie Telco'
    TelcoLow = New-Meas 'kis_country' 'Gminy Telco Ponizej 50'
    Disinfo = New-Meas 'kis_country' 'Sygnały Dezinformacji'
    Reach = New-Meas 'kis_country' 'Zasieg Dezinformacji'
    PSP = New-Meas 'kis_country' 'PSP Zastepy'
    WOT = New-Meas 'kis_country' 'WOT Zolnierze'
    Pumps = New-Meas 'kis_country' 'Pompy'
    Generators = New-Meas 'kis_country' 'Agregaty'
    Helicopters = New-Meas 'kis_country' 'Smiglowce'
    Response = New-Meas 'kis_country' 'Czas Reakcji Min'
    RZZK = New-Meas 'kis_country' 'Rekomendacje RZZK'
    KisPowiat = New-Meas 'kis_country' 'Gminy KIS Powiat Plus'
    KisWojewoda = New-Meas 'kis_country' 'Gminy KIS Wojewoda Plus'
    KisRZZK = New-Meas 'kis_country' 'Gminy KIS RZZK'
}

$cards4 = @(20,335,650,965)
$cards5 = @(20,270,520,770,1020)

Add-Visual $parts $checks 'obraz-kraju' (New-CardVisual 'p1_kis' 'KIS krajowy' $m.KIS 'kis_country.KIS' 'KIS' $cards4[0] 74 295 '#22D3EE') 'EVALUATE ROW("KIS", [KIS])' 'Krajowy indeks sytuacji'
Add-Visual $parts $checks 'obraz-kraju' (New-CardVisual 'p1_kismax' 'KIS max lokalny' $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' $cards4[1] 74 295 '#EF4444') 'EVALUATE ROW("KIS max", [KIS Max Lokalny])' 'Najgorsza sytuacja lokalna'
Add-Visual $parts $checks 'obraz-kraju' (New-CardVisual 'p1_alarm' 'Wodowskazy w alarmie' $m.Alarm 'kis_country.Alarm Hydro' 'Alarm Hydro' $cards4[2] 74 295 '#F59E0B') 'EVALUATE ROW("Alarm", [Alarm Hydro])' 'Liczba wodowskazów w alarmie'
Add-Visual $parts $checks 'obraz-kraju' (New-CardVisual 'p1_incidents' 'Incydenty' $m.Incidents 'kis_country.Incydenty' 'Incydenty' $cards4[3] 74 295 '#EF4444') 'EVALUATE ROW("Incydenty", [Incydenty])' 'Łączna liczba incydentów'

$p1MapRoles = @{
    Category = @((New-Proj (New-Col 'dim_gmina' 'gmina_name') 'dim_gmina.gmina_name' 'gmina_name' 'Gmina'))
    X = @((New-Proj (New-Agg 'dim_gmina' 'lon' 1) 'Average(dim_gmina.lon)' 'Average of lon' 'Długość geograficzna'))
    Y = @((New-Proj (New-Agg 'dim_gmina' 'lat' 1) 'Average(dim_gmina.lat)' 'Average of lat' 'Szerokość geograficzna'))
    Size = @((New-Proj $m.KIS 'kis_country.KIS' 'KIS' 'KIS'))
    Tooltips = @((New-Proj $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' 'KIS max lokalny'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_map' 'azureMap' 'Mapa ryzyka gmin — wielkość bąbla = KIS' 20 178 720 370 $p1MapRoles '#22D3EE') 'EVALUATE TOPN(2477,FILTER(SUMMARIZECOLUMNS(dim_gmina[gmina_name],dim_gmina[lat],dim_gmina[lon],"KIS",[KIS]),NOT ISBLANK([KIS])),[KIS],DESC)' 'Dominująca mapa sytuacji gmin'

$p1VoivRoles = @{
    Category = @((New-Proj (New-Col 'dim_voivodeship' 'voivodeship_name') 'dim_voivodeship.voivodeship_name' 'voivodeship_name' 'Województwo'))
    Y = @((New-Proj $m.KIS 'kis_country.KIS' 'KIS' 'KIS'),(New-Proj $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' 'KIS max'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_voiv' 'clusteredBarChart' 'Województwa — średni i maksymalny KIS' 755 178 505 240 $p1VoivRoles '#F59E0B' $m.KISMax 'Descending') 'EVALUATE SUMMARIZECOLUMNS(dim_voivodeship[voivodeship_name],"KIS",[KIS],"KIS max",[KIS Max Lokalny])' 'Ranking województw'

$p1AreaRoles = @{
    Category = @((New-Proj (New-Col 'incident_reports' 'timestamp') 'incident_reports.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj $m.Incidents 'kis_country.Incydenty' 'Incydenty' 'Incydenty'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_inc_area' 'areaChart' 'Narastanie incydentów w osi scenariusza' 20 560 720 140 $p1AreaRoles '#60A5FA' (New-Col 'incident_reports' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(incident_reports[timestamp],"Incydenty",[Incydenty]),incident_reports[timestamp],ASC)' 'Trend incydentów'

$p1LevelRoles = @{
    Category = @((New-Proj (New-Col 'escalation_recommendations' 'recommended_level') 'escalation_recommendations.recommended_level' 'recommended_level' 'Rekomendowany poziom'))
    Y = @((New-Proj (New-Agg 'escalation_recommendations' 'gmina_code' 2) 'Count(escalation_recommendations.gmina_code)' 'Count of gmina_code' 'Gminy'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_levels' 'columnChart' 'Skala rekomendowanej eskalacji' 755 430 505 270 $p1LevelRoles '#EF4444' (New-Agg 'escalation_recommendations' 'gmina_code' 2) 'Descending') 'EVALUATE SUMMARIZECOLUMNS(escalation_recommendations[recommended_level],"Gminy",COUNTROWS(escalation_recommendations))' 'Rozkład poziomów eskalacji'

Add-Visual $parts $checks 'hydrologia-fala' (New-CardVisual 'p2_alarm' 'Alarm hydro' $m.Alarm 'kis_country.Alarm Hydro' 'Alarm Hydro' $cards4[0] 74 295 '#EF4444') 'EVALUATE ROW("Alarm", [Alarm Hydro])' 'Wodowskazy powyżej alarmu'
Add-Visual $parts $checks 'hydrologia-fala' (New-CardVisual 'p2_warning' 'Stan ostrzegawczy' $m.Warning 'kis_country.Stan Ostrzegawczy Hydro' 'Stan Ostrzegawczy Hydro' $cards4[1] 74 295 '#F59E0B') 'EVALUATE ROW("Ostrzegawcze", [Stan Ostrzegawczy Hydro])' 'Wodowskazy w stanie ostrzegawczym'
Add-Visual $parts $checks 'hydrologia-fala' (New-CardVisual 'p2_alarm_pct' 'Gminy w alarmie' $m.AlarmPct 'kis_country.% Gmin w Alarmie' '% Gmin w Alarmie' $cards4[2] 74 295 '#F59E0B') 'EVALUATE ROW("Procent", [% Gmin w Alarmie])' 'Udział gmin objętych alarmem'
Add-Visual $parts $checks 'hydrologia-fala' (New-CardVisual 'p2_affected' 'Osoby dotknięte' $m.Affected 'kis_country.Osoby Dotkniete' 'Osoby Dotkniete' $cards4[3] 74 295 '#EF4444') 'EVALUATE ROW("Osoby", [Osoby Dotkniete])' 'Skutek społeczny zdarzeń'

$p2MapRoles = @{
    Category = @((New-Proj (New-Col 'dim_river_gauge' 'gauge_name') 'dim_river_gauge.gauge_name' 'gauge_name' 'Wodowskaz'))
    Series = @((New-Proj (New-Col 'dim_river_gauge' 'river') 'dim_river_gauge.river' 'river' 'Rzeka'))
    X = @((New-Proj (New-Agg 'dim_river_gauge' 'lon' 1) 'Average(dim_river_gauge.lon)' 'Average of lon' 'Długość geograficzna'))
    Y = @((New-Proj (New-Agg 'dim_river_gauge' 'lat' 1) 'Average(dim_river_gauge.lat)' 'Average of lat' 'Szerokość geograficzna'))
    Size = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Średni poziom [cm]'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_map' 'azureMap' 'Wodowskazy — położenie i skala poziomu wody' 20 178 560 350 $p2MapRoles '#22D3EE') 'EVALUATE FILTER(SUMMARIZECOLUMNS(dim_river_gauge[gauge_name],dim_river_gauge[river],dim_river_gauge[lat],dim_river_gauge[lon],"Poziom",AVERAGE(hydro_readings[level_cm])),NOT ISBLANK([Poziom]))' 'Mapa wodowskazów'

$p2SmallRoles = @{
    Category = @((New-Proj (New-Col 'hydro_readings' 'timestamp') 'hydro_readings.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Poziom [cm]'))
    Rows = @((New-Proj (New-Col 'hydro_readings' 'river') 'hydro_readings.river' 'river' 'Rzeka'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_wave' 'lineChart' 'Fala w czasie — małe multiplikatory wg rzeki' 595 178 665 350 $p2SmallRoles '#60A5FA' (New-Col 'hydro_readings' 'timestamp') 'Ascending') 'EVALUATE TOPN(1500,SUMMARIZECOLUMNS(hydro_readings[river],hydro_readings[timestamp],"Poziom",AVERAGE(hydro_readings[level_cm])),hydro_readings[timestamp],ASC)' 'Propagacja fali w małych multiplikatorach'

$p2ComboRoles = @{
    Category = @((New-Proj (New-Col 'hydro_readings' 'timestamp') 'hydro_readings.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'hydro_readings' 'flow_m3s' 1) 'Average(hydro_readings.flow_m3s)' 'Average of flow_m3s' 'Przepływ [m³/s]'))
    Y2 = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Poziom [cm]'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_combo' 'lineClusteredColumnComboChart' 'Przepływ i poziom — kolumna + linia' 20 540 700 160 $p2ComboRoles '#F59E0B' (New-Col 'hydro_readings' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(hydro_readings[timestamp],"Przepływ",AVERAGE(hydro_readings[flow_m3s]),"Poziom",AVERAGE(hydro_readings[level_cm])),hydro_readings[timestamp],ASC)' 'Wykres kombi hydro'

$p2MatrixRoles = @{
    Rows = @((New-Proj (New-Col 'dim_river_gauge' 'gauge_name') 'dim_river_gauge.gauge_name' 'gauge_name' 'Wodowskaz'))
    Values = @(
        (New-Proj (New-Agg 'hydro_readings' 'level_cm' 4) 'Max(hydro_readings.level_cm)' 'Max of level_cm' 'Maks. poziom [cm]'),
        (New-Proj (New-Agg 'hydro_readings' 'warning_level_cm' 4) 'Max(hydro_readings.warning_level_cm)' 'Max of warning_level_cm' 'Próg ostrzegawczy [cm]'),
        (New-Proj (New-Agg 'hydro_readings' 'alarm_level_cm' 4) 'Max(hydro_readings.alarm_level_cm)' 'Max of alarm_level_cm' 'Próg alarmowy [cm]')
    )
}
$p2MatrixObjects = New-MatrixObjects @('Max(hydro_readings.level_cm)')
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_matrix' 'pivotTable' 'Wodowskazy i progi — pasek = maksymalny poziom' 735 540 525 160 $p2MatrixRoles '#EF4444' $null 'Ascending' $p2MatrixObjects) 'EVALUATE SUMMARIZECOLUMNS(dim_river_gauge[gauge_name],"Poziom max",MAX(hydro_readings[level_cm]),"Ostrzegawczy",MAX(hydro_readings[warning_level_cm]),"Alarmowy",MAX(hydro_readings[alarm_level_cm]))' 'Macierz progów hydrologicznych'

Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-CardVisual 'p3_power' 'Odbiorcy bez prądu' $m.Power 'kis_country.Odbiorcy Bez Prądu' 'Odbiorcy Bez Prądu' $cards4[0] 74 295 '#EF4444') 'EVALUATE ROW("Bez prądu", [Odbiorcy Bez Prądu])' 'Łączna skala awarii energii'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-CardVisual 'p3_telco_min' 'Min. pokrycie telco' $m.TelcoMin 'kis_country.Minimalne Pokrycie Telco' 'Minimalne Pokrycie Telco' $cards4[1] 74 295 '#F59E0B') 'EVALUATE ROW("Pokrycie", [Minimalne Pokrycie Telco])' 'Najniższy poziom pokrycia'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-CardVisual 'p3_telco_low' 'Gminy telco < 50%' $m.TelcoLow 'kis_country.Gminy Telco Ponizej 50' 'Gminy Telco Ponizej 50' $cards4[2] 74 295 '#F59E0B') 'EVALUATE ROW("Gminy", [Gminy Telco Ponizej 50])' 'Gminy z krytycznym pokryciem'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-CardVisual 'p3_priority' 'Incydenty priorytet 4+' $m.Priority 'kis_country.Incydenty Priorytet 4 Plus' 'Incydenty Priorytet 4 Plus' $cards4[3] 74 295 '#EF4444') 'EVALUATE ROW("Priorytet", [Incydenty Priorytet 4 Plus])' 'Najpoważniejsze incydenty'

$p3ScatterRoles = @{
    Details = @((New-Proj (New-Col 'escalation_recommendations' 'gmina_code') 'escalation_recommendations.gmina_code' 'gmina_code' 'Gmina'))
    X = @((New-Proj (New-Agg 'escalation_recommendations' 'hydro_score' 1) 'Average(escalation_recommendations.hydro_score)' 'Average of hydro_score' 'Presja hydro'))
    Y = @((New-Proj (New-Agg 'escalation_recommendations' 'power_score' 1) 'Average(escalation_recommendations.power_score)' 'Average of power_score' 'Skutek energetyczny'))
    Size = @((New-Proj (New-Agg 'escalation_recommendations' 'telecom_score' 1) 'Average(escalation_recommendations.telecom_score)' 'Average of telecom_score' 'Skutek telco'))
    Tooltips = @((New-Proj (New-Agg 'escalation_recommendations' 'kis' 1) 'Average(escalation_recommendations.kis)' 'Average of kis' 'KIS'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_scatter' 'scatterChart' 'Kaskada hydro → energia → telco (bąbel = skutek telco)' 20 178 720 350 $p3ScatterRoles '#EF4444') 'EVALUATE TOPN(2477,SUMMARIZECOLUMNS(escalation_recommendations[gmina_code],"Hydro",AVERAGE(escalation_recommendations[hydro_score]),"Energia",AVERAGE(escalation_recommendations[power_score]),"Telco",AVERAGE(escalation_recommendations[telecom_score]),"KIS",AVERAGE(escalation_recommendations[kis])),[KIS],DESC)' 'Korelacja skutków infrastrukturalnych'

$p3PowerRoles = @{
    Category = @((New-Proj (New-Col 'power_grid_events' 'timestamp') 'power_grid_events.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'power_grid_events' 'customers_offline' 0) 'Sum(power_grid_events.customers_offline)' 'Sum of customers_offline' 'Odbiorcy bez prądu'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_power_time' 'areaChart' 'Energia — odbiorcy bez zasilania w czasie' 755 178 505 245 $p3PowerRoles '#EF4444' (New-Col 'power_grid_events' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(power_grid_events[timestamp],"Odbiorcy",SUM(power_grid_events[customers_offline])),power_grid_events[timestamp],ASC)' 'Trend awarii energetycznych'

$p3TelcoRoles = @{
    Category = @((New-Proj (New-Col 'telecom_events' 'timestamp') 'telecom_events.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'telecom_events' 'coverage_pct' 1) 'Average(telecom_events.coverage_pct)' 'Average of coverage_pct' 'Pokrycie [%]'))
    Rows = @((New-Proj (New-Col 'telecom_events' 'operator') 'telecom_events.operator' 'operator' 'Operator'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_telco_time' 'lineChart' 'Łączność — pokrycie wg operatora (małe multiplikatory)' 755 435 505 265 $p3TelcoRoles '#22D3EE' (New-Col 'telecom_events' 'timestamp') 'Ascending') 'EVALUATE TOPN(1200,SUMMARIZECOLUMNS(telecom_events[operator],telecom_events[timestamp],"Pokrycie",AVERAGE(telecom_events[coverage_pct])),telecom_events[timestamp],ASC)' 'Trend pokrycia operatorów'

$p3MatrixRoles = @{
    Rows = @((New-Proj (New-Col 'escalation_recommendations' 'gmina_code') 'escalation_recommendations.gmina_code' 'gmina_code' 'Gmina'))
    Values = @(
        (New-Proj (New-Agg 'escalation_recommendations' 'hydro_score' 1) 'Average(escalation_recommendations.hydro_score)' 'Average of hydro_score' 'Hydro'),
        (New-Proj (New-Agg 'escalation_recommendations' 'power_score' 1) 'Average(escalation_recommendations.power_score)' 'Average of power_score' 'Energia'),
        (New-Proj (New-Agg 'escalation_recommendations' 'telecom_score' 1) 'Average(escalation_recommendations.telecom_score)' 'Average of telecom_score' 'Telco'),
        (New-Proj (New-Agg 'escalation_recommendations' 'kis' 1) 'Average(escalation_recommendations.kis)' 'Average of kis' 'KIS')
    )
}
$p3MatrixObjects = New-MatrixObjects @('Average(escalation_recommendations.hydro_score)','Average(escalation_recommendations.power_score)','Average(escalation_recommendations.telecom_score)','Average(escalation_recommendations.kis)')
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_matrix' 'pivotTable' 'Gminy — porównanie składowych kaskady' 20 540 720 160 $p3MatrixRoles '#F59E0B' $null 'Ascending' $p3MatrixObjects) 'EVALUATE TOPN(100,SUMMARIZECOLUMNS(escalation_recommendations[gmina_code],"Hydro",AVERAGE(escalation_recommendations[hydro_score]),"Energia",AVERAGE(escalation_recommendations[power_score]),"Telco",AVERAGE(escalation_recommendations[telecom_score]),"KIS",AVERAGE(escalation_recommendations[kis])),[KIS],DESC)' 'Macierz kaskady z paskami danych'

Add-Visual $parts $checks 'sily-ewakuacja' (New-CardVisual 'p4_evac' 'Osoby ewakuowane' $m.Evac 'kis_country.Liczba Ewakuowanych' 'Liczba Ewakuowanych' $cards5[0] 74 235 '#EF4444') 'EVALUATE ROW("Ewakuowani", [Liczba Ewakuowanych])' 'Skala ewakuacji'
Add-Visual $parts $checks 'sily-ewakuacja' (New-CardVisual 'p4_psp' 'Zastępy PSP' $m.PSP 'kis_country.PSP Zastepy' 'PSP Zastepy' $cards5[1] 74 235 '#F59E0B') 'EVALUATE ROW("PSP", [PSP Zastepy])' 'Zaangażowanie PSP'
Add-Visual $parts $checks 'sily-ewakuacja' (New-CardVisual 'p4_wot' 'Żołnierze WOT' $m.WOT 'kis_country.WOT Zolnierze' 'WOT Zolnierze' $cards5[2] 74 235 '#22D3EE') 'EVALUATE ROW("WOT", [WOT Zolnierze])' 'Zaangażowanie WOT'
Add-Visual $parts $checks 'sily-ewakuacja' (New-CardVisual 'p4_pumps' 'Pompy' $m.Pumps 'kis_country.Pompy' 'Pompy' $cards5[3] 74 235 '#60A5FA') 'EVALUATE ROW("Pompy", [Pompy])' 'Dostępne pompy'
Add-Visual $parts $checks 'sily-ewakuacja' (New-CardVisual 'p4_generators' 'Agregaty' $m.Generators 'kis_country.Agregaty' 'Agregaty' $cards5[4] 74 240 '#A78BFA') 'EVALUATE ROW("Agregaty", [Agregaty])' 'Dostępne agregaty'

$p4StackRoles = @{
    Category = @((New-Proj (New-Col 'resource_deployment' 'voivodeship_code') 'resource_deployment.voivodeship_code' 'voivodeship_code' 'Województwo'))
    Y = @(
        (New-Proj (New-Agg 'resource_deployment' 'psp_units' 0) 'Sum(resource_deployment.psp_units)' 'Sum of psp_units' 'PSP'),
        (New-Proj (New-Agg 'resource_deployment' 'wot_soldiers' 0) 'Sum(resource_deployment.wot_soldiers)' 'Sum of wot_soldiers' 'WOT'),
        (New-Proj (New-Agg 'resource_deployment' 'pumps' 0) 'Sum(resource_deployment.pumps)' 'Sum of pumps' 'Pompy'),
        (New-Proj (New-Agg 'resource_deployment' 'generators' 0) 'Sum(resource_deployment.generators)' 'Sum of generators' 'Agregaty')
    )
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_resources' 'barChart' 'Siły i środki wg województw — słupki skumulowane' 20 178 620 330 $p4StackRoles '#22D3EE') 'EVALUATE SUMMARIZECOLUMNS(resource_deployment[voivodeship_code],"PSP",SUM(resource_deployment[psp_units]),"WOT",SUM(resource_deployment[wot_soldiers]),"Pompy",SUM(resource_deployment[pumps]),"Agregaty",SUM(resource_deployment[generators]))' 'Skumulowany obraz zasobów'

$p4EvacRoles = @{
    Category = @((New-Proj (New-Col 'evacuation_status' 'timestamp') 'evacuation_status.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'evacuation_status' 'people_count' 0) 'Sum(evacuation_status.people_count)' 'Sum of people_count' 'Osoby'))
    Series = @((New-Proj (New-Col 'evacuation_status' 'status') 'evacuation_status.status' 'status' 'Status'))
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_evac_area' 'stackedAreaChart' 'Ewakuacja — narastanie wg statusu' 655 178 605 240 $p4EvacRoles '#EF4444' (New-Col 'evacuation_status' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(evacuation_status[status],evacuation_status[timestamp],"Osoby",SUM(evacuation_status[people_count])),evacuation_status[timestamp],ASC)' 'Narastanie ewakuacji'

$p4ComboRoles = @{
    Category = @((New-Proj (New-Col 'resource_deployment' 'timestamp') 'resource_deployment.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'resource_deployment' 'psp_units' 0) 'Sum(resource_deployment.psp_units)' 'Sum of psp_units' 'Zastępy PSP'))
    Y2 = @((New-Proj (New-Agg 'resource_deployment' 'wot_soldiers' 0) 'Sum(resource_deployment.wot_soldiers)' 'Sum of wot_soldiers' 'Żołnierze WOT'))
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_combo' 'lineClusteredColumnComboChart' 'Napływ zasobów — PSP (kolumny) i WOT (linia)' 655 430 605 270 $p4ComboRoles '#F59E0B' (New-Col 'resource_deployment' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(resource_deployment[timestamp],"PSP",SUM(resource_deployment[psp_units]),"WOT",SUM(resource_deployment[wot_soldiers])),resource_deployment[timestamp],ASC)' 'Tempo mobilizacji zasobów'

$p4MatrixRoles = @{
    Rows = @((New-Proj (New-Col 'resource_deployment' 'voivodeship_code') 'resource_deployment.voivodeship_code' 'voivodeship_code' 'Województwo'))
    Values = @(
        (New-Proj (New-Agg 'resource_deployment' 'psp_units' 0) 'Sum(resource_deployment.psp_units)' 'Sum of psp_units' 'PSP'),
        (New-Proj (New-Agg 'resource_deployment' 'wot_soldiers' 0) 'Sum(resource_deployment.wot_soldiers)' 'Sum of wot_soldiers' 'WOT'),
        (New-Proj (New-Agg 'resource_deployment' 'pumps' 0) 'Sum(resource_deployment.pumps)' 'Sum of pumps' 'Pompy'),
        (New-Proj (New-Agg 'resource_deployment' 'generators' 0) 'Sum(resource_deployment.generators)' 'Sum of generators' 'Agregaty'),
        (New-Proj (New-Agg 'resource_deployment' 'helicopters' 0) 'Sum(resource_deployment.helicopters)' 'Sum of helicopters' 'Śmigłowce')
    )
}
$p4MatrixObjects = New-MatrixObjects @('Sum(resource_deployment.psp_units)','Sum(resource_deployment.wot_soldiers)','Sum(resource_deployment.pumps)','Sum(resource_deployment.generators)')
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_matrix' 'pivotTable' 'Bilans zasobów — dokładne wartości i paski danych' 20 520 620 180 $p4MatrixRoles '#60A5FA' $null 'Ascending' $p4MatrixObjects) 'EVALUATE SUMMARIZECOLUMNS(resource_deployment[voivodeship_code],"PSP",SUM(resource_deployment[psp_units]),"WOT",SUM(resource_deployment[wot_soldiers]),"Pompy",SUM(resource_deployment[pumps]),"Agregaty",SUM(resource_deployment[generators]),"Śmigłowce",SUM(resource_deployment[helicopters]))' 'Macierz bilansu zasobów'

Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-CardVisual 'p5_rzzk' 'Rekomendacje RZZK' $m.RZZK 'kis_country.Rekomendacje RZZK' 'Rekomendacje RZZK' $cards5[0] 74 235 '#EF4444') 'EVALUATE ROW("RZZK", [Rekomendacje RZZK])' 'Rekomendacje najwyższego poziomu'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-CardVisual 'p5_kis_rzzk' 'Gminy KIS ≥ 85' $m.KisRZZK 'kis_country.Gminy KIS RZZK' 'Gminy KIS RZZK' $cards5[1] 74 235 '#EF4444') 'EVALUATE ROW("Gminy", [Gminy KIS RZZK])' 'Gminy wymagające RZZK'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-CardVisual 'p5_disinfo' 'Sygnały Z20' $m.Disinfo 'kis_country.Sygnały Dezinformacji' 'Sygnały Dezinformacji' $cards5[2] 74 235 '#F59E0B') 'EVALUATE ROW("Sygnały", [Sygnały Dezinformacji])' 'Liczba sygnałów dezinformacyjnych'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-CardVisual 'p5_reach' 'Zasięg Z20' $m.Reach 'kis_country.Zasieg Dezinformacji' 'Zasieg Dezinformacji' $cards5[3] 74 235 '#A78BFA') 'EVALUATE ROW("Zasięg", [Zasieg Dezinformacji])' 'Łączny zasięg dezinformacji'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-CardVisual 'p5_response' 'Czas reakcji [min]' $m.Response 'kis_country.Czas Reakcji Min' 'Czas Reakcji Min' $cards5[4] 74 240 '#22D3EE') 'EVALUATE ROW("Minuty", [Czas Reakcji Min])' 'Czas od pierwszego zgłoszenia do eskalacji'

$p5AreaRoles = @{
    Category = @((New-Proj (New-Col 'media_signals' 'timestamp') 'media_signals.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj $m.Reach 'kis_country.Zasieg Dezinformacji' 'Zasieg Dezinformacji' 'Zasięg Z20'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_reach_area' 'areaChart' 'Zasięg dezinformacji w czasie' 20 178 720 250 $p5AreaRoles '#A78BFA' (New-Col 'media_signals' 'timestamp') 'Ascending') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(media_signals[timestamp],"Zasięg",[Zasieg Dezinformacji]),media_signals[timestamp],ASC)' 'Trend zasięgu Z20'

$p5DonutRoles = @{
    Category = @((New-Proj (New-Col 'media_signals' 'channel') 'media_signals.channel' 'channel' 'Kanał'))
    Y = @((New-Proj $m.Disinfo 'kis_country.Sygnały Dezinformacji' 'Sygnały Dezinformacji' 'Sygnały Z20'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_donut' 'donutChart' 'Kanały dezinformacji' 755 178 250 250 $p5DonutRoles '#F59E0B') 'EVALUATE FILTER(SUMMARIZECOLUMNS(media_signals[channel],"Sygnały",[Sygnały Dezinformacji]),[Sygnały]>0)' 'Jedyny wykres pierścieniowy — kanały Z20'

$p5EscRoles = @{
    Category = @((New-Proj (New-Col 'escalation_events' 'to_level') 'escalation_events.to_level' 'to_level' 'Poziom docelowy'))
    Y = @((New-Proj (New-Agg 'escalation_events' 'event_id' 2) 'Count(escalation_events.event_id)' 'Count of event_id' 'Eskalacje'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_escalations' 'columnChart' 'Eskalacje wg poziomu' 1020 178 240 250 $p5EscRoles '#EF4444') 'EVALUATE SUMMARIZECOLUMNS(escalation_events[to_level],"Eskalacje",COUNTROWS(escalation_events))' 'Rozkład zdarzeń eskalacyjnych'

$p5SpoRoles = @{
    Category = @((New-Proj (New-Col 'escalation_recommendations' 'recommended_spo') 'escalation_recommendations.recommended_spo' 'recommended_spo' 'SPO'))
    Y = @((New-Proj (New-Agg 'escalation_recommendations' 'gmina_code' 2) 'Count(escalation_recommendations.gmina_code)' 'Count of gmina_code' 'Rekomendacje'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_spo' 'clusteredBarChart' 'Procedury SPO na stole RZZK' 20 440 500 260 $p5SpoRoles '#F59E0B' (New-Agg 'escalation_recommendations' 'gmina_code' 2) 'Descending') 'EVALUATE SUMMARIZECOLUMNS(escalation_recommendations[recommended_spo],"Rekomendacje",COUNTROWS(escalation_recommendations))' 'Ranking rekomendowanych SPO'

$p5MatrixRoles = @{
    Rows = @(
        (New-Proj (New-Col 'escalation_recommendations' 'recommended_level') 'escalation_recommendations.recommended_level' 'recommended_level' 'Poziom'),
        (New-Proj (New-Col 'escalation_recommendations' 'gmina_code') 'escalation_recommendations.gmina_code' 'gmina_code' 'Gmina')
    )
    Values = @(
        (New-Proj (New-Agg 'escalation_recommendations' 'kis' 1) 'Average(escalation_recommendations.kis)' 'Average of kis' 'KIS'),
        (New-Proj (New-Col 'escalation_recommendations' 'recommended_spo') 'escalation_recommendations.recommended_spo' 'recommended_spo' 'SPO'),
        (New-Proj (New-Col 'escalation_recommendations' 'explanation') 'escalation_recommendations.explanation' 'explanation' 'Uzasadnienie')
    )
}
$p5MatrixObjects = New-MatrixObjects @('Average(escalation_recommendations.kis)')
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_matrix' 'pivotTable' 'Rekomendacje — poziom, SPO i uzasadnienie' 535 440 725 260 $p5MatrixRoles '#EF4444' $null 'Ascending' $p5MatrixObjects) 'EVALUATE TOPN(100,SUMMARIZECOLUMNS(escalation_recommendations[recommended_level],escalation_recommendations[gmina_code],escalation_recommendations[recommended_spo],escalation_recommendations[explanation],"KIS",AVERAGE(escalation_recommendations[kis])),[KIS],DESC)' 'Macierz decyzji i uzasadnień'

$definition = @{ format = 'PBIR'; parts = @($parts) }
$manifestPath = Join-Path $ReportRoot 'validation\visual-dax.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath) | Out-Null
$checks | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if ($GenerateOnly) {
    [pscustomobject]@{ ReportPages = $pageIds.Count; ReportVisuals = $checks.Count; DefinitionParts = $parts.Count; ReportRoot = $ReportRoot } | ConvertTo-Json
    return
}

$fabricToken = Get-AccessToken 'https://api.fabric.microsoft.com'
$fabricHeaders = New-AuthHeaders $fabricToken
$updateBody = @{ definition = $definition }
$update = Invoke-RestJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$ReportId/updateDefinition?updateMetadata=True" -Headers $fabricHeaders -Body $updateBody
$null = Wait-FabricOperation -Response $update -Headers $fabricHeaders
Write-Host "Raport $ReportName zaktualizowany: $ReportId"

Start-Sleep -Seconds 8
$pbiToken = Get-AccessToken 'https://analysis.windows.net/powerbi/api'
$pbiHeaders = New-AuthHeaders $pbiToken
$queryUri = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$SemanticModelId/executeQueries"

function Invoke-Dax([string]$Query) {
    $body = @{ queries = @(@{ query = $Query }); serializerSettings = @{ includeNulls = $true } }
    $response = Invoke-RestJson -Method POST -Uri $queryUri -Headers $pbiHeaders -Body $body
    return $response.Content | ConvertFrom-Json
}

$validationResults = [System.Collections.Generic.List[object]]::new()
foreach ($check in $checks) {
    try {
        $result = Invoke-Dax $check.dax
        $rows = @($result.results[0].tables[0].rows)
        if ($rows.Count -eq 0) { throw 'Zapytanie nie zwróciło wierszy.' }
        $validationResults.Add([ordered]@{ page = $check.page; visual = $check.visual; type = $check.type; purpose = $check.purpose; status = 'OK'; rows = $rows.Count })
        Write-Host "[OK] $($check.page)/$($check.visual) [$($check.type)] rows=$($rows.Count)"
    }
    catch {
        $validationResults.Add([ordered]@{ page = $check.page; visual = $check.visual; type = $check.type; purpose = $check.purpose; status = 'FAIL'; rows = 0; error = $_.Exception.Message })
        Write-Warning "[FAIL] $($check.page)/$($check.visual): $($_.Exception.Message)"
    }
}

$sanityQuery = @'
EVALUATE ROW(
 "KIS", [KIS],
 "KIS Max Lokalny", [KIS Max Lokalny],
 "Liczba Ewakuowanych", [Liczba Ewakuowanych],
 "% Gmin w Alarmie", [% Gmin w Alarmie],
 "Odbiorcy Bez Prądu", [Odbiorcy Bez Prądu],
 "Minimalne Pokrycie Telco", [Minimalne Pokrycie Telco],
 "Gminy Telco Ponizej 50", [Gminy Telco Ponizej 50],
 "Incydenty", [Incydenty],
 "Incydenty Priorytet 4 Plus", [Incydenty Priorytet 4 Plus],
 "Osoby Dotkniete", [Osoby Dotkniete],
 "Sygnały Dezinformacji", [Sygnały Dezinformacji],
 "Zasieg Dezinformacji", [Zasieg Dezinformacji],
 "PSP Zastepy", [PSP Zastepy],
 "WOT Zolnierze", [WOT Zolnierze],
 "Pompy", [Pompy],
 "Agregaty", [Agregaty],
 "Smiglowce", [Smiglowce],
 "Czas Reakcji Min", [Czas Reakcji Min],
 "Rekomendacje RZZK", [Rekomendacje RZZK],
 "Gminy KIS Powiat Plus", [Gminy KIS Powiat Plus],
 "Gminy KIS Wojewoda Plus", [Gminy KIS Wojewoda Plus],
 "Gminy KIS RZZK", [Gminy KIS RZZK],
 "Alarm Hydro", [Alarm Hydro],
 "Stan Ostrzegawczy Hydro", [Stan Ostrzegawczy Hydro]
)
'@
$expected = [ordered]@{
    'KIS' = 5.27
    'KIS Max Lokalny' = 100
    'Liczba Ewakuowanych' = 160871
    '% Gmin w Alarmie' = 0.0040
    'Odbiorcy Bez Prądu' = 1375406
    'Minimalne Pokrycie Telco' = 0.226
    'Gminy Telco Ponizej 50' = 80
    'Incydenty' = 4943
    'Incydenty Priorytet 4 Plus' = 818
    'Osoby Dotkniete' = 263001
    'Sygnały Dezinformacji' = 363
    'Zasieg Dezinformacji' = 39854793
    'PSP Zastepy' = 11366
    'WOT Zolnierze' = 62024
    'Pompy' = 7041
    'Agregaty' = 4426
    'Smiglowce' = 103
    'Czas Reakcji Min' = 3839
    'Rekomendacje RZZK' = 47
    'Gminy KIS Powiat Plus' = 54
    'Gminy KIS Wojewoda Plus' = 47
    'Gminy KIS RZZK' = 47
    'Alarm Hydro' = 10
    'Stan Ostrzegawczy Hydro' = 43
}
$sanity = Invoke-Dax $sanityQuery
$sanityRow = $sanity.results[0].tables[0].rows[0]
$sanityResults = [System.Collections.Generic.List[object]]::new()
foreach ($name in $expected.Keys) {
    $actual = $sanityRow.PSObject.Properties["[$name]"].Value
    $tolerance = if ($name -eq 'KIS') { 0.01 } elseif ($name -in @('% Gmin w Alarmie','Minimalne Pokrycie Telco')) { 0.0005 } else { 0.01 }
    $ok = [Math]::Abs([double]$actual - [double]$expected[$name]) -le $tolerance
    $sanityResults.Add([ordered]@{ measure = $name; expected = $expected[$name]; actual = $actual; status = $(if ($ok) { 'OK' } else { 'FAIL' }) })
}

$definitionResponse = Invoke-RestJson -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$ReportId/getDefinition?format=PBIR" -Headers $fabricHeaders -Body @{}
$deployed = Wait-FabricOperation -Response $definitionResponse -Headers $fabricHeaders
$deployedParts = @($deployed.definition.parts)
$deployedPages = @($deployedParts | Where-Object { $_.path -match '^definition/pages/.+/page\.json$' }).Count
$deployedVisuals = @($deployedParts | Where-Object { $_.path -match '^definition/pages/.+/visuals/.+/visual\.json$' }).Count

$validationSummary = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    reportId = $ReportId
    semanticModelId = $SemanticModelId
    pagesExpected = $pageIds.Count
    pagesDeployed = $deployedPages
    visualsExpected = $checks.Count
    visualsDeployed = $deployedVisuals
    daxPassed = @($validationResults | Where-Object status -eq 'OK').Count
    daxTotal = $validationResults.Count
    sanityPassed = @($sanityResults | Where-Object status -eq 'OK').Count
    sanityTotal = $sanityResults.Count
    visualResults = @($validationResults)
    sanityResults = @($sanityResults)
}
$validationSummary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportRoot 'validation\results.json') -Encoding utf8

$failures = @($validationResults | Where-Object status -ne 'OK')
$sanityFailures = @($sanityResults | Where-Object status -ne 'OK')
if ($failures.Count -gt 0) { throw "Walidacja DAX nie powiodła się dla $($failures.Count) z $($validationResults.Count) wizualizacji." }
if ($sanityFailures.Count -gt 0) { throw "Sanity-check miar nie powiódł się dla $($sanityFailures.Count) z $($sanityResults.Count) miar." }
if ($deployedPages -ne $pageIds.Count -or $deployedVisuals -ne $checks.Count) {
    throw "Wdrożona definicja ma $deployedPages stron i $deployedVisuals wizualizacji; oczekiwano $($pageIds.Count) i $($checks.Count)."
}

[pscustomobject]@{
    ReportId = $ReportId
    ReportPages = $deployedPages
    ReportVisuals = $deployedVisuals
    DaxPassed = @($validationResults | Where-Object status -eq 'OK').Count
    DaxTotal = $validationResults.Count
    SanityPassed = @($sanityResults | Where-Object status -eq 'OK').Count
    SanityTotal = $sanityResults.Count
    LocalReportDefinition = $ReportRoot
} | ConvertTo-Json -Depth 10
