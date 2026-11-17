<#
.SYNOPSIS
  Fills in this checkout for your machine and Google Cloud project, from .env.

.DESCRIPTION
  1. Renders realm-chai\ into realms\realm-chai\, replacing ${CHAI_PROJECT_ID}, ${CHAI_REGION},
     ${CHAI_INSTANCE} and ${CHAI_PROXY_PORT}. realms\ is what `embabel realms link` points at.
  2. Writes the Claude Code session folders sessions\agent, sessions\setup and
     sessions\agent-no-kc, each holding only a .mcp.json with this checkout's helper paths.

  Both outputs are gitignored. Re-run it after editing realm-chai\ or .env; it replaces only
  what it made. Edit realm-chai\, never realms\realm-chai\.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) {
    throw "No .env in $root. Copy .env.example to .env and fill in CHAI_PROJECT_ID."
}

# Last assignment wins, as in a shell. Surrounding quotes are dropped.
$dotenv = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $dotenv[$Matches[1]] = $Matches[2] -replace '^"(.*)"$', '$1' -replace "^'(.*)'$", '$1'
    }
}

function Get-Setting([string]$Name, [string]$Default, [string]$Pattern) {
    $value = $dotenv[$Name]
    if (-not $value) { $value = $Default }
    if (-not $value) { throw "$Name is not set in $envFile." }
    if ($value -cnotmatch $Pattern) { throw "$Name='$value' in $envFile does not match $Pattern." }
    $value
}

$values = [ordered]@{
    CHAI_PROJECT_ID = Get-Setting 'CHAI_PROJECT_ID' '' '^[a-z][a-z0-9-]{4,28}[a-z0-9]$'
    CHAI_REGION     = Get-Setting 'CHAI_REGION' 'asia-south1' '^[a-z]+-[a-z]+[0-9]+$'
    CHAI_INSTANCE   = Get-Setting 'CHAI_INSTANCE' 'chai-and-co-pg' '^[a-z][a-z0-9-]*$'
    CHAI_PROXY_PORT = Get-Setting 'CHAI_PROXY_PORT' '5433' '^[0-9]{2,5}$'
}
$mcpUrl = Get-Setting 'EMBABEL_MCP_URL' 'http://localhost:11043/mcp/code' '^https?://[^\s"\\]+$'

# ── 1. Render the realm ──────────────────────────────────────────────────────────────────────
$utf8 = New-Object System.Text.UTF8Encoding($false)
$src = Join-Path $root 'realm-chai'
$out = Join-Path (Join-Path $root 'realms') 'realm-chai'
$note = 'Generated from realm-chai/ by scripts/configure; edit the source, not this copy.'

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null

Get-ChildItem $src -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/')
    $dest = Join-Path $out $rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
    $text = [IO.File]::ReadAllText($_.FullName, $utf8)
    foreach ($key in $values.Keys) { $text = $text.Replace('${' + $key + '}', $values[$key]) }
    if ($text -match '\$\{CHAI_[A-Z_]+\}') { throw "realm-chai\$rel uses $($Matches[0]), which configure does not fill in." }
    $header = switch -Regex ($_.Extension) {
        '^\.ya?ml$' { "# $note`n" }
        '^\.md$'    { "<!-- $note -->`n" }
        default     { '' }
    }
    [IO.File]::WriteAllText($dest, $header + $text, $utf8)
}

# ── 2. Write the session folders ─────────────────────────────────────────────────────────────
$shell = if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { 'powershell' } else { 'pwsh' }
function Get-Helper([string]$Script) {
    $path = (Join-Path (Join-Path $root 'scripts') $Script) -replace '\\', '/'
    if ($path -match ' ') { $path = '"' + $path + '"' }
    "$shell -NoProfile -ExecutionPolicy Bypass -File $path"
}
function ConvertTo-JsonString([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }

$embabel = @"
    "embabel": {
      "type": "http",
      "url": $(ConvertTo-JsonString $mcpUrl),
      "headersHelper": $(ConvertTo-JsonString (Get-Helper 'embabel-headers.ps1'))
    }
"@
$catalog = @"
    "datacloud_knowledge_catalog_remote": {
      "type": "http",
      "url": "https://dataplex.googleapis.com/mcp",
      "headersHelper": $(ConvertTo-JsonString (Get-Helper 'kc-headers.ps1'))
    },
"@

$sessions = [ordered]@{
    'agent'       = "$catalog`n$embabel"
    'setup'       = $embabel
    'agent-no-kc' = $embabel
}
foreach ($name in $sessions.Keys) {
    $dir = Join-Path (Join-Path $root 'sessions') $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    $json = "{`n  `"mcpServers`": {`n" + ($sessions[$name] -replace "`r", '') + "`n  }`n}`n"
    [IO.File]::WriteAllText((Join-Path $dir '.mcp.json'), $json, $utf8)
}

$realms = Join-Path $root 'realms'
Write-Host "Rendered $out"
Write-Host "Wrote sessions\agent, sessions\setup and sessions\agent-no-kc"
Write-Host ''
Write-Host 'Cloud SQL Auth Proxy (README step 3):'
Write-Host "  cloud-sql-proxy --port $($values.CHAI_PROXY_PORT) $($values.CHAI_PROJECT_ID):$($values.CHAI_REGION):$($values.CHAI_INSTANCE)"
Write-Host 'Link the realm folder (README step 6):'
Write-Host "  embabel realms link `"$realms`""
