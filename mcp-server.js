#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = process.env.MAILU_ROOT || path.resolve(__dirname);

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ValidationError";
  }
}

const MAILU_SERVICES = new Set([
  "redis",
  "front",
  "admin",
  "imap",
  "smtp",
  "oletools",
  "antispam",
  "webmail",
]);

const TOOLS = [
  {
    name: "mailu_status",
    description: "Show Docker Compose status for the Mailu stack.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "mailu_logs",
    description: "Read recent logs from one Mailu service or all services.",
    inputSchema: {
      type: "object",
      properties: {
        service: {
          type: "string",
          description: "Optional Mailu service name such as front, admin, smtp, imap, antispam, webmail, or redis.",
        },
        lines: {
          type: "number",
          description: "How many recent lines to return. Default: 100",
        },
      },
    },
  },
  {
    name: "mailu_endpoints",
    description: "Return the admin, webmail, API, and direct mail endpoints derived from the Mailu env file.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "mailu_domain_add",
    description: "Add a hosted mail domain to Mailu.",
    inputSchema: {
      type: "object",
      properties: {
        domain: { type: "string", description: "Domain to add, for example example.com" },
      },
      required: ["domain"],
    },
  },
  {
    name: "mailu_user_add",
    description: "Create a mailbox user in Mailu.",
    inputSchema: {
      type: "object",
      properties: {
        email: { type: "string", description: "Mailbox email address" },
        password: { type: "string", description: "Mailbox password" },
      },
      required: ["email", "password"],
    },
  },
  {
    name: "mailu_user_delete",
    description: "Disable or remove a mailbox user.",
    inputSchema: {
      type: "object",
      properties: {
        email: { type: "string", description: "Mailbox email address" },
        purge: {
          type: "boolean",
          description: "When true, pass -r to actually remove the user after mailbox data has been handled.",
        },
      },
      required: ["email"],
    },
  },
  {
    name: "mailu_password_set",
    description: "Change a mailbox password.",
    inputSchema: {
      type: "object",
      properties: {
        email: { type: "string", description: "Mailbox email address" },
        password: { type: "string", description: "New password" },
      },
      required: ["email", "password"],
    },
  },
  {
    name: "mailu_alias_add",
    description: "Create an alias that forwards to one or more destination addresses.",
    inputSchema: {
      type: "object",
      properties: {
        alias_email: { type: "string", description: "Alias address such as sales@example.com" },
        destinations: {
          type: "array",
          items: { type: "string" },
          description: "Destination email addresses",
        },
      },
      required: ["alias_email", "destinations"],
    },
  },
  {
    name: "mailu_alias_delete",
    description: "Delete an alias address.",
    inputSchema: {
      type: "object",
      properties: {
        alias_email: { type: "string", description: "Alias address to delete" },
      },
      required: ["alias_email"],
    },
  },
  {
    name: "mailu_config_export",
    description: "Export Mailu configuration through the official CLI, optionally including DNS data.",
    inputSchema: {
      type: "object",
      properties: {
        json: { type: "boolean", description: "Return JSON instead of YAML" },
        dns: { type: "boolean", description: "Include DNS records such as MX, SPF, DKIM, and DMARC" },
        full: { type: "boolean", description: "Include default values" },
        secrets: { type: "boolean", description: "Include plain-text secrets" },
        filters: {
          type: "array",
          items: { type: "string" },
          description: "Optional Mailu export filters such as domain.dns_mx or user.email",
        },
      },
    },
  },
];

function parseEnv() {
  const envPath = path.join(ROOT, ".env");
  const values = {};
  if (!fs.existsSync(envPath)) {
    return values;
  }

  for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
    if (!line || line.trim().startsWith("#")) {
      continue;
    }
    const index = line.indexOf("=");
    if (index === -1) {
      continue;
    }
    const key = line.slice(0, index).trim();
    const value = line.slice(index + 1).trim();
    values[key] = value;
  }
  return values;
}

function runDocker(args, timeout = 30000) {
  return execFileSync("docker", args, {
    cwd: ROOT,
    encoding: "utf8",
    timeout,
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

function runCompose(args, timeout = 30000) {
  return runDocker(["compose", "--env-file", ".env", ...args], timeout);
}

function parseEmail(email) {
  const index = email.indexOf("@");
  if (index <= 0 || index === email.length - 1) {
    throw new Error(`Invalid email address: ${email}`);
  }
  return {
    localpart: email.slice(0, index),
    domain: email.slice(index + 1),
  };
}

function text(value) {
  return { type: "text", text: value };
}

function endpointsText() {
  const env = parseEnv();
  const hostnames = (env.HOSTNAMES || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  const webHost = hostnames.find((entry) => entry !== env.PRIMARY_HOSTNAME) || env.PRIMARY_HOSTNAME || "mail.example.com";
  const adminPath = env.WEB_ADMIN || "/admin";
  const webmailPath = env.WEB_WEBMAIL || "/webmail";
  const apiPath = env.WEB_API || "/api";
  const payload = {
    primaryHostname: env.PRIMARY_HOSTNAME || null,
    publicMailHost: env.PRIMARY_HOSTNAME || null,
    tunnelWebHost: webHost || null,
    adminUrl: webHost ? `https://${webHost}${adminPath}` : null,
    webmailUrl: webHost ? `https://${webHost}${webmailPath}` : null,
    apiUrl: webHost ? `https://${webHost}${apiPath}` : null,
    localAdminUrl: `http://localhost:${env.HTTP_PORT || 8080}${adminPath}`,
    localWebmailUrl: `http://localhost:${env.HTTP_PORT || 8080}${webmailPath}`,
    localApiUrl: `http://localhost:${env.HTTP_PORT || 8080}${apiPath}`,
    imap: {
      host: env.PRIMARY_HOSTNAME || null,
      port: Number(env.IMAPS_PORT || 993),
      security: "SSL/TLS",
    },
    smtpSubmission: {
      host: env.PRIMARY_HOSTNAME || null,
      port: Number(env.SUBMISSION_PORT || 587),
      security: "STARTTLS",
    },
  };
  return JSON.stringify(payload, null, 2);
}

function handleTool(name, args) {
  switch (name) {
    case "mailu_status":
      return text(runCompose(["ps"]));

    case "mailu_logs": {
      const requestedLines = Number(args.lines);
      const lines = Number.isFinite(requestedLines) && requestedLines > 0
        ? String(Math.min(Math.trunc(requestedLines), 5000))
        : "100";
      const command = ["logs", "--tail", lines];
      if (args.service !== undefined && args.service !== null && args.service !== "") {
        if (typeof args.service !== "string" || !MAILU_SERVICES.has(args.service)) {
          throw new ValidationError(
            `Unknown Mailu service. Allowed: ${[...MAILU_SERVICES].join(", ")}`,
          );
        }
        command.push(args.service);
      }
      return text(runCompose(command, 60000));
    }

    case "mailu_endpoints":
      return text(endpointsText());

    case "mailu_domain_add":
      return text(runCompose(["exec", "-T", "admin", "flask", "mailu", "domain", args.domain], 60000));

    case "mailu_user_add": {
      const { localpart, domain } = parseEmail(args.email);
      return text(
        runCompose(
          ["exec", "-T", "admin", "flask", "mailu", "user", localpart, domain, args.password],
          60000,
        ),
      );
    }

    case "mailu_user_delete": {
      const command = ["exec", "-T", "admin", "flask", "mailu", "user-delete"];
      if (args.purge) {
        command.push("-r");
      }
      command.push(args.email);
      return text(runCompose(command, 60000));
    }

    case "mailu_password_set": {
      const { localpart, domain } = parseEmail(args.email);
      return text(
        runCompose(
          ["exec", "-T", "admin", "flask", "mailu", "password", localpart, domain, args.password],
          60000,
        ),
      );
    }

    case "mailu_alias_add": {
      if (!Array.isArray(args.destinations) || args.destinations.length === 0) {
        throw new Error("destinations must be a non-empty array");
      }
      const { localpart, domain } = parseEmail(args.alias_email);
      return text(
        runCompose(
          [
            "exec",
            "-T",
            "admin",
            "flask",
            "mailu",
            "alias",
            localpart,
            domain,
            args.destinations.join(","),
          ],
          60000,
        ),
      );
    }

    case "mailu_alias_delete":
      return text(runCompose(["exec", "-T", "admin", "flask", "mailu", "alias-delete", args.alias_email], 60000));

    case "mailu_config_export": {
      const command = ["exec", "-T", "admin", "flask", "mailu", "config-export"];
      if (args.full) {
        command.push("--full");
      }
      if (args.secrets) {
        command.push("--secrets");
      }
      if (args.dns) {
        command.push("--dns");
      }
      if (args.json) {
        command.push("--json");
      }
      if (Array.isArray(args.filters)) {
        const filterPattern = /^(domain|user|alias|relay|config)(\.[a-z_]+)*$/;
        for (const filter of args.filters) {
          if (typeof filter !== "string" || !filterPattern.test(filter)) {
            throw new ValidationError(`Rejected filter: must match ${filterPattern}`);
          }
          command.push(filter);
        }
      }
      return text(runCompose(command, 60000));
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

function send(message) {
  const body = JSON.stringify(message);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
}

function handleMessage(message) {
  const { id, method, params } = message;

  switch (method) {
    case "initialize":
      send({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "mailu-mcp", version: "1.0.0" },
        },
      });
      return;

    case "notifications/initialized":
      return;

    case "tools/list":
      send({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
      return;

    case "tools/call":
      try {
        const result = handleTool(params.name, params.arguments || {});
        send({ jsonrpc: "2.0", id, result: { content: [result] } });
      } catch (error) {
        const errorId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
        process.stderr.write(`[mcp-server] tool ${params.name} failed (${errorId}): ${error.stack || error.message}\n`);
        const clientMessage = error instanceof ValidationError
          ? `Invalid input: ${error.message}`
          : `Tool '${params.name}' failed. Error id: ${errorId}. See server logs for details.`;
        send({
          jsonrpc: "2.0",
          id,
          result: {
            content: [text(clientMessage)],
            isError: true,
          },
        });
      }
      return;

    default:
      if (id) {
        send({
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: `Method not found: ${method}` },
        });
      }
  }
}

let buffer = "";
process.stdin.on("data", (chunk) => {
  buffer += chunk.toString();

  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) {
      break;
    }

    const header = buffer.slice(0, headerEnd);
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }

    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + length) {
      break;
    }

    const body = buffer.slice(bodyStart, bodyStart + length);
    buffer = buffer.slice(bodyStart + length);

    try {
      handleMessage(JSON.parse(body));
    } catch (error) {
      process.stderr.write(`Parse error: ${error.message}\n`);
    }
  }
});

process.stderr.write(`Mailu MCP server ready for ${ROOT}\n`);
