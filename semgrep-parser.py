#!/usr/bin/env python3
"""
Semgrep-Parser
--------------
Parses a Semgrep SARIF report and prints a readable, severity-tagged summary
of findings grouped by source file.

For each finding it resolves the rule metadata (description, CWE / OWASP tags,
and severity) from the SARIF rule definitions and prints it alongside the
affected file, line range, and the matching code snippet.

Severity note: Semgrep leaves 'level' null on individual results and stores the
real severity on the rule under 'defaultConfiguration.level'. This script reads
the result level first and falls back to the rule definition.

Colour output is enabled automatically when printing to a terminal and stripped
when the output is redirected to a file.

Requires only the Python standard library (offline / airgap friendly).

Usage:
    python3 sarif2text.py results.sarif              # coloured, to screen
    python3 sarif2text.py results.sarif > report.txt # plain text, to file

Author: anon
"""
import json, sys
from collections import defaultdict

BANNER = r"""
 ___                                  ___
/ __| ___ _ __  __ _ _ _ ___ _ __ ___| _ \__ _ _ _ ___ ___ _ _
\__ \/ -_) '  \/ _` | '_/ -_) '_ \___|  _/ _` | '_(_-</ -_) '_|
|___/\___|_|_|_\__, |_| \___| .__/   |_| \__,_|_| /__/\___|_|
               |___/        |_|
"""

sevmap = {"error": "ERROR", "warning": "WARNING", "note": "INFO", "none": "INFO", "": "UNKNOWN"}
colors = {"ERROR": "\033[91m", "WARNING": "\033[93m", "INFO": "\033[96m", "UNKNOWN": "\033[90m"}
reset = "\033[0m"
if not sys.stdout.isatty():          # strip colours when piped to a file
    colors, reset = {}, ""

print(BANNER)

data = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "results.sarif"))
for run in data["runs"]:
    rules = {rule["id"]: rule for rule in run["tool"]["driver"].get("rules", [])}
    by_file = defaultdict(list)
    for r in run.get("results", []):
        loc = r["locations"][0]["physicalLocation"]
        reg = loc.get("region", {})
        rule = rules.get(r.get("ruleId", ""), {})
        lvl = r.get("level") or rule.get("defaultConfiguration", {}).get("level", "")
        s, e = reg.get("startLine", 0), reg.get("endLine", 0)
        by_file[loc["artifactLocation"]["uri"]].append({
            "line": s,
            "rng": "%s-%s" % (s, e) if s != e else str(s),
            "sev": sevmap.get(lvl, (lvl or "").upper()),
            "rule": r.get("ruleId", "").split(".")[-1],
            "desc": rule.get("fullDescription", {}).get("text", ""),
            "tags": [t for t in rule.get("properties", {}).get("tags", []) if "CWE" in t or "OWASP" in t],
            "snip": reg.get("snippet", {}).get("text", "").rstrip(),
        })
    for path in sorted(by_file):
        items = sorted(by_file[path], key=lambda x: x["line"])
        print("\n" + "=" * 70 + "\n%s  (%d finding(s))\n" % (path, len(items)) + "=" * 70)
        for x in items:
            c = colors.get(x["sev"], "")
            print("\n%s[%s]%s %s  (line %s)" % (c, x["sev"], reset, x["rule"], x["rng"]))
            if x["desc"]: print("  Description: " + x["desc"])
            for t in x["tags"]: print("  - " + t)
            if x["snip"]:
                print("  Code:")
                for ln in x["snip"].splitlines(): print("    | " + ln)

