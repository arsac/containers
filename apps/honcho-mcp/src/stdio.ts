#!/usr/bin/env node
/*
 * honcho-mcp — stdio entry point.
 * MODIFICATION NOTICE (AGPL-3.0 §5): addition by github.com/arsac/containers.
 * Upstream Honcho MCP (github.com/plastic-labs/honcho mcp/, AGPL-3.0) ships a
 * Cloudflare Worker entry (src/index.ts); that entry is removed and replaced by
 * this stdio transport for self-hosted use. Corresponding Source: this repo.
 */
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createClient, type HonchoConfig } from "./config.js";
import { createServer } from "./server.js";

const baseUrl = process.env.HONCHO_API_URL?.trim();
if (!baseUrl) {
  process.stderr.write(
    "FATAL: HONCHO_API_URL is required (e.g. http://honcho.<ns>.svc.cluster.local:8000). Refusing to start.\n",
  );
  process.exit(1);
}
const workspaceId = process.env.HONCHO_WORKSPACE_ID?.trim();
if (!workspaceId) {
  process.stderr.write("FATAL: HONCHO_WORKSPACE_ID is required. Refusing to start.\n");
  process.exit(1);
}
const config: HonchoConfig = {
  apiKey: process.env.HONCHO_API_KEY ?? "",
  baseUrl,
  workspaceId,
  userName: process.env.HONCHO_USER_NAME ?? "User",
  assistantName: process.env.HONCHO_ASSISTANT_NAME ?? "Assistant",
};
const honcho = createClient(config);
if (process.env.HONCHO_SKIP_PREFLIGHT !== "1") {
  const attempts = 5;
  let lastErr: unknown;
  for (let i = 1; i <= attempts; i++) {
    try {
      await honcho.getMetadata();
      lastErr = undefined;
      break;
    } catch (e) {
      lastErr = e;
      if (i < attempts) await new Promise((r) => setTimeout(r, 2000));
    }
  }
  if (lastErr !== undefined) {
    process.stderr.write(
      `FATAL: cannot reach Honcho at ${baseUrl} after ${attempts} attempts: ${lastErr instanceof Error ? lastErr.message : String(lastErr)}\n`,
    );
    process.exit(1);
  }
}
const server = createServer({ honcho, config });
await server.connect(new StdioServerTransport());
