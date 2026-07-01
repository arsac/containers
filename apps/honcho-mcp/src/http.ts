#!/usr/bin/env node
/*
 * honcho-mcp — stateless Streamable HTTP entry point.
 * MODIFICATION NOTICE (AGPL-3.0 §5): addition by github.com/arsac/containers.
 * Upstream Honcho MCP (github.com/plastic-labs/honcho mcp/, AGPL-3.0) ships a
 * Cloudflare Worker entry (src/index.ts); that entry is removed and replaced by
 * this Node Streamable HTTP transport for self-hosted use behind ToolHive.
 * Corresponding Source: this repo.
 */
import { createServer as createHttpServer } from "node:http";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createClient, type HonchoConfig } from "./config.js";
import { createServer } from "./server.js";

// Fail closed: refuse to start on a missing required var rather than silently
// mis-target or co-mingle memory.
function required(name: string, hint = ""): string {
  const value = process.env[name]?.trim();
  if (!value) {
    process.stderr.write(`FATAL: ${name} is required${hint ? ` (${hint})` : ""}. Refusing to start.\n`);
    process.exit(1);
  }
  return value;
}

const baseUrl = required("HONCHO_API_URL", "e.g. http://honcho.<ns>.svc.cluster.local:8000");
const workspaceId = required("HONCHO_WORKSPACE_ID");
const config: HonchoConfig = {
  apiKey: process.env.HONCHO_API_KEY ?? "",
  baseUrl,
  workspaceId,
  userName: process.env.HONCHO_USER_NAME ?? "User",
  assistantName: process.env.HONCHO_ASSISTANT_NAME ?? "Assistant",
};
const port = Number(process.env.PORT ?? "8080");

// One shared Honcho client — a stateless fetch-based HTTP client, safe to use
// across concurrent requests. Startup is NOT gated on Honcho reachability
// (canonical cloud-native: no dependency-ordering, no crash loop on a transient
// backing-service outage); a Honcho outage surfaces as tool-call errors and
// self-recovers. Config errors still fail fast above.
const honcho = createClient(config);

const httpServer = createHttpServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain" }).end("ok");
    return;
  }
  if (req.url !== "/mcp") {
    res.writeHead(404).end();
    return;
  }
  if (req.method !== "POST") {
    // Stateless: no server->client SSE stream and no session to delete, so
    // GET/DELETE on /mcp are not supported.
    res.writeHead(405, { Allow: "POST" }).end();
    return;
  }

  // Stateless MCP: a fresh server + transport per request fully isolates
  // concurrent clients (no shared session state, no request-id collisions).
  // The transport reads/validates the request body itself and, with
  // enableJsonResponse, replies with a single JSON response (no SSE).
  const server = createServer({ honcho, config });
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  try {
    await server.connect(transport);
    await transport.handleRequest(req, res);
  } catch (e) {
    process.stderr.write(`error handling MCP request: ${e instanceof Error ? e.message : String(e)}\n`);
    if (!res.headersSent) {
      res
        .writeHead(500, { "Content-Type": "application/json" })
        .end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32603, message: "Internal server error" } }));
    }
  }
});

httpServer.listen(port, "0.0.0.0", () => {
  process.stderr.write(`honcho-mcp streamable-http listening on 0.0.0.0:${port} (workspace ${workspaceId})\n`);
});
