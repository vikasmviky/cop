#!/bin/bash
# cop - Copilot launcher with selective MCP loading
# Usage: cop -m webex,agilestudio,ms365 [other copilot args...]
# Add to shell: alias cop='/path/to/cop.sh'

MCP_CONFIG="$HOME/.copilot/mcp-config.json"
PROJECT_MCP_FILES=(".mcp.json" ".github/mcp.json" ".github/mcp.local.json")

# Parse arguments
REQUESTED_MCPS=""
DISABLE_BUILTIN=false
LIST_MCPS=false
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      REQUESTED_MCPS="$2"
      shift 2
      ;;
    -dibm)
      DISABLE_BUILTIN=true
      shift
      ;;
    -listmcps)
      LIST_MCPS=true
      shift
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

# List available MCPs and exit
if [[ "$LIST_MCPS" == true ]]; then
  python3 -c "
import json, glob, os

mcp_config = os.path.expanduser('$MCP_CONFIG')

print('Available MCPs:')
print('')

# From global config
with open(mcp_config) as f:
    config = json.load(f)
servers = config.get('mcpServers', config)
if servers:
    print('  Global (~/.copilot/mcp-config.json):')
    for k in servers:
        print(f'    • {k}')

# From plugins
plugin_mcps = {}
for mcp_file in glob.glob(os.path.expanduser('~/.copilot/installed-plugins/**/.mcp.json'), recursive=True):
    with open(mcp_file) as f:
        data = json.load(f)
    plugin_name = mcp_file.split('/installed-plugins/')[1].split('/')[0]
    for k in data.get('mcpServers', {}).keys():
        plugin_mcps[k] = plugin_name

if plugin_mcps:
    print('')
    print('  Plugins:')
    for k, plugin in plugin_mcps.items():
        print(f'    • {k}  (plugin: {plugin})')

# From project-level configs
project_mcps = {}
for f in ['.mcp.json', '.github/mcp.json', '.github/mcp.local.json']:
    if os.path.isfile(f):
        with open(f) as fh:
            data = json.load(fh)
        for k in data.get('mcpServers', {}).keys():
            project_mcps[k] = f

if project_mcps:
    print('')
    print(f'  Project ({os.getcwd()}):')
    for k, src in project_mcps.items():
        print(f'    • {k}  ({src})')

print('')
print('  Built-in:')
print('    • github-mcp-server  (use -dibm to disable)')
print('')
print('Usage: cop -m <name1>,<name2>  (fuzzy match supported)')
print('Flags: -m <mcps>  -dibm  -listmcps')
"
  exit 0
fi

# If no -m flag, disable all MCPs and launch copilot
if [[ -z "$REQUESTED_MCPS" ]]; then
  ALL_NAMES=$(python3 -c "
import json, glob, os

mcp_config = os.path.expanduser('$MCP_CONFIG')
names = set()

# From global config
with open(mcp_config) as f:
    config = json.load(f)
for k in config.get('mcpServers', config).keys():
    names.add(k)

# From plugins
for mcp_file in glob.glob(os.path.expanduser('~/.copilot/installed-plugins/**/.mcp.json'), recursive=True):
    with open(mcp_file) as f:
        data = json.load(f)
    for k in data.get('mcpServers', {}).keys():
        names.add(k)

# From project-level configs
for f in ['.mcp.json', '.github/mcp.json', '.github/mcp.local.json']:
    if os.path.isfile(f):
        with open(f) as fh:
            data = json.load(fh)
        for k in data.get('mcpServers', {}).keys():
            names.add(k)

print(' '.join(names))
")
  CMD=(copilot)
  if [[ "$DISABLE_BUILTIN" == true ]]; then
    CMD+=(--disable-builtin-mcps)
  fi
  for name in $ALL_NAMES; do
    CMD+=(--disable-mcp-server "$name")
  done
  CMD+=("${PASSTHROUGH_ARGS[@]}")
  echo "🚀 No MCPs loaded (all disabled)"
  echo ""
  exec "${CMD[@]}"
fi

# Use python3 to fuzzy-match names, compute disable list, and build JSON
RESULT=$(python3 -c "
import json, sys, glob, os

mcp_config = sys.argv[1]
requested_raw = sys.argv[2].split(',')

with open(mcp_config) as f:
    config = json.load(f)

servers = config.get('mcpServers', config)

# Also collect MCP servers from plugins
plugin_servers = {}
for mcp_file in glob.glob(os.path.expanduser('~/.copilot/installed-plugins/**/.mcp.json'), recursive=True):
    with open(mcp_file) as f:
        data = json.load(f)
    for k, v in data.get('mcpServers', {}).items():
        plugin_servers[k] = v

# Also collect from project-level configs
project_servers = {}
for f in ['.mcp.json', '.github/mcp.json', '.github/mcp.local.json']:
    if os.path.isfile(f):
        with open(f) as fh:
            data = json.load(fh)
        for k, v in data.get('mcpServers', {}).items():
            if k not in servers and k not in plugin_servers:
                project_servers[k] = v

# All server keys (global config + plugins + project)
all_keys = list(servers.keys()) + [k for k in plugin_servers if k not in servers] + [k for k in project_servers if k not in servers and k not in plugin_servers]

# Fuzzy match: find config key that contains the query (case-insensitive)
def find_match(query):
    query = query.strip().lower()
    # Try exact match first (case-insensitive)
    for key in all_keys:
        if key.lower() == query:
            return [key]
    # Then substring match - collect ALL matches
    matches = []
    for key in all_keys:
        if query in key.lower() or key.lower() in query:
            matches.append(key)
    return matches

resolved = {}
has_error = False
for raw in requested_raw:
    raw = raw.strip()
    if not raw:
        continue
    matches = find_match(raw)
    if len(matches) == 1:
        match = matches[0]
        # Get config from global, plugin, or project
        if match in servers:
            resolved[match] = servers[match]
        elif match in plugin_servers:
            resolved[match] = plugin_servers[match]
        elif match in project_servers:
            resolved[match] = project_servers[match]
    elif len(matches) > 1:
        matched_str = ', '.join(matches)
        print(f'⚠️  \"{raw}\" matches multiple servers: {matched_str}', file=sys.stderr)
        print(f'   Be more specific.', file=sys.stderr)
        has_error = True
    else:
        print(f'⚠️  No MCP matching \"{raw}\" in config', file=sys.stderr)
        has_error = True

if has_error:
    sys.exit(1)

# Servers to disable = all minus the ones we want
to_disable = [k for k in all_keys if k not in resolved]

output = {
    'disable': to_disable,
    'selected_names': list(resolved.keys()),
    'mcp_json': json.dumps({'mcpServers': resolved}, separators=(',', ':'))
}
print(json.dumps(output))
" "$MCP_CONFIG" "$REQUESTED_MCPS")

RC=$?
if [[ $RC -ne 0 ]]; then
  echo "❌ Aborting. Fix the MCP names and retry."
  exit 1
fi

# Parse python output
DISABLE_NAMES=$(echo "$RESULT" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['disable']))")
SELECTED_NAMES=$(echo "$RESULT" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['selected_names']))")
MCP_JSON=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['mcp_json'])")

# Build copilot command
CMD=(copilot)

# Disable built-in MCPs if requested
if [[ "$DISABLE_BUILTIN" == true ]]; then
  CMD+=(--disable-builtin-mcps)
fi

# Add --disable-mcp-server for each server not requested
for name in $DISABLE_NAMES; do
  CMD+=(--disable-mcp-server "$name")
done

# Add the selected MCPs as additional config
if [[ "$MCP_JSON" != '{"mcpServers":{}}' ]]; then
  CMD+=(--additional-mcp-config "$MCP_JSON")
fi

# Pass through remaining args
CMD+=("${PASSTHROUGH_ARGS[@]}")

# Show what's being launched
echo "🚀 Loading MCPs: $SELECTED_NAMES"
echo "   Disabled: $DISABLE_NAMES"
echo ""

exec "${CMD[@]}"
