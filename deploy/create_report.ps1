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
$ThemeFile = 'COP24-Rzadowy-c0242026.json'

# Paleta urzedowa: jasne tlo, granat jako kolor instytucji, akcenty tylko tam gdzie niosa znaczenie.
$NAVY   = '#12325B'
$INK    = '#1B2A41'
$MUTED  = '#5C6B80'
$LINE   = '#D8DFE8'
$PANEL  = '#FFFFFF'
$PAGE   = '#EEF2F7'
$RED    = '#B3261E'; $RED_T   = '#FBECEA'
$AMBER  = '#B26B00'; $AMBER_T = '#FDF4E5'
$BLUE   = '#1B4A8B'; $BLUE_T  = '#EAF0FA'
$TEAL   = '#0F6E6E'; $TEAL_T  = '#E6F2F2'
$VIOLET = '#5B4B8A'; $VIOLET_T= '#EFEDF7'
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

function New-PanelVco([string]$Title, [string]$Accent = $BLUE, [bool]$ShowTitle = $true, [string]$Subtitle = '') {
    $vco = [ordered]@{
        background = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color $PANEL); transparency = (New-NumLit 0) } })
        border = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color $LINE); radius = (New-NumLit 4); width = (New-NumLit 1) } })
        dropShadow = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color '#8A99AD'); position = (New-StringLit 'Outer'); preset = (New-StringLit 'BottomRight'); transparency = (New-NumLit 88) } })
        padding = @(@{ properties = @{ top = (New-NumLit 12); bottom = (New-NumLit 12); left = (New-NumLit 14); right = (New-NumLit 14) } })
        visualHeader = @(@{ properties = @{ show = (New-BoolLit $false) } })
    }
    if ($ShowTitle) {
        $vco.title = @(@{ properties = @{
            show = (New-BoolLit $true)
            text = (New-StringLit $Title)
            fontSize = (New-NumLit 12)
            bold = (New-BoolLit $true)
            fontColor = (New-Color $NAVY)
            background = (New-Color $PANEL)
            alignment = (New-StringLit 'left')
        } })
        $vco.subTitle = @(@{ properties = @{
            show = (New-BoolLit ([bool]$Subtitle))
            text = (New-StringLit $(if ($Subtitle) { $Subtitle } else { ' ' }))
            fontSize = (New-NumLit 9)
            italic = (New-BoolLit $false)
            fontColor = (New-Color $MUTED)
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
        [string]$Accent = $BLUE,
        $SortField = $null,
        [ValidateSet('Ascending','Descending')] [string]$SortDirection = 'Ascending',
        $Objects = $null,
        [string]$Subtitle = ''
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
            visualContainerObjects = (New-PanelVco -Title $Title -Accent $Accent -Subtitle $Subtitle)
            drillFilterOtherVisuals = $true
        }
    }
    if ($Objects) { $visual.visual.objects = $Objects }
    return $visual
}

function New-KpiVisual {
    param(
        [string]$Name,
        [string]$Label,
        $Field,
        [string]$QueryRef,
        [string]$NativeRef,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [string]$Accent = $BLUE,
        [string]$Tint = $BLUE_T
    )
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = $X; y = $Y; z = 100; height = 92; width = $Width; tabOrder = 100 }
        visual = [ordered]@{
            visualType = 'cardVisual'
            query = @{ queryState = @{ Data = @{ projections = @((New-Proj $Field $QueryRef $NativeRef $Label)) } } }
            objects = @{
                value = @(@{ properties = @{ fontSize = (New-NumLit 30); bold = (New-BoolLit $true); fontFamily = (New-StringLit 'Segoe UI Semibold'); fontColor = (New-Color $Accent) }; selector = @{ id = 'default' } })
                label = @(@{ properties = @{ show = (New-BoolLit $true); text = (New-StringLit $Label.ToUpperInvariant()); fontSize = (New-NumLit 9); bold = (New-BoolLit $true); fontFamily = (New-StringLit 'Segoe UI'); fontColor = (New-Color $MUTED) }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLit $false) }; selector = @{ id = 'default' } })
                layout = @(@{ properties = @{ topOuterMargin = (New-Lit '4L'); bottomOuterMargin = (New-Lit '4L'); leftOuterMargin = (New-Lit '2L'); rightOuterMargin = (New-Lit '2L'); paddingUniform = (New-Lit '0L') }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = [ordered]@{
                background = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color $Tint); transparency = (New-NumLit 0) } })
                border = @(@{ properties = @{ show = (New-BoolLit $true); color = (New-Color $Accent); radius = (New-NumLit 4); width = (New-NumLit 1) } })
                dropShadow = @(@{ properties = @{ show = (New-BoolLit $false) } })
                padding = @(@{ properties = @{ top = (New-NumLit 10); bottom = (New-NumLit 10); left = (New-NumLit 16); right = (New-NumLit 16) } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLit $false) } })
            }
            drillFilterOtherVisuals = $true
        }
    }
}

function New-TextVisual {
    param(
        [string]$Name,
        [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z,
        [array]$Paragraphs
    )
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = $X; y = $Y; z = $Z; height = $Height; width = $Width; tabOrder = $Z }
        visual = @{
            visualType = 'textbox'
            objects = @{ general = @(@{ properties = @{ paragraphs = $Paragraphs } }) }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLit $false) } })
                border = @(@{ properties = @{ show = (New-BoolLit $false) } })
                dropShadow = @(@{ properties = @{ show = (New-BoolLit $false) } })
                padding = @(@{ properties = @{ top = (New-NumLit 0); bottom = (New-NumLit 0); left = (New-NumLit 0); right = (New-NumLit 0) } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLit $false) } })
            }
        }
    }
}

function New-Para([string]$Text, [string]$Font, [string]$Size, [string]$Color, [string]$Align = 'left', [bool]$Spacing = $false) {
    $run = @{ value = $Text; textStyle = [ordered]@{ fontFamily = $Font; fontSize = $Size; color = $Color } }
    if ($Spacing) { $run.textStyle.letterSpacing = '1.6px' }
    return @{ textRuns = @($run); horizontalTextAlignment = $Align }
}

function New-HeaderShape([string]$Name) {
    return [ordered]@{
        '$schema' = $VisualSchema
        name = $Name
        position = @{ x = 0; y = 0; z = 0; height = 88; width = 1280; tabOrder = 0 }
        visual = @{
            visualType = 'shape'
            objects = @{
                shape = @(@{ properties = @{ tileShape = (New-StringLit 'rectangle') } })
                fill = @(@{ properties = @{ fillColor = (New-Color $NAVY); transparency = (New-NumLit 0) }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLit $false) }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLit $false) } })
                border = @(@{ properties = @{ show = (New-BoolLit $false) } })
                dropShadow = @(@{ properties = @{ show = (New-BoolLit $false) } })
                padding = @(@{ properties = @{ top = (New-NumLit 0); bottom = (New-NumLit 0); left = (New-NumLit 0); right = (New-NumLit 0) } })
            }
        }
    }
}

function New-HeaderTextbox([string]$Name, [string]$Kicker, [string]$Title, [string]$Lead) {
    $paragraphs = @(
        (New-Para $Kicker 'Segoe UI Semibold' '9px' '#8FB0DC' 'left' $true),
        (New-Para $Title 'Segoe UI Light' '26px' '#FFFFFF'),
        (New-Para $Lead 'Segoe UI' '11px' '#C4D4EA')
    )
    return New-TextVisual -Name $Name -X 32 -Y 8 -Width 900 -Height 76 -Z 10 -Paragraphs $paragraphs
}

function New-BrandTextbox([string]$Name, [string]$Step) {
    $paragraphs = @(
        (New-Para 'COP-24  ·  KRAJOWY OBRAZ SYTUACJI' 'Segoe UI Semibold' '10px' '#FFFFFF' 'right' $true),
        (New-Para 'Rządowe Centrum Bezpieczeństwa  ·  ćwiczenie sztabowe' 'Segoe UI' '9px' '#9FBBDE' 'right'),
        (New-Para $Step 'Segoe UI Semibold' '9px' '#8FB0DC' 'right' $true)
    )
    return New-TextVisual -Name $Name -X 948 -Y 16 -Width 300 -Height 62 -Z 11 -Paragraphs $paragraphs
}

function New-FooterTextbox([string]$Name, [string]$Text) {
    $paragraphs = @((New-Para $Text 'Segoe UI' '9px' '#7A8899'))
    return New-TextVisual -Name $Name -X 32 -Y 688 -Width 1216 -Height 24 -Z 5 -Paragraphs $paragraphs
}

function New-MatrixObjects([string[]]$DataBarQueryRefs = @()) {
    $columnFormatting = [System.Collections.Generic.List[object]]::new()
    foreach ($queryRef in $DataBarQueryRefs) {
        $columnFormatting.Add(@{
            properties = @{
                dataBars = @{
                    positiveColor = (New-Color $BLUE)
                    negativeColor = (New-Color $RED)
                    axisColor = (New-Color $LINE)
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
            fontColor = (New-Color '#FFFFFF')
            backColor = (New-Color $NAVY)
            bold = (New-BoolLit $true)
            fontSize = (New-NumLit 10)
        } })
        rowHeaders = @(@{ properties = @{ fontColor = (New-Color $INK); backColor = (New-Color $PANEL); fontSize = (New-NumLit 10) } })
        values = @(@{ properties = @{
            fontColorPrimary = (New-Color $INK)
            fontColorSecondary = (New-Color $INK)
            backColorPrimary = (New-Color $PANEL)
            backColorSecondary = (New-Color '#F5F8FC')
            fontSize = (New-NumLit 10)
        } })
        grid = @(@{ properties = @{ gridVertical = (New-BoolLit $false); gridHorizontalColor = (New-Color $LINE); rowPadding = (New-NumLit 4) } })
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
    dataColors = @($BLUE,$RED,$AMBER,$TEAL,'#2F6FB0',$VIOLET,'#8C5A2B','#4C7A34','#9C3D6E','#3A7FA8')
    good = $TEAL
    neutral = $AMBER
    bad = $RED
    maximum = $RED
    center = $AMBER
    minimum = $BLUE
    null = '#9AA7B8'
    firstLevelElements = $INK
    secondLevelElements = $MUTED
    thirdLevelElements = $LINE
    fourthLevelElements = '#94A3B8'
    background = $PANEL
    secondaryBackground = $PAGE
    tableAccent = $NAVY
    textClasses = @{
        callout = @{ fontSize = 30; fontFace = 'Segoe UI Semibold'; color = $NAVY }
        title = @{ fontSize = 12; fontFace = 'Segoe UI Semibold'; color = $NAVY }
        header = @{ fontSize = 11; fontFace = 'Segoe UI Semibold'; color = $NAVY }
        label = @{ fontSize = 10; fontFace = 'Segoe UI'; color = $MUTED }
    }
    visualStyles = @{
        '*' = @{
            '*' = @{
                title = @(@{ show = $true; fontFamily = 'Segoe UI Semibold'; fontSize = 12; fontColor = @{ solid = @{ color = $NAVY } }; background = @{ solid = @{ color = $PANEL } }; titleWrap = $false })
                subTitle = @(@{ show = $true; fontFamily = 'Segoe UI'; fontSize = 9; fontColor = @{ solid = @{ color = $MUTED } } })
                background = @(@{ show = $true; color = @{ solid = @{ color = $PANEL } }; transparency = 0 })
                border = @(@{ show = $true; color = @{ solid = @{ color = $LINE } }; radius = 4; width = 1 })
                dropShadow = @(@{ show = $true; color = @{ solid = @{ color = '#8A99AD' } }; position = 'Outer'; preset = 'BottomRight'; transparency = 88 })
                visualHeader = @(@{ show = $false })
                legend = @(@{ show = $true; position = 'TopCenter'; labelColor = @{ solid = @{ color = $MUTED } }; fontFamily = 'Segoe UI'; fontSize = 9; showTitle = $false })
                categoryAxis = @(@{ labelColor = @{ solid = @{ color = $MUTED } }; fontSize = 9; titleColor = @{ solid = @{ color = $MUTED } }; showAxisTitle = $false; gridlineShow = $false; lineColor = @{ solid = @{ color = $LINE } } })
                valueAxis = @(@{ labelColor = @{ solid = @{ color = $MUTED } }; fontSize = 9; titleColor = @{ solid = @{ color = $MUTED } }; showAxisTitle = $false; gridlineColor = @{ solid = @{ color = '#E7ECF3' } }; gridlineStyle = 'solid'; gridlineThickness = 1 })
                labels = @(@{ show = $false; color = @{ solid = @{ color = $INK } }; fontSize = 9; fontFamily = 'Segoe UI' })
                outspacePane = @(@{ backgroundColor = @{ solid = @{ color = $PAGE } }; foregroundColor = @{ solid = @{ color = $INK } }; inputBoxColor = @{ solid = @{ color = $PANEL } }; border = $true; borderColor = @{ solid = @{ color = $LINE } }; checkboxAndApplyColor = @{ solid = @{ color = $NAVY } } })
                filterCard = @(
                    @{ '$id' = 'Applied'; backgroundColor = @{ solid = @{ color = $BLUE_T } } },
                    @{ '$id' = 'Available'; backgroundColor = @{ solid = @{ color = $PANEL } } }
                )
            }
        }
        cardVisual = @{
            '*' = @{
                value = @(@{ '$id' = 'default'; bold = $true; fontFamily = 'Segoe UI Semibold'; fontColor = @{ solid = @{ color = $NAVY } } })
                label = @(@{ '$id' = 'default'; show = $true; fontColor = @{ solid = @{ color = $MUTED } } })
                title = @(@{ show = $false })
                subTitle = @(@{ show = $false })
                dropShadow = @(@{ show = $false })
                spacing = @(@{ '$id' = 'default'; verticalSpacing = 2 })
            }
        }
        lineChart = @{
            '*' = @{
                lineStyles = @(@{ strokeWidth = 3; lineStyle = 'solid'; showMarker = $false })
            }
        }
        areaChart = @{
            '*' = @{
                lineStyles = @(@{ strokeWidth = 2; transparency = 60 })
            }
        }
        pivotTable = @{
            '*' = @{
                columnHeaders = @(@{ autoSizeColumnWidth = $true; columnAdjustment = 'growToFit'; bold = $true; fontColor = @{ solid = @{ color = '#FFFFFF' } }; backColor = @{ solid = @{ color = $NAVY } } })
                grid = @(@{ gridVertical = $false; gridHorizontalColor = @{ solid = @{ color = $LINE } }; rowPadding = 4 })
            }
        }
        tableEx = @{
            '*' = @{
                columnHeaders = @(@{ autoSizeColumnWidth = $true; columnAdjustment = 'growToFit'; bold = $true; fontColor = @{ solid = @{ color = '#FFFFFF' } }; backColor = @{ solid = @{ color = $NAVY } } })
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
    'obraz-kraju' = @(
        'Obraz kraju',
        'KROK 1 z 5  ·  CO SIĘ DZIEJE',
        'Jedno spojrzenie: skala kryzysu, jego koncentracja przestrzenna i tempo narastania.',
        'Źródło: Eventhouse OL_COP24 → Lakehouse → model Direct Lake  ·  Scenariusz powodziowy 12–25.09.2026  ·  Krok 1 z 5')
    'hydrologia-fala' = @(
        'Hydrologia i fala',
        'KROK 2 z 5  ·  SKĄD NADCHODZI',
        'Fala przemieszcza się Kłodzko → Nysa → Opole → Wrocław. Progi ostrzegawcze i alarmowe wskazują wyprzedzenie czasowe.',
        'Źródło: IMGW (dane symulowane), 148 wodowskazów  ·  Krok 2 z 5')
    'infrastruktura-krytyczna' = @(
        'Infrastruktura krytyczna',
        'KROK 3 z 5  ·  CO SIĘ SYPIE',
        'Presja hydrologiczna przenosi się na energetykę i łączność — to tam powstaje ryzyko wtórne.',
        'Źródło: operatorzy OSD i telekomunikacyjni (dane symulowane)  ·  Krok 3 z 5')
    'sily-ewakuacja' = @(
        'Siły, środki i ewakuacja',
        'KROK 4 z 5  ·  CZY NADĄŻAMY',
        'Zestawienie tempa ewakuacji z tempem mobilizacji zasobów pokazuje, gdzie powstaje luka.',
        'Źródło: PSP, WOT, zasoby wojewódzkie (dane symulowane)  ·  Krok 4 z 5')
    'eskalacja-spo-dezinformacja' = @(
        'Decyzja: eskalacja i SPO',
        'KROK 5 z 5  ·  CO ROBIMY',
        'Od sygnału do decyzji: rekomendowany poziom zarządzania, procedura SPO i ryzyko informacyjne Z20.',
        'Rekomendacje generowane regułowo na podstawie KIS; wymagają zatwierdzenia RZZK  ·  Krok 5 z 5')
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
            background = @(@{ properties = @{ color = (New-Color $PAGE); transparency = (New-NumLit 0) } })
            outspace = @(@{ properties = @{ color = (New-Color '#DDE4EC'); transparency = (New-NumLit 0) } })
        }
    } | ConvertTo-Json -Depth 30
    Add-ReportPart $parts "definition/pages/$pageId/page.json" $page
    Add-Visual $parts $checks $pageId (New-HeaderShape "hdr_${pageId}") 'EVALUATE ROW("element", 1)' 'Pasek nagłówka strony'
    Add-Visual $parts $checks $pageId (New-HeaderTextbox "ttl_${pageId}" $pageInfo[$pageId][1] $pageInfo[$pageId][0] $pageInfo[$pageId][2]) 'EVALUATE ROW("element", 1)' 'Tytuł, krok narracji i zdanie decyzyjne'
    Add-Visual $parts $checks $pageId (New-BrandTextbox "brd_${pageId}" $pageInfo[$pageId][1]) 'EVALUATE ROW("element", 1)' 'Sygnatura instytucjonalna i numer kroku'
    Add-Visual $parts $checks $pageId (New-FooterTextbox "ftr_${pageId}" $pageInfo[$pageId][3]) 'EVALUATE ROW("element", 1)' 'Stopka ze źródłem danych'
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

# Siatka: margines 32 px, cztery karty KPI w rzedzie, dwa panele glowne, jeden pas dolny.
# Mniej elementow na stronie niz w poprzedniej wersji - kazdy panel niesie jedna teze.
$kpiX = @(32, 342, 652, 962)
$kpiW = 286
$kpiY = 104
$mainY = 220
$mainH = 296
$leftX = 32;  $leftW = 748
$rightX = 804; $rightW = 444
$bandY = 540
$bandH = 140
$bandW = 1216

# ---------------------------------------------------------------- STRONA 1
Add-Visual $parts $checks 'obraz-kraju' (New-KpiVisual 'p1_kis' 'KIS krajowy' $m.KIS 'kis_country.KIS' 'KIS' $kpiX[0] $kpiY $kpiW $BLUE $BLUE_T) 'EVALUATE ROW("KIS", [KIS])' 'Krajowy indeks sytuacji'
Add-Visual $parts $checks 'obraz-kraju' (New-KpiVisual 'p1_kismax' 'Najwyższy KIS lokalny' $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' $kpiX[1] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("KIS max", [KIS Max Lokalny])' 'Najgorsza sytuacja lokalna'
Add-Visual $parts $checks 'obraz-kraju' (New-KpiVisual 'p1_affected' 'Osoby dotknięte' $m.Affected 'kis_country.Osoby Dotkniete' 'Osoby Dotkniete' $kpiX[2] $kpiY $kpiW $AMBER $AMBER_T) 'EVALUATE ROW("Osoby", [Osoby Dotkniete])' 'Skutek społeczny zdarzeń'
Add-Visual $parts $checks 'obraz-kraju' (New-KpiVisual 'p1_incidents' 'Zgłoszone incydenty' $m.Incidents 'kis_country.Incydenty' 'Incydenty' $kpiX[3] $kpiY $kpiW $TEAL $TEAL_T) 'EVALUATE ROW("Incydenty", [Incydenty])' 'Łączna liczba incydentów'

$p1MapRoles = @{
    # Wspolrzedne musza byc liczbami i miec agregacje - dopiero wtedy Azure Maps
    # przyjmuje je razem z rola Lokalizacji. Wczesniej lat/lon byly w modelu tekstem.
    Category = @((New-Proj (New-Col 'dim_gmina' 'gmina_name') 'dim_gmina.gmina_name' 'gmina_name' 'Gmina'))
    X = @((New-Proj (New-Agg 'dim_gmina' 'lon' 1) 'Average(dim_gmina.lon)' 'Average of lon' 'Długość geograficzna'))
    Y = @((New-Proj (New-Agg 'dim_gmina' 'lat' 1) 'Average(dim_gmina.lat)' 'Average of lat' 'Szerokość geograficzna'))
    Size = @((New-Proj $m.KIS 'kis_country.KIS' 'KIS' 'KIS'))
    Tooltips = @((New-Proj $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' 'KIS max lokalny'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_map' 'azureMap' 'Gdzie jest ciężar kryzysu' $leftX $mainY $leftW $mainH $p1MapRoles $BLUE $null 'Ascending' $null 'Wielkość bąbla odpowiada indeksowi KIS gminy — zagrożenie koncentruje się w dorzeczu górnej Odry') 'EVALUATE TOPN(2477,FILTER(SUMMARIZECOLUMNS(dim_gmina[gmina_name],dim_gmina[lat],dim_gmina[lon],"KIS",[KIS]),NOT ISBLANK([KIS])),[KIS],DESC)' 'Dominująca mapa sytuacji gmin'

$p1VoivRoles = @{
    Category = @((New-Proj (New-Col 'dim_voivodeship' 'voivodeship_name') 'dim_voivodeship.voivodeship_name' 'voivodeship_name' 'Województwo'))
    Y = @((New-Proj $m.KIS 'kis_country.KIS' 'KIS' 'KIS średni'),(New-Proj $m.KISMax 'kis_country.KIS Max Lokalny' 'KIS Max Lokalny' 'KIS maksymalny'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_voiv' 'clusteredBarChart' 'Które województwa wymagają uwagi' $rightX $mainY $rightW $mainH $p1VoivRoles $AMBER $m.KISMax 'Descending' $null 'Rozjazd między średnią a maksimum wskazuje kryzys punktowy, nie rozlany') 'EVALUATE SUMMARIZECOLUMNS(dim_voivodeship[voivodeship_name],"KIS",[KIS],"KIS max",[KIS Max Lokalny])' 'Ranking województw'

$p1AreaRoles = @{
    Category = @((New-Proj (New-Col 'incident_reports' 'timestamp') 'incident_reports.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj $m.Incidents 'kis_country.Incydenty' 'Incydenty' 'Incydenty'))
}
Add-Visual $parts $checks 'obraz-kraju' (New-DataVisual 'p1_inc_area' 'areaChart' 'Tempo narastania zdarzeń' $leftX $bandY $bandW $bandH $p1AreaRoles $BLUE (New-Col 'incident_reports' 'timestamp') 'Ascending' $null 'Punkt przegięcia krzywej wyznacza moment, w którym reagowanie lokalne przestaje wystarczać') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(incident_reports[timestamp],"Incydenty",[Incydenty]),incident_reports[timestamp],ASC)' 'Trend incydentów'

# ---------------------------------------------------------------- STRONA 2
Add-Visual $parts $checks 'hydrologia-fala' (New-KpiVisual 'p2_alarm' 'Wodowskazy w alarmie' $m.Alarm 'kis_country.Alarm Hydro' 'Alarm Hydro' $kpiX[0] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("Alarm", [Alarm Hydro])' 'Wodowskazy powyżej alarmu'
Add-Visual $parts $checks 'hydrologia-fala' (New-KpiVisual 'p2_warning' 'Stan ostrzegawczy' $m.Warning 'kis_country.Stan Ostrzegawczy Hydro' 'Stan Ostrzegawczy Hydro' $kpiX[1] $kpiY $kpiW $AMBER $AMBER_T) 'EVALUATE ROW("Ostrzegawcze", [Stan Ostrzegawczy Hydro])' 'Wodowskazy w stanie ostrzegawczym'
Add-Visual $parts $checks 'hydrologia-fala' (New-KpiVisual 'p2_alarm_pct' 'Udział gmin w alarmie' $m.AlarmPct 'kis_country.% Gmin w Alarmie' '% Gmin w Alarmie' $kpiX[2] $kpiY $kpiW $BLUE $BLUE_T) 'EVALUATE ROW("Procent", [% Gmin w Alarmie])' 'Udział gmin objętych alarmem'
Add-Visual $parts $checks 'hydrologia-fala' (New-KpiVisual 'p2_affected' 'Osoby dotknięte' $m.Affected 'kis_country.Osoby Dotkniete' 'Osoby Dotkniete' $kpiX[3] $kpiY $kpiW $VIOLET $VIOLET_T) 'EVALUATE ROW("Osoby", [Osoby Dotkniete])' 'Skutek społeczny zdarzeń'

$p2MapRoles = @{
    Category = @((New-Proj (New-Col 'dim_river_gauge' 'gauge_name') 'dim_river_gauge.gauge_name' 'gauge_name' 'Wodowskaz'))
    Series = @((New-Proj (New-Col 'dim_river_gauge' 'river') 'dim_river_gauge.river' 'river' 'Rzeka'))
    X = @((New-Proj (New-Agg 'dim_river_gauge' 'lon' 1) 'Average(dim_river_gauge.lon)' 'Average of lon' 'Długość geograficzna'))
    Y = @((New-Proj (New-Agg 'dim_river_gauge' 'lat' 1) 'Average(dim_river_gauge.lat)' 'Average of lat' 'Szerokość geograficzna'))
    Size = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Średni poziom [cm]'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_map' 'azureMap' 'Sieć wodowskazów i obciążenie rzek' $leftX $mainY $leftW $mainH $p2MapRoles $BLUE $null 'Ascending' $null 'Kolor oznacza rzekę, wielkość — średni poziom wody; ciąg bąbli pokazuje kierunek fali') 'EVALUATE FILTER(SUMMARIZECOLUMNS(dim_river_gauge[gauge_name],dim_river_gauge[river],dim_river_gauge[lat],dim_river_gauge[lon],"Poziom",AVERAGE(hydro_readings[level_cm])),NOT ISBLANK([Poziom]))' 'Mapa wodowskazów'

$p2SmallRoles = @{
    Category = @((New-Proj (New-Col 'hydro_readings' 'timestamp') 'hydro_readings.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Poziom [cm]'))
    Rows = @((New-Proj (New-Col 'hydro_readings' 'river') 'hydro_readings.river' 'river' 'Rzeka'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_wave' 'lineChart' 'Propagacja fali w czasie' $rightX $mainY $rightW $mainH $p2SmallRoles $RED (New-Col 'hydro_readings' 'timestamp') 'Ascending' $null 'Przesunięcie szczytów między rzekami to realne wyprzedzenie decyzyjne — kilkanaście godzin') 'EVALUATE TOPN(1500,SUMMARIZECOLUMNS(hydro_readings[river],hydro_readings[timestamp],"Poziom",AVERAGE(hydro_readings[level_cm])),hydro_readings[timestamp],ASC)' 'Propagacja fali w małych multiplikatorach'

$p2ComboRoles = @{
    Category = @((New-Proj (New-Col 'hydro_readings' 'timestamp') 'hydro_readings.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'hydro_readings' 'flow_m3s' 1) 'Average(hydro_readings.flow_m3s)' 'Average of flow_m3s' 'Przepływ [m³/s]'))
    Y2 = @((New-Proj (New-Agg 'hydro_readings' 'level_cm' 1) 'Average(hydro_readings.level_cm)' 'Average of level_cm' 'Poziom [cm]'))
}
Add-Visual $parts $checks 'hydrologia-fala' (New-DataVisual 'p2_combo' 'lineClusteredColumnComboChart' 'Przepływ kontra poziom wody' $leftX $bandY $bandW $bandH $p2ComboRoles $AMBER (New-Col 'hydro_readings' 'timestamp') 'Ascending' $null 'Przepływ rośnie przed poziomem — to najwcześniejszy sygnał ostrzegawczy w całym zestawie danych') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(hydro_readings[timestamp],"Przepływ",AVERAGE(hydro_readings[flow_m3s]),"Poziom",AVERAGE(hydro_readings[level_cm])),hydro_readings[timestamp],ASC)' 'Wykres kombi hydro'

# ---------------------------------------------------------------- STRONA 3
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-KpiVisual 'p3_power' 'Odbiorcy bez prądu' $m.Power 'kis_country.Odbiorcy Bez Prądu' 'Odbiorcy Bez Prądu' $kpiX[0] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("Bez prądu", [Odbiorcy Bez Prądu])' 'Łączna skala awarii energii'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-KpiVisual 'p3_telco_min' 'Najniższe pokrycie telco' $m.TelcoMin 'kis_country.Minimalne Pokrycie Telco' 'Minimalne Pokrycie Telco' $kpiX[1] $kpiY $kpiW $AMBER $AMBER_T) 'EVALUATE ROW("Pokrycie", [Minimalne Pokrycie Telco])' 'Najniższy poziom pokrycia'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-KpiVisual 'p3_telco_low' 'Gminy z pokryciem < 50%' $m.TelcoLow 'kis_country.Gminy Telco Ponizej 50' 'Gminy Telco Ponizej 50' $kpiX[2] $kpiY $kpiW $VIOLET $VIOLET_T) 'EVALUATE ROW("Gminy", [Gminy Telco Ponizej 50])' 'Gminy z krytycznym pokryciem'
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-KpiVisual 'p3_priority' 'Incydenty priorytet 4+' $m.Priority 'kis_country.Incydenty Priorytet 4 Plus' 'Incydenty Priorytet 4 Plus' $kpiX[3] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("Priorytet", [Incydenty Priorytet 4 Plus])' 'Najpoważniejsze incydenty'

$p3ScatterRoles = @{
    Details = @((New-Proj (New-Col 'escalation_recommendations' 'gmina_code') 'escalation_recommendations.gmina_code' 'gmina_code' 'Gmina'))
    X = @((New-Proj (New-Agg 'escalation_recommendations' 'hydro_score' 1) 'Average(escalation_recommendations.hydro_score)' 'Average of hydro_score' 'Presja hydrologiczna'))
    Y = @((New-Proj (New-Agg 'escalation_recommendations' 'power_score' 1) 'Average(escalation_recommendations.power_score)' 'Average of power_score' 'Skutek energetyczny'))
    Size = @((New-Proj (New-Agg 'escalation_recommendations' 'telecom_score' 1) 'Average(escalation_recommendations.telecom_score)' 'Average of telecom_score' 'Skutek telekomunikacyjny'))
    Tooltips = @((New-Proj (New-Agg 'escalation_recommendations' 'kis' 1) 'Average(escalation_recommendations.kis)' 'Average of kis' 'KIS'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_scatter' 'scatterChart' 'Kaskada skutków: woda → prąd → łączność' $leftX $mainY $leftW $mainH $p3ScatterRoles $RED $null 'Ascending' $null 'Gminy w prawym górnym rogu tracą jednocześnie zasilanie i łączność — tam ratownik działa bez wsparcia systemów') 'EVALUATE TOPN(2477,SUMMARIZECOLUMNS(escalation_recommendations[gmina_code],"Hydro",AVERAGE(escalation_recommendations[hydro_score]),"Energia",AVERAGE(escalation_recommendations[power_score]),"Telco",AVERAGE(escalation_recommendations[telecom_score]),"KIS",AVERAGE(escalation_recommendations[kis])),[KIS],DESC)' 'Korelacja skutków infrastrukturalnych'

$p3PowerRoles = @{
    Category = @((New-Proj (New-Col 'power_grid_events' 'timestamp') 'power_grid_events.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'power_grid_events' 'customers_offline' 0) 'Sum(power_grid_events.customers_offline)' 'Sum of customers_offline' 'Odbiorcy bez prądu'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_power_time' 'areaChart' 'Skala wyłączeń energetycznych' $rightX $mainY $rightW $mainH $p3PowerRoles $AMBER (New-Col 'power_grid_events' 'timestamp') 'Ascending' $null 'Szczyt wyłączeń wypada kilka godzin po kulminacji fali — to okno na dowóz agregatów') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(power_grid_events[timestamp],"Odbiorcy",SUM(power_grid_events[customers_offline])),power_grid_events[timestamp],ASC)' 'Trend awarii energetycznych'

$p3TelcoRoles = @{
    Category = @((New-Proj (New-Col 'telecom_events' 'timestamp') 'telecom_events.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'telecom_events' 'coverage_pct' 1) 'Average(telecom_events.coverage_pct)' 'Average of coverage_pct' 'Pokrycie [%]'))
    Rows = @((New-Proj (New-Col 'telecom_events' 'operator') 'telecom_events.operator' 'operator' 'Operator'))
}
Add-Visual $parts $checks 'infrastruktura-krytyczna' (New-DataVisual 'p3_telco_time' 'lineChart' 'Łączność w rękach czterech operatorów' $leftX $bandY $bandW $bandH $p3TelcoRoles $BLUE (New-Col 'telecom_events' 'timestamp') 'Ascending' $null 'Spadki są skorelowane — awaria zasilania uderza we wszystkich operatorów naraz, redundancja komercyjna zawodzi') 'EVALUATE TOPN(1200,SUMMARIZECOLUMNS(telecom_events[operator],telecom_events[timestamp],"Pokrycie",AVERAGE(telecom_events[coverage_pct])),telecom_events[timestamp],ASC)' 'Trend pokrycia operatorów'

# ---------------------------------------------------------------- STRONA 4
Add-Visual $parts $checks 'sily-ewakuacja' (New-KpiVisual 'p4_evac' 'Osoby ewakuowane' $m.Evac 'kis_country.Liczba Ewakuowanych' 'Liczba Ewakuowanych' $kpiX[0] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("Ewakuowani", [Liczba Ewakuowanych])' 'Skala ewakuacji'
Add-Visual $parts $checks 'sily-ewakuacja' (New-KpiVisual 'p4_psp' 'Zastępy PSP w akcji' $m.PSP 'kis_country.PSP Zastepy' 'PSP Zastepy' $kpiX[1] $kpiY $kpiW $BLUE $BLUE_T) 'EVALUATE ROW("PSP", [PSP Zastepy])' 'Zaangażowanie PSP'
Add-Visual $parts $checks 'sily-ewakuacja' (New-KpiVisual 'p4_wot' 'Żołnierze WOT' $m.WOT 'kis_country.WOT Zolnierze' 'WOT Zolnierze' $kpiX[2] $kpiY $kpiW $TEAL $TEAL_T) 'EVALUATE ROW("WOT", [WOT Zolnierze])' 'Zaangażowanie WOT'
Add-Visual $parts $checks 'sily-ewakuacja' (New-KpiVisual 'p4_generators' 'Agregaty prądotwórcze' $m.Generators 'kis_country.Agregaty' 'Agregaty' $kpiX[3] $kpiY $kpiW $VIOLET $VIOLET_T) 'EVALUATE ROW("Agregaty", [Agregaty])' 'Dostępne agregaty'

$p4StackRoles = @{
    Category = @((New-Proj (New-Col 'resource_deployment' 'voivodeship_code') 'resource_deployment.voivodeship_code' 'voivodeship_code' 'Województwo'))
    Y = @(
        (New-Proj (New-Agg 'resource_deployment' 'psp_units' 0) 'Sum(resource_deployment.psp_units)' 'Sum of psp_units' 'PSP'),
        (New-Proj (New-Agg 'resource_deployment' 'wot_soldiers' 0) 'Sum(resource_deployment.wot_soldiers)' 'Sum of wot_soldiers' 'WOT'),
        (New-Proj (New-Agg 'resource_deployment' 'pumps' 0) 'Sum(resource_deployment.pumps)' 'Sum of pumps' 'Pompy'),
        (New-Proj (New-Agg 'resource_deployment' 'generators' 0) 'Sum(resource_deployment.generators)' 'Sum of generators' 'Agregaty')
    )
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_resources' 'barChart' 'Rozmieszczenie sił i środków' $leftX $mainY $leftW $mainH $p4StackRoles $BLUE $null 'Ascending' $null 'Zestawienie z mapą z kroku 1 pokazuje, czy zasoby stoją tam, gdzie rośnie KIS') 'EVALUATE SUMMARIZECOLUMNS(resource_deployment[voivodeship_code],"PSP",SUM(resource_deployment[psp_units]),"WOT",SUM(resource_deployment[wot_soldiers]),"Pompy",SUM(resource_deployment[pumps]),"Agregaty",SUM(resource_deployment[generators]))' 'Skumulowany obraz zasobów'

$p4EvacRoles = @{
    Category = @((New-Proj (New-Col 'evacuation_status' 'timestamp') 'evacuation_status.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'evacuation_status' 'people_count' 0) 'Sum(evacuation_status.people_count)' 'Sum of people_count' 'Osoby'))
    Series = @((New-Proj (New-Col 'evacuation_status' 'status') 'evacuation_status.status' 'status' 'Status'))
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_evac_area' 'stackedAreaChart' 'Przebieg ewakuacji według statusu' $rightX $mainY $rightW $mainH $p4EvacRoles $RED (New-Col 'evacuation_status' 'timestamp') 'Ascending' $null 'Rosnąca warstwa „w toku” oznacza wąskie gardło transportu lub miejsc w punktach zbiórki') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(evacuation_status[status],evacuation_status[timestamp],"Osoby",SUM(evacuation_status[people_count])),evacuation_status[timestamp],ASC)' 'Narastanie ewakuacji'

$p4ComboRoles = @{
    Category = @((New-Proj (New-Col 'resource_deployment' 'timestamp') 'resource_deployment.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj (New-Agg 'resource_deployment' 'psp_units' 0) 'Sum(resource_deployment.psp_units)' 'Sum of psp_units' 'Zastępy PSP'))
    Y2 = @((New-Proj (New-Agg 'resource_deployment' 'wot_soldiers' 0) 'Sum(resource_deployment.wot_soldiers)' 'Sum of wot_soldiers' 'Żołnierze WOT'))
}
Add-Visual $parts $checks 'sily-ewakuacja' (New-DataVisual 'p4_combo' 'lineClusteredColumnComboChart' 'Tempo mobilizacji: PSP i WOT' $leftX $bandY $bandW $bandH $p4ComboRoles $TEAL (New-Col 'resource_deployment' 'timestamp') 'Ascending' $null 'WOT wchodzi z opóźnieniem wobec PSP — decyzja o wezwaniu wojska musi wyprzedzać kulminację') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(resource_deployment[timestamp],"PSP",SUM(resource_deployment[psp_units]),"WOT",SUM(resource_deployment[wot_soldiers])),resource_deployment[timestamp],ASC)' 'Tempo mobilizacji zasobów'

# ---------------------------------------------------------------- STRONA 5
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-KpiVisual 'p5_rzzk' 'Rekomendacje RZZK' $m.RZZK 'kis_country.Rekomendacje RZZK' 'Rekomendacje RZZK' $kpiX[0] $kpiY $kpiW $RED $RED_T) 'EVALUATE ROW("RZZK", [Rekomendacje RZZK])' 'Rekomendacje najwyższego poziomu'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-KpiVisual 'p5_kis_rzzk' 'Gminy z KIS ≥ 85' $m.KisRZZK 'kis_country.Gminy KIS RZZK' 'Gminy KIS RZZK' $kpiX[1] $kpiY $kpiW $AMBER $AMBER_T) 'EVALUATE ROW("Gminy", [Gminy KIS RZZK])' 'Gminy wymagające RZZK'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-KpiVisual 'p5_disinfo' 'Sygnały dezinformacji Z20' $m.Disinfo 'kis_country.Sygnały Dezinformacji' 'Sygnały Dezinformacji' $kpiX[2] $kpiY $kpiW $VIOLET $VIOLET_T) 'EVALUATE ROW("Sygnały", [Sygnały Dezinformacji])' 'Liczba sygnałów dezinformacyjnych'
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-KpiVisual 'p5_response' 'Czas reakcji [min]' $m.Response 'kis_country.Czas Reakcji Min' 'Czas Reakcji Min' $kpiX[3] $kpiY $kpiW $BLUE $BLUE_T) 'EVALUATE ROW("Minuty", [Czas Reakcji Min])' 'Czas od pierwszego zgłoszenia do eskalacji'

$p5ReachRoles = @{
    Category = @((New-Proj (New-Col 'media_signals' 'timestamp') 'media_signals.timestamp' 'timestamp' 'Czas'))
    Y = @((New-Proj $m.Reach 'kis_country.Zasieg Dezinformacji' 'Zasieg Dezinformacji' 'Zasięg Z20'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_reach_area' 'areaChart' 'Zasięg dezinformacji w czasie' $leftX $mainY $leftW $mainH $p5ReachRoles $RED (New-Col 'media_signals' 'timestamp') 'Ascending' $null 'Narracja podważająca ewakuację rozchodzi się szybciej niż komunikat urzędowy — stąd potrzeba wyprzedzającego RCB Alert') 'EVALUATE TOPN(1000,SUMMARIZECOLUMNS(media_signals[timestamp],"Zasięg",[Zasieg Dezinformacji]),media_signals[timestamp],ASC)' 'Trend zasięgu Z20'

$p5DonutRoles = @{
    Category = @((New-Proj (New-Col 'media_signals' 'channel') 'media_signals.channel' 'channel' 'Kanał'))
    Y = @((New-Proj $m.Disinfo 'kis_country.Sygnały Dezinformacji' 'Sygnały Dezinformacji' 'Sygnały Z20'))
}
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_donut' 'donutChart' 'Kanały dezinformacji' $rightX $mainY $rightW $mainH $p5DonutRoles $VIOLET $null 'Ascending' $null 'Dominujący kanał wyznacza formę reakcji: sprostowanie, RCB Alert czy wniosek do platformy') 'EVALUATE FILTER(SUMMARIZECOLUMNS(media_signals[channel],"Sygnały",[Sygnały Dezinformacji]),[Sygnały]>0)' 'Rozkład kanałów Z20'

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
Add-Visual $parts $checks 'eskalacja-spo-dezinformacja' (New-DataVisual 'p5_matrix' 'pivotTable' 'Rekomendacje z uzasadnieniem' $leftX $bandY $bandW $bandH $p5MatrixRoles $NAVY $null 'Ascending' $p5MatrixObjects 'Jedyne miejsce w raporcie, gdzie potrzebna jest wartość co do jednostki — to zapis decyzji do protokołu') 'EVALUATE TOPN(100,SUMMARIZECOLUMNS(escalation_recommendations[recommended_level],escalation_recommendations[gmina_code],escalation_recommendations[recommended_spo],escalation_recommendations[explanation],"KIS",AVERAGE(escalation_recommendations[kis])),[KIS],DESC)' 'Macierz decyzji i uzasadnień'

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
