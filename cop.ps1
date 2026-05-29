# cop.ps1 - Copilot launcher with selective MCP loading (Windows PowerShell)
# Usage: cop -m webex,agilestudio,ms365 [other copilot args...]
# Setup: Add to $PROFILE: function cop { & "C:\path\to\cop.ps1" @args }

param(
    [string]$m,
    [switch]$dibm,
    [switch]$listmcps,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassthroughArgs
)

$McpConfig = Join-Path $env:USERPROFILE ".copilot\mcp-config.json"
$PluginsDir = Join-Path $env:USERPROFILE ".copilot\installed-plugins"

# Helper: Discover all MCPs from config + plugins + project
function Get-AllMcps {
    $allMcps = @{}

    # From global config
    if (Test-Path $McpConfig) {
        $config = Get-Content $McpConfig -Raw | ConvertFrom-Json
        $servers = $config.mcpServers
        foreach ($prop in $servers.PSObject.Properties) {
            $allMcps[$prop.Name] = @{ Source = "global"; Config = $prop.Value }
        }
    }

    # From plugins
    if (Test-Path $PluginsDir) {
        $mcpFiles = Get-ChildItem -Path $PluginsDir -Filter ".mcp.json" -Recurse -File
        foreach ($file in $mcpFiles) {
            $pluginName = ($file.FullName -split "installed-plugins[\\/]")[1] -split "[\\/]" | Select-Object -First 1
            $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ($data.mcpServers) {
                foreach ($prop in $data.mcpServers.PSObject.Properties) {
                    if (-not $allMcps.ContainsKey($prop.Name)) {
                        $allMcps[$prop.Name] = @{ Source = "plugin:$pluginName"; Config = $prop.Value }
                    }
                }
            }
        }
    }

    # From project-level configs
    $projectFiles = @(".mcp.json", ".github\mcp.json", ".github\mcp.local.json")
    foreach ($pf in $projectFiles) {
        if (Test-Path $pf) {
            $data = Get-Content $pf -Raw | ConvertFrom-Json
            if ($data.mcpServers) {
                foreach ($prop in $data.mcpServers.PSObject.Properties) {
                    if (-not $allMcps.ContainsKey($prop.Name)) {
                        $allMcps[$prop.Name] = @{ Source = "project:$pf"; Config = $prop.Value }
                    }
                }
            }
        }
    }

    return $allMcps
}

# Helper: Fuzzy match
function Find-McpMatch {
    param([string]$Query, [string[]]$AllKeys)

    $query = $Query.Trim().ToLower()

    # Exact match first
    $exact = $AllKeys | Where-Object { $_.ToLower() -eq $query }
    if ($exact) { return @($exact) }

    # Substring match
    $matches = $AllKeys | Where-Object {
        $key = $_.ToLower()
        $query.Contains($key) -or $key.Contains($query)
    }
    return @($matches)
}

# -listmcps
if ($listmcps) {
    $allMcps = Get-AllMcps
    Write-Host "Available MCPs:" -ForegroundColor Cyan
    Write-Host ""

    $global = $allMcps.GetEnumerator() | Where-Object { $_.Value.Source -eq "global" }
    if ($global) {
        Write-Host "  Global (~\.copilot\mcp-config.json):" -ForegroundColor White
        foreach ($entry in $global) {
            Write-Host "    * $($entry.Key)" -ForegroundColor Gray
        }
    }

    $plugins = $allMcps.GetEnumerator() | Where-Object { $_.Value.Source -like "plugin:*" }
    if ($plugins) {
        Write-Host ""
        Write-Host "  Plugins:" -ForegroundColor White
        foreach ($entry in $plugins) {
            Write-Host "    * $($entry.Key)  ($($entry.Value.Source))" -ForegroundColor Gray
        }
    }

    $project = $allMcps.GetEnumerator() | Where-Object { $_.Value.Source -like "project:*" }
    if ($project) {
        Write-Host ""
        Write-Host "  Project ($(Get-Location)):" -ForegroundColor White
        foreach ($entry in $project) {
            $src = $entry.Value.Source -replace "^project:", ""
            Write-Host "    * $($entry.Key)  ($src)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "  Built-in:" -ForegroundColor White
    Write-Host "    * github-mcp-server  (use -dibm to disable)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Usage: cop -m <name1>,<name2>  (fuzzy match supported)" -ForegroundColor Yellow
    Write-Host "Flags: -m <mcps>  -dibm  -listmcps" -ForegroundColor Yellow
    exit 0
}

$allMcps = Get-AllMcps
$allKeys = @($allMcps.Keys)

# No -m flag: disable all MCPs and launch copilot
if (-not $m) {
    $cmd = @("copilot")
    if ($dibm) { $cmd += "--disable-builtin-mcps" }
    foreach ($name in $allKeys) {
        $cmd += "--disable-mcp-server"
        $cmd += $name
    }
    $cmd += $PassthroughArgs
    Write-Host "`u{1F680} No MCPs loaded (all disabled)" -ForegroundColor Yellow
    Write-Host ""
    & $cmd[0] $cmd[1..($cmd.Length - 1)]
    exit $LASTEXITCODE
}

# Resolve requested MCPs
$requested = $m -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$resolved = @{}
$hasError = $false

foreach ($raw in $requested) {
    $matches = Find-McpMatch -Query $raw -AllKeys $allKeys

    if ($matches.Count -eq 1) {
        $match = $matches[0]
        $resolved[$match] = $allMcps[$match].Config
    }
    elseif ($matches.Count -gt 1) {
        Write-Host "  `u{26A0}`u{FE0F}  `"$raw`" matches multiple servers: $($matches -join ', ')" -ForegroundColor Red
        Write-Host "     Be more specific." -ForegroundColor Red
        $hasError = $true
    }
    else {
        Write-Host "  `u{26A0}`u{FE0F}  No MCP matching `"$raw`" in config" -ForegroundColor Red
        $hasError = $true
    }
}

if ($hasError) {
    Write-Host "`u{274C} Aborting. Fix the MCP names and retry." -ForegroundColor Red
    exit 1
}

# Build command
$cmd = @("copilot")
if ($dibm) { $cmd += "--disable-builtin-mcps" }

# Disable all non-selected MCPs
$toDisable = $allKeys | Where-Object { -not $resolved.ContainsKey($_) }
foreach ($name in $toDisable) {
    $cmd += "--disable-mcp-server"
    $cmd += $name
}

# Add selected MCPs as JSON
$mcpJson = @{ mcpServers = $resolved } | ConvertTo-Json -Depth 10 -Compress
$cmd += "--additional-mcp-config"
$cmd += $mcpJson

# Passthrough args
$cmd += $PassthroughArgs

$selectedNames = $resolved.Keys -join " "
$disabledNames = $toDisable -join " "
Write-Host "`u{1F680} Loading MCPs: $selectedNames" -ForegroundColor Green
Write-Host "   Disabled: $disabledNames" -ForegroundColor DarkGray
Write-Host ""

& $cmd[0] $cmd[1..($cmd.Length - 1)]
exit $LASTEXITCODE
