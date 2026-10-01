// Evaluates polkit .rules files the way polkitd does, without polkitd:
// each file's polkit.addRule() functions run in file-name order, the first
// that returns a result wins, otherwise the action's <defaults> from the
// .policy file decide (allow_active for a local active subject,
// allow_inactive for a local inactive one, allow_any otherwise).
//
//   node polkit-rules.js POLICY RULES_DIR...  < queries
//
// Each query line: "<action id> <local 0|1> <active 0|1> <groups,comma>".
// Prints one line per query: "<action id> <result>". The rules see
// action.id, subject.local, subject.active, subject.user and
// subject.isInGroup(); polkit.spawn is not provided (no rule may need it
// yet). Used by tests/pkgs/sys.sh; polkitd itself runs only on a real
// machine (Janus checks there).
"use strict";
const fs = require("fs");
const path = require("path");

const [policyFile, ...ruleDirs] = process.argv.slice(2);
const xml = fs.readFileSync(policyFile, "utf8");
const defaults = {};
for (const m of xml.matchAll(/<action id="([^"]+)">([\s\S]*?)<\/action>/g)) {
  const body = m[2];
  const get = (tag) => (body.match(new RegExp(`<${tag}>([^<]*)</${tag}>`)) || [])[1];
  defaults[m[1]] = { any: get("allow_any"), inactive: get("allow_inactive"), active: get("allow_active") };
}

const rules = [];
const polkit = {
  Result: { YES: "yes", NO: "no", AUTH_SELF: "auth_self", AUTH_SELF_KEEP: "auth_self_keep",
            AUTH_ADMIN: "auth_admin", AUTH_ADMIN_KEEP: "auth_admin_keep", NOT_HANDLED: null },
  addRule(f) { rules.push(f); },
  addAdminRule() {},
  log() {},
  spawn() { throw new Error("polkit.spawn is not available in this harness"); },
};
const files = ruleDirs.flatMap((d) => fs.existsSync(d)
  ? fs.readdirSync(d).filter((f) => f.endsWith(".rules")).map((f) => path.join(d, f)) : []);
files.sort((a, b) => path.basename(a).localeCompare(path.basename(b)));
for (const f of files) {
  new Function("polkit", fs.readFileSync(f, "utf8"))(polkit);
}

const input = fs.readFileSync(0, "utf8").split("\n").filter((l) => l.trim());
for (const line of input) {
  const [id, local, active, groups] = line.trim().split(/\s+/);
  const g = (groups || "").split(",").filter(Boolean);
  const action = { id, lookup() { return undefined; } };
  const subject = { local: local === "1", active: active === "1", user: "person",
                    isInGroup: (x) => g.includes(x), isInNetGroup: () => false };
  let result = null;
  for (const r of rules) {
    const v = r(action, subject);
    if (v !== undefined && v !== null) { result = v; break; }
  }
  if (result === null) {
    const d = defaults[id];
    if (!d) result = "no-such-action";
    else if (subject.local && subject.active) result = d.active;
    else if (subject.local) result = d.inactive;
    else result = d.any;
  }
  console.log(`${id} ${result}`);
}
