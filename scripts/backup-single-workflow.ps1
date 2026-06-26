param(
    [string]$ApiBaseUrl = "https://n8n.kbusiness.ca/api/v1",
    [string]$ApiKey,
    [string]$ApiKeyFile = "fetch_workflow.http",
    [string]$WorkflowId,
    [string]$WorkflowName,
    [string]$OutputFile,
    [string]$OutputRoot = "source",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $WorkflowId -and -not $WorkflowName) {
    Write-Error "WorkflowId or WorkflowName is required."
    exit 1
}

function Get-ApiKeyFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "API key file not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($raw, "X-N8N-API-KEY:\s*([^\r\n]+)")
    if (-not $match.Success) {
        throw "Could not find X-N8N-API-KEY in $Path"
    }
    return $match.Groups[1].Value.Trim()
}

function Get-SafePathPart {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "unnamed" }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($ch in $invalid) { $safe = $safe.Replace([string]$ch, "_") }
    $safe = $safe.Trim().TrimEnd(".")
    if ([string]::IsNullOrWhiteSpace($safe)) { return "unnamed" }
    return $safe
}

function Invoke-N8nGet {
    param(
        [string]$Path,
        [hashtable]$Headers,
        [hashtable]$Query
    )

    $qs = ""
    if ($Query) {
        $pairs = foreach ($k in $Query.Keys) {
            $v = $Query[$k]
            if ($null -ne $v -and "$v" -ne "") {
                "{0}={1}" -f [Uri]::EscapeDataString("$k"), [Uri]::EscapeDataString("$v")
            }
        }
        $pairs = @($pairs | Where-Object { $_ })
        if ($pairs.Count -gt 0) {
            $qs = "?" + ($pairs -join "&")
        }
    }

    $uri = "$ApiBaseUrl$Path$qs"
    return Invoke-RestMethod -Uri $uri -Method Get -Headers $Headers
}

if (-not $ApiKey) {
    if ($env:N8N_API_KEY) {
        $ApiKey = $env:N8N_API_KEY
    } else {
        $ApiKey = Get-ApiKeyFromFile -Path $ApiKeyFile
    }
}

$headers = @{ "X-N8N-API-KEY" = $ApiKey }

if (-not $WorkflowId) {
    Write-Host "Searching workflow by name: $WorkflowName"
    $resp = Invoke-N8nGet -Path "/workflows" -Headers $headers -Query @{ limit = 250 }
    $found = @($resp.data) | Where-Object { $_.name -eq $WorkflowName }
    if ($found.Count -eq 0) {
        Write-Error "Workflow not found: $WorkflowName"
        exit 1
    }
    if ($found.Count -gt 1) {
        Write-Warning "Multiple workflows found with that name. Using the first one."
    }
    $WorkflowId = "$($found[0].id)"
    Write-Host "Found: $WorkflowId ($($found[0].name))"
}

$detail = Invoke-N8nGet -Path "/workflows/$WorkflowId" -Headers $headers -Query @{}
$wfName = "$($detail.name)"

if (-not $OutputFile) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $resolvedRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
        $OutputRoot
    } else {
        Join-Path -Path $projectRoot -ChildPath $OutputRoot
    }
    $safeName = Get-SafePathPart -Name $wfName
    $OutputFile = Join-Path -Path $resolvedRoot -ChildPath "${safeName}_${WorkflowId}.json"
}

if ($DryRun) {
    Write-Host "[DRY-RUN] $WorkflowId ($wfName) => $OutputFile"
} else {
    $dir = Split-Path -Parent $OutputFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $detail | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputFile -Encoding utf8
    Write-Host "Saved: $OutputFile"
    Write-Host "Workflow: $wfName (ID: $WorkflowId)"
}
