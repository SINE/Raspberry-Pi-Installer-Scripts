#!/usr/bin/env python3
"""
malcontent JSON -> SARIF 2.1.0 converter.

Usage: malcontent_sarif.py <src.json> <dst.sarif>

Understands the FileReport / Behavior schema from malcontent
(pkg/malcontent/malcontent.go):

  Top-level JSON: {"Files": {"<path>": <FileReport>}, ...}
  FileReport:     {Path, RiskScore, RiskLevel, Behaviors:[...], ...}
  Behavior:       {ID, RiskScore, RiskLevel, Description,
                   MatchStrings, RuleURL, ReferenceURL, ...}

RiskLevel -> SARIF level:
  CRITICAL -> error   (security-severity 9.5)
  HIGH     -> error   (security-severity 7.5)
  MEDIUM   -> warning (security-severity 5.0)
  LOW      -> note    (security-severity 2.0)
"""
import json, sys, hashlib

src, dst = sys.argv[1], sys.argv[2]

RISK_MAP = {
    "CRITICAL": ("error",   "9.5"),
    "HIGH":     ("error",   "7.5"),
    "MEDIUM":   ("warning", "5.0"),
    "LOW":      ("note",    "2.0"),
}

def risk_to_sarif_level(risk_level):
    return RISK_MAP.get((risk_level or "").upper(), ("note", "1.0"))

def behaviors_to_rules(all_behaviors):
    seen = {}
    for b in all_behaviors:
        bid = b.get("ID") or b.get("RuleName") or "unknown"
        if bid not in seen:
            level, sec_sev = risk_to_sarif_level(b.get("RiskLevel", ""))
            desc = b.get("Description") or bid
            rule_url = b.get("RuleURL") or b.get("ReferenceURL") or ""
            help_md = desc + (f"\n\nRule: [{rule_url}]({rule_url})" if rule_url else "")
            seen[bid] = {
                "id": bid,
                "name": bid.replace("/", "-").replace(".", "-"),
                "shortDescription": {"text": desc[:1024]},
                "fullDescription":  {"text": desc[:1024]},
                "defaultConfiguration": {"level": level},
                "help": {"text": desc[:1024], "markdown": help_md[:1024]},
                "properties": {
                    "tags": ["security", "supply-chain"],
                    "precision": "high",
                    "security-severity": sec_sev,
                    "problem.severity": "error" if level == "error" else "warning",
                }
            }
    return list(seen.values())

def make_sarif(json_path):
    try:
        with open(json_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"  Skipping {json_path}: {e}", file=sys.stderr)
        return None
    files_map = data.get("Files") or {}
    all_behaviors = [b for fr in files_map.values() for b in (fr.get("Behaviors") or [])]
    rules      = behaviors_to_rules(all_behaviors)
    rule_index = {r["id"]: i for i, r in enumerate(rules)}
    results = []
    for path, fr in files_map.items():
        rel = path.removeprefix("/repo/").lstrip("/")
        for b in (fr.get("Behaviors") or []):
            bid   = b.get("ID") or b.get("RuleName") or "unknown"
            level, _ = risk_to_sarif_level(b.get("RiskLevel", ""))
            desc  = b.get("Description") or bid
            matches = b.get("MatchStrings") or []
            msg_text = desc + (" Matched: " + ", ".join(str(m) for m in matches[:5]) if matches else "")
            fp = hashlib.sha256(f"{bid}:{rel}".encode()).hexdigest()[:16]
            results.append({
                "ruleId":    bid,
                "ruleIndex": rule_index.get(bid, 0),
                "level":     level,
                "message":   {"text": msg_text[:1024]},
                "locations": [{"physicalLocation": {
                    "artifactLocation": {"uri": rel, "uriBaseId": "%SRCROOT%"},
                    "region": {"startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 1}
                }}],
                "partialFingerprints": {"primaryLocationLineHash": f"{fp}:1"}
            })
    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{"tool": {"driver": {
            "name": "malcontent", "version": "latest",
            "informationUri": "https://github.com/chainguard-dev/malcontent",
            "rules": rules
        }}, "automationDetails": {"id": "malcontent/"}, "results": results}]
    }

EMPTY_SARIF = {
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [{"tool": {"driver": {"name": "malcontent", "rules": []}}, "results": []}]
}
sarif = make_sarif(src) or EMPTY_SARIF
with open(dst, "w") as f:
    json.dump(sarif, f, indent=2)
print(f"  {dst}: {len(sarif['runs'][0]['results'])} result(s)")
