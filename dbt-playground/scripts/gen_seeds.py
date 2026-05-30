#!/usr/bin/env python3
"""seed CSV 생성: (1) 이미지 취약점 findings, (2) 이미지 크기, (3) git 커밋 로그."""
import csv
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # dbt-playground/
REPO = ROOT.parent                                  # image-harden/ (git repo)
SEEDS = ROOT / "seeds"
SEEDS.mkdir(exist_ok=True)

LANGS = ["go", "python", "java"]
VARIANTS = ["naive", "wolfi"]


def sh(args):
    return subprocess.run(args, capture_output=True, text=True).stdout


# ── 1) 취약점 findings (trivy) ──────────────────────────────────────────
findings = []
for lang in LANGS:
    for variant in VARIANTS:
        img = f"harden-{lang}:{variant}"
        out = sh(["trivy", "image", "-q", "--format", "json", img])
        if not out.strip():
            continue
        data = json.loads(out)
        for res in (data.get("Results") or []):
            for v in (res.get("Vulnerabilities") or []):
                findings.append({
                    "lang": lang,
                    "variant": variant,
                    "target": res.get("Target", ""),
                    "vuln_id": v.get("VulnerabilityID", ""),
                    "pkg_name": v.get("PkgName", ""),
                    "installed_version": v.get("InstalledVersion", ""),
                    "fixed_version": v.get("FixedVersion", ""),
                    "severity": v.get("Severity", ""),
                })
with (SEEDS / "vuln_findings.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "lang", "variant", "target", "vuln_id", "pkg_name",
        "installed_version", "fixed_version", "severity"])
    w.writeheader()
    w.writerows(findings)
print(f"vuln_findings.csv: {len(findings)} rows")

# ── 2) 이미지 크기 ──────────────────────────────────────────────────────
sizes = []
for lang in LANGS:
    for variant in VARIANTS:
        img = f"harden-{lang}:{variant}"
        b = sh(["docker", "image", "inspect", img, "--format", "{{.Size}}"]).strip()
        if not b.isdigit():
            continue
        sizes.append({"lang": lang, "variant": variant,
                      "size_mb": round(int(b) / 1_000_000, 2)})
with (SEEDS / "image_sizes.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["lang", "variant", "size_mb"])
    w.writeheader()
    w.writerows(sizes)
print(f"image_sizes.csv: {len(sizes)} rows")

# ── 3) git 커밋 로그 ────────────────────────────────────────────────────
log = sh(["git", "-C", str(REPO), "log",
          "--pretty=format:%h\x1f%an\x1f%ad\x1f%s", "--date=short"])
commits = []
for line in log.splitlines():
    parts = line.split("\x1f")
    if len(parts) != 4:
        continue
    sha, author, date, subject = parts
    ctype = subject.split(":", 1)[0].strip() if ":" in subject else "other"
    commits.append({"sha": sha, "author": author, "commit_date": date,
                    "commit_type": ctype, "subject": subject})
with (SEEDS / "git_commits.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "sha", "author", "commit_date", "commit_type", "subject"])
    w.writeheader()
    w.writerows(commits)
print(f"git_commits.csv: {len(commits)} rows")
