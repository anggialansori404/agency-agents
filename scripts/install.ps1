<#
.SYNOPSIS
install.ps1 -- Install The Agency agents into your local agentic tool(s).
#>

$ErrorActionPreference = "Stop"

$ESC = [char]27
$HasTerminal = (-not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected)

if ($HasTerminal) {
    $global:C_GREEN  = "${ESC}[0;32m"
    $global:C_YELLOW = "${ESC}[1;33m"
    $global:C_RED    = "${ESC}[0;31m"
    $global:C_CYAN   = "${ESC}[0;36m"
    $global:C_BOLD   = "${ESC}[1m"
    $global:C_DIM    = "${ESC}[2m"
    $global:C_RESET  = "${ESC}[0m"
} else {
    $global:C_GREEN  = ""
    $global:C_YELLOW = ""
    $global:C_RED    = ""
    $global:C_CYAN   = ""
    $global:C_BOLD   = ""
    $global:C_DIM    = ""
    $global:C_RESET  = ""
}

function Write-Ok ($Message) { Write-Host "${C_GREEN}[OK]${C_RESET}  $Message" }
function Write-Warn ($Message) { Write-Host "${C_YELLOW}[!!]${C_RESET}  $Message" }
function Write-Err ($Message) { Write-Host "${C_RED}[ERR]${C_RESET} $Message" }
function Write-Header ($Message) { Write-Host "`n${C_BOLD}$Message${C_RESET}" }
function Write-Dim ($Message) { Write-Host "${C_DIM}$Message${C_RESET}" }

$BOX_INNER = 48
function Write-BoxTop { Write-Host ("  +" + ("-" * $BOX_INNER) + "+") }
function Write-BoxBot { Write-BoxTop }
function Write-BoxSep { Write-Host ("  |" + ("-" * $BOX_INNER) + "|") }
function Write-BoxRow($RawText) {
    $visible = $RawText -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
    $pad = $BOX_INNER - 2 - $visible.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host ("  | " + $RawText + (' ' * $pad) + " |")
}
function Write-BoxBlank { Write-Host ("  |" + (' ' * $BOX_INNER) + "|") }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = $PWD.ProviderPath }
$RepoRoot = Split-Path -Parent $ScriptDir
$Integrations = Join-Path $RepoRoot "integrations"
$CurrentDir = $PWD.ProviderPath

$AllTools = @("claude-code", "antigravity", "gemini-cli", "opencode", "cursor", "aider", "windsurf")

function Show-Usage {
    Write-Host @"
install.ps1 -- Install The Agency agents into your local agentic tool(s).

Reads converted files from integrations/ and copies them to the appropriate
config directory for each tool. Run scripts/convert.ps1 first if integrations/
is missing or stale.

Usage:
  .\scripts\install.ps1 [--tool <name>] [--interactive] [--no-interactive] [--help]

Tools:
  claude-code  -- Copy agents to ~/.claude/agents/
  antigravity  -- Copy skills to ~/.gemini/antigravity/skills/
  gemini-cli   -- Install extension to ~/.gemini/extensions/agency-agents/
  opencode     -- Copy agents to .opencode/agent/ in current directory
  cursor       -- Copy rules to .cursor/rules/ in current directory
  aider        -- Copy CONVENTIONS.md to current directory
  windsurf     -- Copy .windsurfrules to current directory
  all          -- Install for all detected tools (default)

Flags:
  --tool <name>     Install only the specified tool
  --interactive     Show interactive selector (default when run in a terminal)
  --no-interactive  Skip interactive selector, install all detected tools
  --help            Show this help

Platform support:
  Windows PowerShell 5.1+, PowerShell Core
"@
}

function Test-ClaudeCode { Test-Path (Join-Path $env:USERPROFILE ".claude") }
function Test-Antigravity { Test-Path (Join-Path $env:USERPROFILE ".gemini\antigravity\skills") }
function Test-GeminiCli { (Get-Command "gemini" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".gemini")) }
function Test-OpenCode { (Get-Command "opencode" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".config\opencode")) }
function Test-Cursor { (Get-Command "cursor" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".cursor")) }
function Test-Aider { (Get-Command "aider" -ErrorAction SilentlyContinue) }
function Test-Windsurf { (Get-Command "windsurf" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".codeium")) }

function Test-IsDetected($ToolName) {
    switch ($ToolName) {
        "claude-code" { return Test-ClaudeCode }
        "antigravity" { return Test-Antigravity }
        "gemini-cli"  { return Test-GeminiCli }
        "opencode"    { return Test-OpenCode }
        "cursor"      { return Test-Cursor }
        "aider"       { return Test-Aider }
        "windsurf"    { return Test-Windsurf }
        default       { return $false }
    }
}

function Get-ToolLabel($ToolName) {
    $name = ""
    $desc = ""
    switch ($ToolName) {
        "claude-code" { $name = "Claude Code"; $desc = "(claude.ai/code)" }
        "antigravity" { $name = "Antigravity"; $desc = "(~/.gemini/antigravity)" }
        "gemini-cli"  { $name = "Gemini CLI";  $desc = "(gemini extension)" }
        "opencode"    { $name = "OpenCode";    $desc = "(opencode.ai)" }
        "cursor"      { $name = "Cursor";      $desc = "(.cursor/rules)" }
        "aider"       { $name = "Aider";       $desc = "(CONVENTIONS.md)" }
        "windsurf"    { $name = "Windsurf";    $desc = "(.windsurfrules)" }
    }
    return '{0,-14}  {1}' -f $name, $desc
}

function Show-InteractiveSelect {
    $selected = @(0) * $AllTools.Length
    $detectedMap = @(0) * $AllTools.Length

    for ($i = 0; $i -lt $AllTools.Length; $i++) {
        if (Test-IsDetected $AllTools[$i]) {
            $selected[$i] = 1
            $detectedMap[$i] = 1
        }
    }

    while ($true) {
        Write-Host ""
        Write-BoxTop
        Write-BoxRow "${C_BOLD}  The Agency -- Tool Installer${C_RESET}"
        Write-BoxBot
        Write-Host ""
        Write-Host "  ${C_DIM}System scan:  [*] = detected on this machine${C_RESET}"
        Write-Host ""

        for ($i = 0; $i -lt $AllTools.Length; $i++) {
            $num = $i + 1
            $label = Get-ToolLabel $AllTools[$i]
            $dot = if ($detectedMap[$i] -eq 1) { "${C_GREEN}[*]${C_RESET}" } else { "${C_DIM}[ ]${C_RESET}" }
            $chk = if ($selected[$i] -eq 1) { "${C_GREEN}[x]${C_RESET}" } else { "${C_DIM}[ ]${C_RESET}" }

            Write-Host "  $chk  $num)  $dot  $label"
        }

        Write-Host ""
        Write-Host "  ------------------------------------------------"
        Write-Host "  ${C_CYAN}[1-$($AllTools.Length)]${C_RESET} toggle   ${C_CYAN}[a]${C_RESET} all   ${C_CYAN}[n]${C_RESET} none   ${C_CYAN}[d]${C_RESET} detected"
        Write-Host "  ${C_GREEN}[Enter]${C_RESET} install   ${C_RED}[q]${C_RESET} quit"
        Write-Host ""
        Write-Host "  >> " -NoNewline

        $inputStr = Read-Host

        $lines = $AllTools.Length + 14
        $shouldBreak = $false

        switch -Regex ($inputStr) {
            '^[qQ]$' {
                Write-Host "`n"
                Write-Ok "Aborted."
                exit 0
            }
            '^[aA]$' {
                for ($j = 0; $j -lt $AllTools.Length; $j++) { $selected[$j] = 1 }
            }
            '^[nN]$' {
                for ($j = 0; $j -lt $AllTools.Length; $j++) { $selected[$j] = 0 }
            }
            '^[dD]$' {
                for ($j = 0; $j -lt $AllTools.Length; $j++) { $selected[$j] = $detectedMap[$j] }
            }
            '^$' {
                $any = $false
                foreach ($s in $selected) { if ($s -eq 1) { $any = $true; break } }
                if ($any) {
                    $shouldBreak = $true
                } else {
                    Write-Host "  ${C_YELLOW}Nothing selected -- pick a tool or press q to quit.${C_RESET}"
                    Start-Sleep -Seconds 1
                    $lines++
                }
            }
            default {
                $toggled = $false
                $tokens = $inputStr -split '\s+'
                foreach ($token in $tokens) {
                    if ($token -match '^[0-9]+$') {
                        $idx = [int]$token - 1
                        if ($idx -ge 0 -and $idx -lt $AllTools.Length) {
                            $selected[$idx] = if ($selected[$idx] -eq 1) { 0 } else { 1 }
                            $toggled = $true
                        }
                    }
                }
                if (-not $toggled) {
                    Write-Host "  ${C_RED}Invalid. Enter a number 1-$($AllTools.Length), or a command.${C_RESET}"
                    Start-Sleep -Seconds 1
                    $lines++
                }
            }
        }

        if ($shouldBreak) { break }

        # Clear UI for redraw
        for ($l = 0; $l -lt $lines; $l++) {
            Write-Host "${ESC}[1A${ESC}[2K" -NoNewline
        }
    }

    $global:SelectedTools = @()
    for ($i = 0; $i -lt $AllTools.Length; $i++) {
        if ($selected[$i] -eq 1) {
            $global:SelectedTools += $AllTools[$i]
        }
    }
}

function Install-ClaudeCode {
    $dest = Join-Path $env:USERPROFILE ".claude\agents"
    $count = 0
    $null = New-Item -ItemType Directory -Force -Path $dest

    $dirs = @("design", "engineering", "marketing", "product", "project-management", "testing", "support", "spatial-computing", "specialized")
    foreach ($dir in $dirs) {
        $srcDir = Join-Path $RepoRoot $dir
        if (-not (Test-Path $srcDir)) { continue }
        $files = Get-ChildItem -Path $srcDir -Filter "*.md" -File
        foreach ($f in $files) {
            $firstLine = (Get-Content -Path $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($firstLine -eq "---") {
                Copy-Item -Path $f.FullName -Destination $dest -Force
                $count++
            }
        }
    }
    Write-Ok "Claude Code: $count agents -> $dest"
}

function Install-Antigravity {
    $src = Join-Path $Integrations "antigravity"
    $dest = Join-Path $env:USERPROFILE ".gemini\antigravity\skills"
    $count = 0
    if (-not (Test-Path $src)) { Write-Err "integrations/antigravity missing. Run convert.ps1 first."; return }
    $null = New-Item -ItemType Directory -Force -Path $dest
    $dirs = Get-ChildItem -Path $src -Directory
    foreach ($d in $dirs) {
        $name = $d.Name
        $targetDir = Join-Path $dest $name
        $null = New-Item -ItemType Directory -Force -Path $targetDir
        $skillFile = Join-Path $d.FullName "SKILL.md"
        if (Test-Path $skillFile) {
            Copy-Item -Path $skillFile -Destination (Join-Path $targetDir "SKILL.md") -Force
            $count++
        }
    }
    Write-Ok "Antigravity: $count skills -> $dest"
}

function Install-GeminiCli {
    $src = Join-Path $Integrations "gemini-cli"
    $dest = Join-Path $env:USERPROFILE ".gemini\extensions\agency-agents"
    $count = 0
    if (-not (Test-Path $src)) { Write-Err "integrations/gemini-cli missing. Run convert.ps1 first."; return }
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $dest "skills")
    $extJson = Join-Path $src "gemini-extension.json"
    if (Test-Path $extJson) {
        Copy-Item -Path $extJson -Destination (Join-Path $dest "gemini-extension.json") -Force
    }
    $skillsDir = Join-Path $src "skills"
    if (Test-Path $skillsDir) {
        $dirs = Get-ChildItem -Path $skillsDir -Directory
        foreach ($d in $dirs) {
            $name = $d.Name
            $targetDir = Join-Path $dest "skills\$name"
            $null = New-Item -ItemType Directory -Force -Path $targetDir
            $skillFile = Join-Path $d.FullName "SKILL.md"
            if (Test-Path $skillFile) {
                Copy-Item -Path $skillFile -Destination (Join-Path $targetDir "SKILL.md") -Force
                $count++
            }
        }
    }
    Write-Ok "Gemini CLI: $count skills -> $dest"
}

function Install-OpenCode {
    $src = Join-Path $Integrations "opencode\agent"
    $dest = Join-Path $CurrentDir ".opencode\agent"
    $count = 0
    if (-not (Test-Path $src)) { Write-Err "integrations/opencode missing. Run convert.ps1 first."; return }
    $null = New-Item -ItemType Directory -Force -Path $dest
    $files = Get-ChildItem -Path $src -Filter "*.md" -File
    foreach ($f in $files) {
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $count++
    }
    Write-Ok "OpenCode: $count agents -> $dest"
    Write-Warn "OpenCode: project-scoped. Run from your project root to install there."
}

function Install-Cursor {
    $src = Join-Path $Integrations "cursor\rules"
    $dest = Join-Path $CurrentDir ".cursor\rules"
    $count = 0
    if (-not (Test-Path $src)) { Write-Err "integrations/cursor missing. Run convert.ps1 first."; return }
    $null = New-Item -ItemType Directory -Force -Path $dest
    $files = Get-ChildItem -Path $src -Filter "*.mdc" -File
    foreach ($f in $files) {
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $count++
    }
    Write-Ok "Cursor: $count rules -> $dest"
    Write-Warn "Cursor: project-scoped. Run from your project root to install there."
}

function Install-Aider {
    $src = Join-Path $Integrations "aider\CONVENTIONS.md"
    $dest = Join-Path $CurrentDir "CONVENTIONS.md"
    if (-not (Test-Path $src)) { Write-Err "integrations/aider/CONVENTIONS.md missing. Run convert.ps1 first."; return }
    if (Test-Path $dest) {
        Write-Warn "Aider: CONVENTIONS.md already exists at $dest (remove to reinstall)."
        return
    }
    Copy-Item -Path $src -Destination $dest -Force
    Write-Ok "Aider: installed -> $dest"
    Write-Warn "Aider: project-scoped. Run from your project root to install there."
}

function Install-Windsurf {
    $src = Join-Path $Integrations "windsurf\.windsurfrules"
    $dest = Join-Path $CurrentDir ".windsurfrules"
    if (-not (Test-Path $src)) { Write-Err "integrations/windsurf/.windsurfrules missing. Run convert.ps1 first."; return }
    if (Test-Path $dest) {
        Write-Warn "Windsurf: .windsurfrules already exists at $dest (remove to reinstall)."
        return
    }
    Copy-Item -Path $src -Destination $dest -Force
    Write-Ok "Windsurf: installed -> $dest"
    Write-Warn "Windsurf: project-scoped. Run from your project root to install there."
}

function Install-Tool($ToolName) {
    switch ($ToolName) {
        "claude-code" { Install-ClaudeCode }
        "antigravity" { Install-Antigravity }
        "gemini-cli"  { Install-GeminiCli }
        "opencode"    { Install-OpenCode }
        "cursor"      { Install-Cursor }
        "aider"       { Install-Aider }
        "windsurf"    { Install-Windsurf }
    }
}

$Tool = "all"
$InteractiveMode = "auto"

$i = 0
while ($i -lt $args.Length) {
    $arg = $args[$i]
    switch ($arg) {
        "--tool" {
            if ($i + 1 -lt $args.Length) {
                $Tool = $args[$i + 1]
                $i += 2
                $InteractiveMode = "no"
            } else {
                Write-Err "--tool requires a value"
                exit 1
            }
        }
        "--interactive" {
            $InteractiveMode = "yes"
            $i++
        }
        "--no-interactive" {
            $InteractiveMode = "no"
            $i++
        }
        { $_ -in "--help", "-h" } {
            Show-Usage
            exit 0
        }
        default {
            Write-Err "Unknown option: $arg"
            Show-Usage
            exit 1
        }
    }
}

if (-not (Test-Path $Integrations)) {
    Write-Err "integrations/ not found. Run .\scripts\convert.ps1 first."
    exit 1
}

if ($Tool -ne "all") {
    $valid = $false
    foreach ($t in $AllTools) {
        if ($t -eq $Tool) { $valid = $true; break }
    }
    if (-not $valid) {
        Write-Err "Unknown tool '$Tool'. Valid: $($AllTools -join ' ')"
        exit 1
    }
}

$UseInteractive = $false
if ($InteractiveMode -eq "yes") {
    $UseInteractive = $true
} elseif ($InteractiveMode -eq "auto" -and $HasTerminal -and $Tool -eq "all") {
    $UseInteractive = $true
}

$global:SelectedTools = @()

if ($UseInteractive) {
    Show-InteractiveSelect
} elseif ($Tool -ne "all") {
    $global:SelectedTools += $Tool
} else {
    Write-Header "The Agency -- Scanning for installed tools..."
    Write-Host ""
    foreach ($t in $AllTools) {
        if (Test-IsDetected $t) {
            $global:SelectedTools += $t
            $label = Get-ToolLabel $t
            Write-Host "  ${C_GREEN}[*]${C_RESET}  $label  ${C_DIM}detected${C_RESET}"
        } else {
            $label = Get-ToolLabel $t
            Write-Host "  ${C_DIM}[ ]  $label  not found${C_RESET}"
        }
    }
}

if ($global:SelectedTools.Length -eq 0) {
    Write-Warn "No tools selected or detected. Nothing to install."
    Write-Host ""
    Write-Dim "  Tip: use --tool <name> to force-install a specific tool."
    Write-Dim "  Available: $($AllTools -join ' ')"
    exit 0
}

Write-Host ""
Write-Header "The Agency -- Installing agents"
Write-Host "  Repo:       $RepoRoot"
Write-Host "  Installing: $($global:SelectedTools -join ' ')"
Write-Host ""

$installed = 0
foreach ($t in $global:SelectedTools) {
    Install-Tool $t
    $installed++
}

$msg = "  Done!  Installed $installed tool(s)."
Write-Host ""
Write-BoxTop
Write-BoxRow "${C_GREEN}${C_BOLD}${msg}${C_RESET}"
Write-BoxBot
Write-Host ""
Write-Dim "  Run .\scripts\convert.ps1 to regenerate after adding or editing agents."
Write-Host ""
