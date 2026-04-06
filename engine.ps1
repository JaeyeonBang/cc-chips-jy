#!/usr/bin/env pwsh
# CC CHIPS-JY — PowerShell engine for Windows Terminal / PowerShell
#
# Reads JSON from stdin, outputs a plain ASCII status line.
# No ANSI escape codes by default (safe for all PowerShell environments).
#
# Configure in ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "pwsh -NoProfile -File C:\\Users\\USERNAME\\.claude\\cc-chips\\engine.ps1"
#   }
#
# Requirements: PowerShell 7+ (pwsh) or Windows PowerShell 5.1+, git in PATH

param()

# ── Read JSON from stdin ─────────────────────────────────────────
$inputRaw = @($input) -join "`n"
if ([string]::IsNullOrWhiteSpace($inputRaw)) {
    Write-Output "[CC CHIPS-JY] No input received"
    exit 0
}

try {
    $data = $inputRaw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Output "[CC CHIPS-JY] Invalid JSON input"
    exit 1
}

# ── Safe nested property access ──────────────────────────────────
function Get-Nested {
    param($obj, [string[]]$path, $default = "")
    $cur = $obj
    foreach ($key in $path) {
        if ($null -eq $cur) { return $default }
        $prop = $cur.PSObject.Properties[$key]
        if ($null -eq $prop) { return $default }
        $cur = $prop.Value
    }
    if ($null -eq $cur) { return $default }
    return $cur
}

# ── Extract fields ────────────────────────────────────────────────
$projectDir = Get-Nested $data @("workspace", "project_dir") ""
if ([string]::IsNullOrEmpty($projectDir)) {
    $projectDir = Get-Nested $data @("workspace", "current_dir") "."
}
$shortPath = Split-Path $projectDir -Leaf
if ([string]::IsNullOrEmpty($shortPath)) { $shortPath = $projectDir }

$sessionId    = Get-Nested $data @("session_id") "unknown"
$sessionShort = $sessionId.Substring(0, [Math]::Min(8, $sessionId.Length))

# Model (may be object or string)
$modelRaw = ""
$modelObj = $data.PSObject.Properties["model"]
if ($null -ne $modelObj) {
    $m = $modelObj.Value
    if ($m -is [string]) { $modelRaw = $m }
    elseif ($null -ne $m) {
        $dn = $m.PSObject.Properties["display_name"]
        $id = $m.PSObject.Properties["id"]
        $modelRaw = if ($null -ne $dn -and $null -ne $dn.Value) { $dn.Value }
                    elseif ($null -ne $id -and $null -ne $id.Value) { $id.Value }
                    else { "unknown" }
    }
}

# Model display name normalization
$modelDisplay = switch -Regex ($modelRaw) {
    "opus.*4\.6|opus-4-6"     { "Opus 4.6";    break }
    "opus.*4\.5|opus-4-5"     { "Opus 4.5";    break }
    "opus.*4|opus-4"          { "Opus 4";      break }
    "sonnet.*4\.6|sonnet-4-6" { "Sonnet 4.6";  break }
    "sonnet.*4\.5|sonnet-4-5" { "Sonnet 4.5";  break }
    "sonnet.*4|sonnet-4"      { "Sonnet 4";    break }
    "sonnet.*3\.5|sonnet-3-5" { "Sonnet 3.5";  break }
    "haiku.*4\.5|haiku-4-5"   { "Haiku 4.5";   break }
    "haiku.*3\.5|haiku-3-5"   { "Haiku 3.5";   break }
    default                   { $modelRaw }
}
if ([string]::IsNullOrEmpty($modelDisplay)) { $modelDisplay = "unknown" }

# Context window tokens
$inputTok   = [int](Get-Nested $data @("context_window","current_usage","input_tokens") 0)
$outputTok  = [int](Get-Nested $data @("context_window","current_usage","output_tokens") 0)
$cacheRead  = [int](Get-Nested $data @("context_window","current_usage","cache_read_input_tokens") 0)
$cacheWrite = [int](Get-Nested $data @("context_window","current_usage","cache_creation_input_tokens") 0)
$ctxSize    = [int](Get-Nested $data @("context_window","context_window_size") 0)
$apiMs      = [int](Get-Nested $data @("cost","total_api_duration_ms") 0)

# ── Derived calculations ──────────────────────────────────────────
$currentCtx = $inputTok + $cacheWrite + $cacheRead
$contextPct = if ($ctxSize -gt 0) { [int]($currentCtx * 100 / $ctxSize) } else { 0 }

$totalCtxTok = $inputTok + $cacheRead + $cacheWrite
$cachePct    = if ($totalCtxTok -gt 0) { [int]($cacheRead * 100 / $totalCtxTok) } else { 0 }

$apiSec  = if ($apiMs -gt 0) { "{0:F1}" -f ($apiMs / 1000.0) } else { "0.0" }
$apiWarn = if ($apiMs -ge 10000) { "!! " } else { "" }

# Context bar (5 chars)
$ctxFilled = [int]($contextPct * 5 / 100)
$ctxBar    = ("#" * $ctxFilled) + ("-" * (5 - $ctxFilled))

# Cost calculation (per 1M tokens, in cents)
# Opus 4.6: $5/$25, Sonnet 4.6: $3/$15, Haiku 4.5: $1/$5
# Cache read: 0.1x input, Cache write: 1.25x input
$priceIn, $priceOut, $priceCR, $priceCW = switch -Regex ($modelDisplay) {
    "^Sonnet" { 300,  1500,  30,  375;  break }
    "^Haiku"  { 100,  500,   10,  125;  break }
    default   { 500,  2500,  50,  625        }
}
$costCents = [long](($inputTok * $priceIn + $outputTok * $priceOut +
                     $cacheRead * $priceCR + $cacheWrite * $priceCW) / 1000000)
$costDisplay = if ($costCents -eq 0)        { '$0' }
               elseif ($costCents -lt 100)  { '$0.{0:D2}' -f [int]$costCents }
               else { '$' + [int]($costCents / 100) + '.{0:D2}' -f ($costCents % 100) }

# ── Git detection ─────────────────────────────────────────────────
$gitBranch = ""
$gitDirty  = ""
try {
    $gb = & git -C "$projectDir" branch --show-current 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($gb)) {
        $gitBranch = $gb.Trim()
        & git -C "$projectDir" diff --quiet 2>$null
        $diffExit = $LASTEXITCODE
        & git -C "$projectDir" diff --cached --quiet 2>$null
        $diffCachedExit = $LASTEXITCODE
        if ($diffExit -ne 0 -or $diffCachedExit -ne 0) { $gitDirty = " *" }
    }
} catch { }

# ── Build output (ASCII, no ANSI) ────────────────────────────────
$chip1 = "[# $shortPath]"
$chip2 = if ($gitBranch) { " [> @ $gitBranch$gitDirty]" } else { "" }
$chip3 = " [~ $modelDisplay % [$ctxBar] $contextPct% $ $costDisplay & $sessionShort]"
$chip4 = " [= ${cachePct}% ! ${apiWarn}${apiSec}s]"

Write-Output "${chip1}${chip2}${chip3}${chip4}"
