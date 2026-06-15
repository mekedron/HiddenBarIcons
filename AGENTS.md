# Browser Use

You can run and test anything in Chrome browser using `chrome-devtools` MCP server. NEVER use `claude-in-chrome` MCP — always use `chrome-devtools` MCP exclusively for all browser automation.

The `chrome-devtools` MCP is configured to attach to a long-lived Chrome on `http://127.0.0.1:9222` (see `.mcp.json`), so the same profile is shared across every Claude Code session and sub-agent. Before the first `chrome-devtools` tool call in a session, run `./scripts/start-chrome.sh` from the project root. It is idempotent — if the proper Chrome is already up it exits 0 with no side effects, so it is safe to run every time. If it reports that the profile is locked by an old Chrome instance, follow the `pkill` instruction it prints and re-run it.
