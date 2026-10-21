#!/usr/bin/env node
// Create first-install credentials without putting secrets in argv or Git.
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";

const namespace = "cliproxyapi";
const kubectl = (args, input) =>
  execFileSync("kubectl", args, { encoding: "utf8", input });
const existing = kubectl([
  "-n",
  namespace,
  "get",
  "secret",
  "cliproxyapi-bootstrap",
  "--ignore-not-found",
  "-o",
  "name",
]);
if (existing.trim()) {
  console.log("Bootstrap Secret already exists; credentials preserved.");
  process.exit(0);
}

const managementKey = randomBytes(32).toString("hex");
const clientKey = randomBytes(32).toString("hex");
const config = readFileSync(
  new URL("../argocd/cliproxyapi/config.example", import.meta.url),
  "utf8",
)
  .replace("REPLACE_MANAGEMENT_KEY", managementKey)
  .replace("REPLACE_CLIENT_KEY", clientKey);

kubectl(
  ["apply", "--server-side", "-f", "-"],
  JSON.stringify({
    apiVersion: "v1",
    kind: "Namespace",
    metadata: { name: namespace },
  }),
);
kubectl(
  ["create", "-f", "-"],
  JSON.stringify({
    apiVersion: "v1",
    kind: "Secret",
    metadata: { name: "cliproxyapi-bootstrap", namespace },
    type: "Opaque",
    stringData: {
      "config.yaml": config,
      "management-key": managementKey,
      "client-key": clientKey,
      "keeper-password": randomBytes(24).toString("base64url"),
    },
  }),
);
console.log("Bootstrap Secret created; values remain in Kubernetes.");
