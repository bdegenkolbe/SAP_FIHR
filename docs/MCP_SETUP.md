# MCP-Anbindung

Der Server `sapfhir.mcp.server` spricht MCP über **stdio**, ohne Netz-Egress.

## Claude Desktop (PC-A, user-scope)
`%APPDATA%\Claude\claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "sapfhir": {
      "command": "%LOCALAPPDATA%\\greenbay\\sapfhir\\.venv\\Scripts\\python.exe",
      "args": ["-m", "sapfhir.mcp.server"],
      "cwd": "%LOCALAPPDATA%\\greenbay\\sapfhir"
    }
  }
}
```

## LibreChat via Supergateway (PC-A)
Wie die übrigen sieben MCP-Server: Supergateway bridgt stdio→SSE. Beispiel-Kommando:
```
npx -y supergateway --stdio "python -m sapfhir.mcp.server" --port 8790
```
LibreChat `librechat.yaml` → `mcpServers.sapfhir.url: http://127.0.0.1:8790/sse`.

## Vor jedem Rollout
Skill `windows-infra-preflight` ausführen — PC-A vs. PC-B unterscheiden
(Profil `BjörnDegenko_ii5jj9a` / `BJRNDE~2`, LibreChat `C:\ai\LibreChat`, Docker läuft).
`C:\ai\_ops\machine.json` lesen statt raten.

## Datenschutzentscheidung (offen)
Claude Desktop nutzt Anthropic-Endpunkte — nur mit freigegebener AVV/Konzern-Policy.
Andernfalls LibreChat + lokales Modell. Diese Wahl steht vor Produktivnutzung an
(siehe docs/CONCEPT.md §20). Der MCP-Server selbst gibt keine Daten nach außen; die
Datenweitergabe entsteht erst durch das gewählte LLM-Frontend.
