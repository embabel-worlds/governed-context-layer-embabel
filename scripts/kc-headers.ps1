# Prints auth headers for the Knowledge Catalog (Dataplex) MCP server (Claude Code headersHelper
# in .mcp.json): a gcloud application-default access token, and CHAI_PROJECT_ID from the
# checkout's .env as the quota project. Exits non-zero instead of emitting an empty token.
$envFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
$project = $null
if (Test-Path $envFile) {
    $line = Get-Content $envFile | Select-String '^\s*CHAI_PROJECT_ID\s*=' | Select-Object -Last 1
    if ($line) { $project = ($line.Line -split '=', 2)[1].Trim().Trim('"') }
}
if (-not $project) {
    [Console]::Error.WriteLine("kc-headers.ps1: no CHAI_PROJECT_ID in $envFile.")
    exit 1
}
$token = $null
foreach ($attempt in 1..2) {
    $out = gcloud auth application-default print-access-token
    if ($LASTEXITCODE -eq 0) {
        $token = $out | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1
        if ($token) { $token = $token.Trim(); break }
    }
    if ($attempt -lt 2) { Start-Sleep -Seconds 2 }  # one retry for transient network/DNS errors
}
if (-not $token) {
    [Console]::Error.WriteLine('kc-headers.ps1: gcloud returned no access token (see the gcloud error above). Check network/TLS, or run: gcloud auth application-default login')
    exit 1
}
@{ "Authorization" = "Bearer $token"; "x-goog-user-project" = $project } | ConvertTo-Json -Compress
