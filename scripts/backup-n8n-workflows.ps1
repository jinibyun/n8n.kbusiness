param(
    [string]$ApiBaseUrl = "https://n8n.kbusiness.ca/api/v1",
    [string]$ApiKey,
    [string]$ApiKeyFile = "fetch_workflow.http",
    [string]$OutputRoot = "source",
    [string]$DateFolder = (Get-Date -Format "yyyyMMdd"),
    [int]$Limit = 100,
    [switch]$Flat,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ApiKeyFromFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "API key file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($raw, "X-N8N-API-KEY:\s*([^\r\n]+)")
    if (-not $match.Success) {
        throw "Could not find 'X-N8N-API-KEY' in $Path"
    }

    return $match.Groups[1].Value.Trim()
}

function Get-SafePathPart {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "unnamed"
    }

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($ch in $invalid) {
        $safe = $safe.Replace([string]$ch, "_")
    }

    $safe = $safe.Trim().TrimEnd(".")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed"
    }

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

function Get-WorkflowSummaries {
    param(
        [hashtable]$Headers,
        [int]$PageLimit
    )

    $all = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]

    $cursor = $null

    while ($true) {
        $query = @{ limit = $PageLimit }
        if ($cursor) {
            $query.cursor = $cursor
        }

        $resp = Invoke-N8nGet -Path "/workflows" -Headers $Headers -Query $query
        $items = @($resp.data)

        if ($items.Count -eq 0) {
            break
        }

        $addedThisRound = 0
        foreach ($wf in $items) {
            $id = "$($wf.id)"
            if (-not [string]::IsNullOrWhiteSpace($id) -and $seen.Add($id)) {
                $all.Add($wf)
                $addedThisRound++
            }
        }

        if ($resp.PSObject.Properties.Name -contains "nextCursor" -and $resp.nextCursor) {
            $cursor = "$($resp.nextCursor)"
            continue
        }

        if ($items.Count -lt $PageLimit) {
            break
        }

        if ($addedThisRound -eq 0) {
            break
        }

        break
    }

    return $all.ToArray()
}

function Get-FolderMap {
    param([hashtable]$Headers)

    $folderById = @{}

    try {
        $projectsResp = Invoke-N8nGet -Path "/projects" -Headers $Headers -Query @{ limit = 100 }
        $projects = @($projectsResp.data)
    } catch {
        $projects = @()
    }

    foreach ($project in $projects) {
        $projectId = "$($project.id)"
        if ([string]::IsNullOrWhiteSpace($projectId)) {
            continue
        }

        try {
            $foldersResp = Invoke-N8nGet -Path "/folders" -Headers $Headers -Query @{ projectId = $projectId; limit = 250 }
            $folders = @($foldersResp.data)

            foreach ($folder in $folders) {
                if (-not $folderById.ContainsKey("$($folder.id)")) {
                    $folderById["$($folder.id)"] = [pscustomobject]@{
                        id = "$($folder.id)"
                        name = "$($folder.name)"
                        parentFolderId = "$($folder.parentFolderId)"
                        projectId = $projectId
                    }
                }
            }
        } catch {
            # Continue without folder metadata if folder API is unavailable.
        }
    }

    return $folderById
}

function Resolve-FolderPath {
    param(
        [string]$FolderId,
        [hashtable]$FolderById
    )

    if ([string]::IsNullOrWhiteSpace($FolderId)) {
        return ""
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $current = $FolderId
    $guard = 0

    while (-not [string]::IsNullOrWhiteSpace($current) -and $guard -lt 50) {
        $guard++

        if (-not $FolderById.ContainsKey($current)) {
            $parts.Insert(0, "folder_$current")
            break
        }

        $folder = $FolderById[$current]
        $parts.Insert(0, (Get-SafePathPart -Name $folder.name))
        $current = "$($folder.parentFolderId)"
    }

    return ($parts -join [System.IO.Path]::DirectorySeparatorChar)
}

if (-not $ApiKey) {
    if ($env:N8N_API_KEY) {
        $ApiKey = $env:N8N_API_KEY
    } else {
        $ApiKey = Get-ApiKeyFromFile -Path $ApiKeyFile
    }
}

$headers = @{ "X-N8N-API-KEY" = $ApiKey }

$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot
} else {
    Join-Path -Path $projectRoot -ChildPath $OutputRoot
}

$outputBase = Join-Path -Path $resolvedOutputRoot -ChildPath $DateFolder
if (Test-Path -LiteralPath $outputBase) {
    Remove-Item -LiteralPath $outputBase -Recurse -Force
}
New-Item -ItemType Directory -Path $outputBase -Force | Out-Null

$workflows = Get-WorkflowSummaries -Headers $headers -PageLimit $Limit
if ($workflows.Count -eq 0) {
    Write-Host "No workflows found."
    exit 0
}

$folderMap = @{}
if (-not $Flat) {
    $folderMap = Get-FolderMap -Headers $headers
    if ($folderMap.Count -eq 0) {
        Write-Warning "Folder metadata is unavailable via current API. Backup will be saved as flat files under the date folder."
    }
}

$written = 0
$failed = 0

foreach ($wf in $workflows) {
    $wfId = "$($wf.id)"
    $wfName = "$($wf.name)"

    try {
        $detail = Invoke-N8nGet -Path "/workflows/$wfId" -Headers $headers -Query @{}

        $relativeDir = ""
        if (-not $Flat) {
            $parentFolderId = ""
            if ($detail.PSObject.Properties.Name -contains "parentFolderId") {
                $parentFolderId = "$($detail.parentFolderId)"
            } elseif ($wf.PSObject.Properties.Name -contains "parentFolderId") {
                $parentFolderId = "$($wf.parentFolderId)"
            }

            $relativeDir = Resolve-FolderPath -FolderId $parentFolderId -FolderById $folderMap
        }

        $targetDir = $outputBase
        if (-not [string]::IsNullOrWhiteSpace($relativeDir)) {
            $targetDir = Join-Path -Path $outputBase -ChildPath $relativeDir
        }

        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        $safeName = Get-SafePathPart -Name $wfName
        $fileName = "$safeName.json"
        $filePath = Join-Path -Path $targetDir -ChildPath $fileName

        if ($DryRun) {
            Write-Host "[DRY-RUN] $wfId => $filePath"
        } else {
            $detail | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $filePath -Encoding utf8
            Write-Host "Saved $wfId => $filePath"
        }

        $written++
    } catch {
        $failed++
        Write-Warning "Failed $wfId ($wfName): $($_.Exception.Message)"
    }
}

if ($DryRun) {
    Write-Host "Done (dry-run). Workflows scanned: $($workflows.Count), Planned: $written, Failed: $failed"
} else {
    Write-Host "Done. Workflows scanned: $($workflows.Count), Saved: $written, Failed: $failed"
    Write-Host "Backup root: $outputBase"
}
