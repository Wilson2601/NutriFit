"""Runs every automated test and writes docs/evaluation/TEST_REPORT.md (real pass/fail results).

Usage (backend folder, venv active):  python make_test_report.py
"""
import subprocess, sys, xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

root = Path(__file__).resolve().parent
xml_path = root / ".pytest_report.xml"
subprocess.run([sys.executable, "-m", "pytest", "-q", f"--junitxml={xml_path}"], cwd=root)

suite = ET.parse(xml_path).getroot()
suite = suite if suite.tag == "testsuite" else suite[0]
rows, groups = [], {}
for tc in suite.iter("testcase"):
    failed = tc.find("failure") is not None or tc.find("error") is not None
    file = tc.get("classname", "").split(".")[-1]
    groups.setdefault(file, [0, 0])[0 if not failed else 1] += 1
    rows.append((file, tc.get("name"), "FAIL" if failed else "PASS"))

total = len(rows); bad = sum(1 for r in rows if r[2] == "FAIL")
out = [f"# NutriFit automated test report", "", f"Generated: {datetime.now():%Y-%m-%d %H:%M}",
       f"Result: **{total - bad} passed, {bad} failed, {total} total**", "",
       "| Test file | Passed | Failed |", "|---|---|---|"]
out += [f"| {f} | {p} | {x} |" for f, (p, x) in sorted(groups.items())]
out += ["", "## All test cases", "", "| File | Test case | Result |", "|---|---|---|"]
out += [f"| {f} | {n} | {r} |" for f, n, r in rows]
dest = root.parent / "docs" / "evaluation" / "TEST_REPORT.md"
dest.write_text("\n".join(out) + "\n", encoding="utf-8")
xml_path.unlink(missing_ok=True)
print(f"Wrote {dest}  ({total - bad} passed, {bad} failed)")
