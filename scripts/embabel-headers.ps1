# Prints the auth header for the appliance's MCP door (Claude Code headersHelper in .mcp.json).
# Reads EMBABEL_MCP_TOKEN from the checkout's .env, so the token never sits in .mcp.json.
# Exits non-zero instead of emitting an empty "Bearer " token when the line is missing.
$envFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
$token = $null
if (Test-Path $envFile) {
    $line = Get-Content $envFile | Select-String '^\s*EMBABEL_MCP_TOKEN\s*=' | Select-Object -Last 1
    if ($line) { $token = ($line.Line -split '=', 2)[1].Trim().Trim('"') }
}
if (-not $token) {
    [Console]::Error.WriteLine("embabel-headers.ps1: no EMBABEL_MCP_TOKEN in $envFile. Add the token the appliance minted at setup (README step 6).")
    exit 1
}
@{ "Authorization" = "Bearer $token" } | ConvertTo-Json -Compress
