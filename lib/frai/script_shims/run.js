#!/usr/bin/env node
// Frai internal shim — do not edit in user projects.

const fs = require("fs");
const path = require("path");

const scriptPath = path.resolve(process.argv[2]);
const { input } = JSON.parse(fs.readFileSync(0, "utf8"));
const mod = require(scriptPath);

if (typeof mod.call !== "function") {
  console.error(`Script must export call(input): ${scriptPath}`);
  process.exit(1);
}

process.stdout.write(JSON.stringify(mod.call(input)));
