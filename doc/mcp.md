# MCP server

[Documentation](README.md) › MCP server

`atlas mcp` makes an API usable by AI agents (Claude, Cursor, …) through the [Model Context Protocol](https://modelcontextprotocol.io): each operation becomes a tool the agent can call, authenticated with the profile. The credentials stay with atlas; the agent sees the tools and the responses.

```sh
# Claude Code
claude mcp add exo -- atlas mcp exo
```

```json
{"mcpServers": {"exo": {"command": "atlas", "args": ["mcp", "exo"]}}}
```

The second form is the configuration file of Claude Desktop and most other clients. Give the full path of `atlas` if the client doesn't search your `PATH`.

**Which operations.** By default, the read-only ones: GET, HEAD and OPTIONS. `--allow-writes` offers them all. A profile's `mcp.operations` lists exactly the operations to offer, writes included, by name or with `*` for any text:

```json
{"profiles": {"exo": {"schema": "https://api.example.com/openapi.json",
                      "mcp": {"operations": ["list-*", "get-instance", "start-instance"]}}}}
```

An unknown name, or a pattern that matches no operation, stops `atlas mcp` with an error.

Offer as few as the task needs: every tool's description and schema goes into the agent's context, and above 100 tools atlas warns. A large API (GitHub's read-only operations alone take about 900 KB) needs a list.

**Tools.** A tool is named like the operation in `atlas op` (`list-instances`). Its arguments are the path, query and header parameters, by name, and the request body as `body`; a name that two parameters share takes their location as prefix (`query.id`). Headers and query parameters the profile or its authentication adds are not arguments. The input schema is the spec's, in JSON Schema 2020-12 (OpenAPI 3.0's `nullable` and boolean `exclusiveMinimum`/`exclusiveMaximum` converted; recursive schemas as `$defs`), without the body's read-only properties. Annotations say which tools only read (`readOnlyHint`), and which may destroy (DELETE, PUT, PATCH) or are idempotent.

**Calls.** atlas checks the arguments before sending anything: required ones, parameter values and the body against their schemas. A JSON body that isn't an object or array (a string, a number) is sent as JSON. The result is the response body: JSON, or text. A 4xx or 5xx response, a network error or wrong arguments come back as a tool error with the status and body, so the agent can correct itself. Profile headers, retries, pagination and `-v` (on stderr) apply as for `atlas op`.

**Workflows.** `--arazzo=NAME` adds the workflows of an Arazzo context or file as tools named `workflow.WORKFLOW-ID`, with the workflow's inputs as arguments. They run with the context's profile, else the profile `atlas mcp` names, and return the workflow's outputs. `atlas mcp --arazzo=NAME` without a profile offers the workflows alone. They are offered whatever they do: list them in the context only if the agent may run them.

**Protocol.** atlas speaks MCP 2026-07-28, without sessions, and the earlier versions that open with `initialize` (2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05), over stdio. It reads one JSON-RPC message (or batch) per line on stdin and writes the answers on stdout; logs go to stderr. It stops when stdin closes. External auth tools and the browser of OAuth flows never share its stdin or stdout.

## Options

| Option | Description |
|--------|-------------|
| `--allow-writes` | Offer every operation, not only GET, HEAD and OPTIONS |
| `--arazzo=NAME` | Also offer the workflows of an Arazzo context or file |

`mcp` also takes `-v`, `--timeout`, the retry options, `--max-pages`, `--no-paginate`, `--base-url`, `--server-index`, `--server.`, `--ssl.`, `--reload` and `--cache-ttl` as above.
