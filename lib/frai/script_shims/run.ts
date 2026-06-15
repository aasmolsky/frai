// Frai internal shim — do not edit in user projects.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const scriptPath = path.resolve(process.argv[2] ?? "");
const { input } = JSON.parse(fs.readFileSync(0, "utf8"));

const mod = await import(pathToFileURL(scriptPath).href);
const callFn = typeof mod.call === "function" ? mod.call : mod.default?.call;

if (typeof callFn !== "function") {
  console.error(`Script must export call(input): ${scriptPath}`);
  process.exit(1);
}

const result = await callFn(input);
process.stdout.write(JSON.stringify(result));
