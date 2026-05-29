# `cop` — Selective MCP Loader for GitHub Copilot CLI

A lightweight shell wrapper that launches GitHub Copilot CLI with **only the MCP servers you need** for a session, keeping token usage low and startup fast.

## Why?

MCP tool definitions are injected into the prompt context on every turn — even if you never call them. Loading all MCP servers means thousands of tokens consumed before you even ask a question. This wrapper lets you pick only what you need per session.

## Prerequisites

- **GitHub Copilot CLI** (`copilot`) installed and authenticated
- **Python 3** (used for JSON parsing and fuzzy matching)
- **MCP servers configured** in `~/.copilot/mcp-config.json` and/or via installed plugins

## Installation

### macOS / Linux

```bash
# Copy to a directory in your PATH
sudo cp cop.sh /usr/local/bin/cop
sudo chmod +x /usr/local/bin/cop
```

Or without sudo (user-local):
```bash
cp cop.sh ~/.local/bin/cop
chmod +x ~/.local/bin/cop
# Ensure ~/.local/bin is in your PATH
```

### Windows (PowerShell)

```powershell
# Copy to a folder in your PATH
Copy-Item cop.ps1 C:\Tools\cop.ps1

# Add to PATH (one-time, restart terminal after)
[Environment]::SetEnvironmentVariable("PATH", "$env:PATH;C:\Tools", "User")
```

### Alternative: Use an alias

If you prefer not to modify PATH:

**macOS/Linux** — add to `~/.zshrc` or `~/.bashrc`:
```bash
alias cop='/path/to/cop.sh'
```

**Windows** — add to `$PROFILE`:
```powershell
function cop { & "C:\path\to\cop.ps1" @args }
```

## Usage

```bash
# List all available MCPs
cop -listmcps

# Launch with specific MCPs only
cop -m webex,ms365,agile

# Launch with no MCPs at all (minimal token usage)
cop

# Disable built-in github-mcp-server too
cop -m webex -dibm

# No MCPs and no built-in
cop -dibm

# Pass any other copilot flags as normal
cop -m webex --model claude-sonnet-4.5

# Resume a session with specific MCPs
cop -m webex,ms365 --resume <session-id>
```

## Flags

| Flag | Description |
|------|-------------|
| `-m <names>` | Comma-separated MCP names to enable (fuzzy match) |
| `-dibm` | Also disable built-in MCPs (github-mcp-server) |
| `-listmcps` | List all available MCPs and exit |
| _(any other)_ | Passed through to `copilot` as-is |

## Fuzzy Matching

You don't need to type the full MCP config key. The script matches by **substring** (case-insensitive):

| You type | Matches config key |
|----------|-------------------|
| `web` | webex-mcp |
| `agile` | agile-studio |
| `ms3` | ms365 |
| `graf` | grafana-mcp |
| `know` | knowledgehub |
| `inf` | infinity-rules-mcp |
| `open` | OpenAgile |
| `work` | workiq (plugin) |
| `khub` | khub-mcp (plugin) |

Full names also work: `cop -m webex-mcp,ms365`

## Behavior

| Scenario | What happens |
|----------|-------------|
| `cop -m web,ms3` | Only webex-mcp and ms365 load; all others disabled |
| `cop` | **No MCPs load** — all globally configured and plugin MCPs are disabled |
| `cop -dibm` | No MCPs + built-in github-mcp-server also disabled |
| `cop -m bogus` | ❌ Aborts with error — copilot does not start |
| `cop -m web,bogus` | ❌ Aborts — if **any** name fails to match, session won't start |
| `cop -listmcps` | Shows all available MCPs grouped by source |

## MCP Sources

The script discovers MCPs from three locations:

1. **Global config:** `~/.copilot/mcp-config.json`
2. **Installed plugins:** `~/.copilot/installed-plugins/**/.mcp.json`
3. **Project-level** (from current directory where `cop` is invoked):
   - `.mcp.json`
   - `.github/mcp.json`
   - `.github/mcp.local.json`

Run `cop -listmcps` to see all discovered MCPs:

```
Available MCPs:

  Global (~/.copilot/mcp-config.json):
    • agile-studio
    • knowledgehub
    • OpenAgile
    • ms365
    • webex-mcp
    • infinity-rules-mcp
    • grafana-mcp

  Plugins:
    • workiq  (plugin: work-iq)
    • agile-studio  (plugin: cdh-dev-skills)
    • khub-mcp  (plugin: cdh-dev-skills)

  Project (/path/to/your/project):
    • my-project-mcp  (.mcp.json)

  Built-in:
    • github-mcp-server  (use -dibm to disable)
```

## How It Works

1. Reads `~/.copilot/mcp-config.json`, `~/.copilot/installed-plugins/**/.mcp.json`, and project-level configs (`.mcp.json`, `.github/mcp.json`, `.github/mcp.local.json`) to discover all configured MCP servers
2. Fuzzy-matches your `-m` input against server names
3. Disables all non-matching servers via `--disable-mcp-server` flags
4. Passes matching server configs inline via `--additional-mcp-config` JSON
5. Optionally disables built-in MCPs with `--disable-builtin-mcps` (via `-dibm`)
6. Forwards all other arguments to `copilot` as-is

## Configuration

The script reads from three standard Copilot locations:

**Global MCP config:**
```
~/.copilot/mcp-config.json
```

**Plugin MCP configs (auto-discovered):**
```
~/.copilot/installed-plugins/<plugin-name>/<name>/.mcp.json
```

**Project-level configs (from current directory):**
```
.mcp.json
.github/mcp.json
.github/mcp.local.json
```

Example `mcp-config.json` structure:

```json
{
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "/path/to/server",
      "args": ["--flag"],
      "env": { "API_KEY": "..." },
      "tools": ["*"]
    }
  }
}
```

No changes to config files are needed — the wrapper works non-destructively.

## Notes

- **Session resume:** MCP config is determined at launch time. When resuming a session, pass `-m` again with the same MCPs you want.
- **Adding new MCPs:** Just add them to `~/.copilot/mcp-config.json` or install a plugin — no script changes needed. Fuzzy matching picks them up automatically.
- **Plugins:** Installing a new Copilot plugin that includes `.mcp.json` will automatically be discovered by `cop -listmcps`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `⚠️ No MCP matching "x"` | Run `cop -listmcps` to see available names |
| `⚠️ matches multiple servers` | Be more specific (e.g., `webex` not `mcp`) |
| `python3: command not found` | Install Python 3 (`brew install python3`) |
| MCPs still loading | Ensure you're using `cop` not `copilot` directly |
| Built-in still loads | Add `-dibm` flag |

## Platform Support

| Platform | Script | Copilot Config path |
|----------|--------|-------------|
| macOS | `cop.sh` | `~/.copilot/` |
| Linux | `cop.sh` | `~/.copilot/` |
| Windows (WSL) | `cop.sh` | `~/.copilot/` |
| Windows (native) | `cop.ps1` | `%USERPROFILE%\.copilot\` |
