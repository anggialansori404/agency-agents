#!/usr/bin/env pwsh
<#
.SYNOPSIS
Validates agent markdown files:
  1. YAML frontmatter must exist with name, description, color (ERROR)
  2. Recommended sections checked but only warned (WARN)
  3. File must have meaningful content

.DESCRIPTION
Usage: .\scripts\lint-agents.ps1 [file ...]
  If no files given, scans all agent directories.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$AgentDirs = @(
    "design"
    "engineering"
    "marketing"
    "product"
    "project-management"
    "testing"
    "support"
    "spatial-computing"
    "specialized"
    "strategy"
)

$RequiredFrontmatter = @("name", "description", "color")
$RecommendedSections = @("Identity", "Core Mission", "Critical Rules")

$Script:errors = 0
$Script:warnings = 0

function Lint-File {
    param (
        [string]$File
    )

    if (-not (Test-Path -Path $File -PathType Leaf)) {
        Write-Output "ERROR $($File): file does not exist"
        $Script:errors++
        return
    }

    $lines = Get-Content -Path $File
    if ($null -eq $lines) {
        $lines = @()
    } elseif ($lines -is [string]) {
        $lines = @($lines)
    }

    if ($lines.Count -eq 0) {
        $first_line = ""
    } else {
        $first_line = $lines[0]
    }

    if ($first_line -ne "---") {
        Write-Output "ERROR $($File): missing frontmatter opening ---"
        $Script:errors++
        return
    }

    # Extract frontmatter
    $frontmatterLines = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "---") {
            break
        }
        $frontmatterLines += $lines[$i]
    }
    $frontmatterText = $frontmatterLines -join "`n"

    if ([string]::IsNullOrWhiteSpace($frontmatterText)) {
        Write-Output "ERROR $($File): empty or malformed frontmatter"
        $Script:errors++
        return
    }

    foreach ($field in $RequiredFrontmatter) {
        if (-not ($frontmatterText -match "(?m)^${field}:")) {
            Write-Output "ERROR $($File): missing frontmatter field '${field}'"
            $Script:errors++
        }
    }

    # Extract body using bash's awk logic
    $bodyLines = @()
    $n = 0
    foreach ($line in $lines) {
        if ($line -eq "---") {
            $n++
            continue
        }
        if ($n -ge 2) {
            $bodyLines += $line
        }
    }
    $bodyText = $bodyLines -join "`n"

    foreach ($section in $RecommendedSections) {
        if (-not ($bodyText -match "(?i)$([regex]::Escape($section))")) {
            Write-Output "WARN  $($File): missing recommended section '${section}'"
            $Script:warnings++
        }
    }

    $wordCount = 0
    if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
        $wordCount = [regex]::Matches($bodyText, "\S+").Count
    }

    if ($wordCount -lt 50) {
        Write-Output "WARN  $($File): body seems very short (< 50 words)"
        $Script:warnings++
    }
}

$filesToLint = @()
if ($Files -and $Files.Count -gt 0) {
    $filesToLint = $Files
} else {
    foreach ($dir in $AgentDirs) {
        if (Test-Path -Path $dir) {
            $mdFiles = Get-ChildItem -Path $dir -Filter "*.md" -File | Sort-Object Name
            foreach ($f in $mdFiles) {
                # Format to forward slashes to match bash output
                $relPath = "$dir/" + $f.Name
                $filesToLint += $relPath
            }
        }
    }
}

if ($filesToLint.Count -eq 0) {
    Write-Output "No agent files found."
    exit 1
}

Write-Output "Linting $($filesToLint.Count) agent files..."
Write-Output ""

foreach ($file in $filesToLint) {
    Lint-File -File $file
}

Write-Output ""
Write-Output "Results: ${Script:errors} error(s), ${Script:warnings} warning(s) in $($filesToLint.Count) files."

if ($Script:errors -gt 0) {
    Write-Output "FAILED: fix the errors above before merging."
    exit 1
} else {
    Write-Output "PASSED"
    exit 0
}
