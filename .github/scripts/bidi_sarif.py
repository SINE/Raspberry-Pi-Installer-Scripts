#!/usr/bin/env python3
"""
Trojan Source / BiDi SARIF generator.

Usage: bidi_sarif.py <hits_newline_separated>

Reads a newline-separated list of file paths (from grep -rPl) passed as the
first positional argument and writes a SARIF 2.1.0 file to
/tmp/sarif/trojan-source.sarif.  Exits with code 1 if any hits are found.
"""
import json, sys

hits_raw = sys.argv[1].strip() if len(sys.argv) > 1 else ""
hits = [h for h in hits_raw.splitlines() if h.strip()] if hits_raw else []

results = []
for filepath in hits:
    rel = filepath.lstrip("./")
    results.append({
        "ruleId": "trojan-source/bidi-control-char",
        "level": "error",
        "message": {
            "text": (
                f"Trojan Source: Unicode BiDi control character detected in '{rel}'. "
                "These characters can make malicious code appear visually benign. "
                "Reference: https://trojansource.codes/ -- CVE-2021-42574"
            )
        },
        "locations": [{
            "physicalLocation": {
                "artifactLocation": {"uri": rel, "uriBaseId": "%SRCROOT%"},
                "region": {"startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 1}
            }
        }]
    })

sarif = {
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [{
        "tool": {
            "driver": {
                "name": "trojan-source",
                "version": "1.0.0",
                "informationUri": "https://trojansource.codes/",
                "rules": [{
                    "id": "trojan-source/bidi-control-char",
                    "name": "BidiControlCharacter",
                    "shortDescription": {"text": "Unicode BiDi control character (Trojan Source, CVE-2021-42574)"},
                    "fullDescription": {"text": (
                        "Unicode bidirectional control characters (U+200B, U+200E, U+200F, "
                        "U+202A-U+202E, U+2066-U+2069, U+FEFF, U+00AD) can reorder displayed "
                        "text so that malicious code appears visually harmless. This is the "
                        "Trojan Source attack (CVE-2021-42574)."
                    )},
                    "defaultConfiguration": {"level": "error"},
                    "help": {
                        "text": "Remove the BiDi control character. Reference: https://trojansource.codes/",
                        "markdown": (
                            "Remove the BiDi control character. "
                            "See [trojansource.codes](https://trojansource.codes/) and "
                            "[CVE-2021-42574](https://nvd.nist.gov/vuln/detail/CVE-2021-42574)."
                        )
                    },
                    "properties": {
                        "tags": ["security", "supply-chain"],
                        "precision": "very-high",
                        "security-severity": "8.0"
                    }
                }]
            }
        },
        "results": results
    }]
}

out = "/tmp/sarif/trojan-source.sarif"
with open(out, "w") as f:
    json.dump(sarif, f, indent=2)

if hits:
    print(f"::error::Trojan Source BiDi control characters detected in {len(hits)} file(s).")
    for h in hits:
        print(f"  {h}")
    print("Reference: https://trojansource.codes/ -- CVE-2021-42574")
    sys.exit(1)
else:
    print("No BiDi characters detected.")
