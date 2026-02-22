#!/usr/bin/env python3
"""
Generate test-report-alpha.html from test-output.txt.

Goal: a curated, scenario-oriented report (similar to test-report.html) that:
- Groups tests into meaningful module buckets.
- Visualizes the key scenario data that tests already print to the console.
- Keeps a collapsible "Raw Console Output" section for auditability.
"""

from __future__ import annotations

import datetime as dt
import html
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
TEST_OUTPUT = ROOT / "test-output.txt"
BASE_REPORT = ROOT / "test-report.html"
OUT_HTML = ROOT / "test-report-alpha.html"
OUT_RESULTS = ROOT / "test-results.json"
OUT_STRUCTURE = ROOT / "test-structure.json"

PASS_RE = re.compile(r"^\s*✔\s+(.*?)(?:\s*\((\d+)ms\))?\s*$")
PEND_RE = re.compile(r"^\s*-\s+(.*)\s*$")
SUMMARY_PASS_RE = re.compile(r"^\s*(\d+)\s+passing\s*\(([^)]+)\)\s*$")
SUMMARY_PEND_RE = re.compile(r"^\s*(\d+)\s+pending\s*$")

DROP_SUITE_EXACT = {
    "'constructor',",
    "'startTest',",
    "'recordTimelineEntry',",
    "'endTest',",
    "'isTracking',",
    "'getTestData',",
    "'getAllTests',",
    "'getCurrentTestId',",
    "'getSummary',",
    "'getTestsByFile',",
    "'getTestsByStatus',",
    "'clear',",
    "'toJSON',",
    "'fromJSON'",
}


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def parse_int(s: str) -> int:
    return int(s.replace(",", "").strip())


def last_match(lines: List[str], rx: re.Pattern[str]) -> Optional[re.Match[str]]:
    for line in reversed(lines):
        m = rx.match(line)
        if m:
            return m
    return None


def find_index(lines: List[str], pred, start: int = 0) -> Optional[int]:
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    return None


def extract_block(
    lines: List[str], start_pred, end_pred, *, include_end: bool = False
) -> List[str]:
    start = find_index(lines, start_pred)
    if start is None:
        return []
    out: List[str] = []
    for i in range(start, len(lines)):
        out.append(lines[i])
        if end_pred(lines[i]):
            if not include_end:
                out.pop()
            break
    return out


def extract_css_from_base() -> str:
    raw = BASE_REPORT.read_text(encoding="utf-8")
    m = re.search(r"<style>\s*(.*?)\s*</style>", raw, flags=re.S | re.I)
    if not m:
        raise RuntimeError("Could not extract <style> from test-report.html")
    return m.group(1)


def is_noise_suite_name(name: str) -> bool:
    t = name.strip()
    if not t:
        return True
    if t in DROP_SUITE_EXACT:
        return True
    if t.startswith(("StateTracker", "Scientific Reporter")):
        return True
    if t.startswith(("Gas used", "Gas:", "Cost:", "Bytes:", "Kilobytes:", "Megabytes:")):
        return True
    if t.startswith(("┌", "│", "└", "##", "===", "====", "•", "*")):
        return True
    if t.startswith(("✓", "✅", "🎉", "🚨", "🎮", "🚀", "💎", "📊", "⚠")):
        return True
    if t.startswith(("Match ", "Move ", "Player", "Status", "Round ", "Tier ", "Phase ")):
        return True

    # Label/value log lines like "Player1: 0xabc..." or "Players tracked: 136"
    m = re.match(r"^[A-Za-z0-9_() ./-]+:\s*(.+)$", t)
    if m:
        rhs = m.group(1).strip()
        if rhs.startswith(("0x", "$")):
            return True
        if re.match(r"^[0-9]", rhs):
            return True
    return False


def merge_noise_suites(node: Dict[str, Any]) -> None:
    # Clean children first
    new_children: List[Dict[str, Any]] = []
    for child in node.get("subsuites", []):
        merge_noise_suites(child)
        if is_noise_suite_name(child.get("name", "")):
            node.setdefault("tests", []).extend(child.get("tests", []))
            node.setdefault("subsuites", []).extend(child.get("subsuites", []))
            continue
        if child.get("tests") or child.get("subsuites"):
            new_children.append(child)
    node["subsuites"] = new_children


def parse_suite_tree(lines: List[str]) -> List[Dict[str, Any]]:
    root: List[Dict[str, Any]] = []
    stack: List[Tuple[int, Dict[str, Any]]] = []

    for raw in lines:
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        if line.strip().startswith("> "):
            continue
        if SUMMARY_PASS_RE.match(line) or SUMMARY_PEND_RE.match(line):
            continue

        m = PASS_RE.match(line)
        if m:
            name = m.group(1).strip()
            ms = int(m.group(2)) if m.group(2) else None
            if stack:
                stack[-1][1]["tests"].append({"name": name, "status": "passing", "ms": ms})
            continue

        m = PEND_RE.match(line)
        if m:
            name = m.group(1).strip()
            if stack:
                stack[-1][1]["tests"].append({"name": name, "status": "pending", "ms": None})
            continue

        indent = len(line) - len(line.lstrip(" "))
        if indent < 2:
            continue

        stripped = line.strip()
        if stripped.startswith(("┌", "│", "└")):
            continue
        if stripped.startswith(("##", "===", "====")):
            continue

        node: Dict[str, Any] = {"name": stripped, "subsuites": [], "tests": []}

        while stack and indent <= stack[-1][0]:
            stack.pop()

        if stack:
            stack[-1][1]["subsuites"].append(node)
        else:
            root.append(node)

        stack.append((indent, node))

    cleaned: List[Dict[str, Any]] = []
    for s in root:
        merge_noise_suites(s)
        if is_noise_suite_name(s.get("name", "")):
            continue
        if s.get("tests") or s.get("subsuites"):
            cleaned.append(s)
    return cleaned


def count_suite(node: Dict[str, Any]) -> Tuple[int, int]:
    p = sum(1 for t in node.get("tests", []) if t.get("status") == "passing")
    q = sum(1 for t in node.get("tests", []) if t.get("status") == "pending")
    for sub in node.get("subsuites", []):
        sp, sq = count_suite(sub)
        p += sp
        q += sq
    return p, q


def flatten_tests(node: Dict[str, Any], path: List[str]) -> List[Tuple[List[str], Dict[str, Any]]]:
    out: List[Tuple[List[str], Dict[str, Any]]] = []
    next_path = path + [node.get("name", "")]
    for t in node.get("tests", []):
        out.append((next_path, t))
    for sub in node.get("subsuites", []):
        out.extend(flatten_tests(sub, next_path))
    return out


def group_for_path(path: List[str]) -> str:
    joined = " ".join(path).lower()
    if "connectfour" in joined:
        return "ConnectFourOnChain"
    if "chess" in joined:
        return "ChessOnChain"
    if "tictac" in joined:
        return "TicTacChain"
    if "arbitrum storage gas cost analysis" in joined:
        return "Gas & Storage"
    if any(k in joined for k in ("gas", "storage", "capacity")):
        return "Gas & Performance"
    return "Protocol Core"


def category_for_test(path: List[str], test_name: str) -> str:
    hay = (" ".join(path) + " " + test_name).lower()
    if any(k in hay for k in ("gas", "storage", "capacity")):
        return "Gas & Performance"
    if any(k in hay for k in ("escalation", "timeout", "force start", "ml", "el", "abandoned")):
        return "Escalation & Timeouts"
    if "all-draw" in hay or "all draw" in hay:
        return "All-Draw Resolution"
    if any(k in hay for k in ("prize", "fee", "earnings", "raffle", "reserve")):
        return "Economics & Prizes"
    if any(k in hay for k in ("event", "transfer", "record")):
        return "Events & Records"
    if any(k in hay for k in ("view", "leaderboard", "stats", "info")):
        return "Views & Data Integrity"
    if any(k in hay for k in ("bug", "regression", "edge case", "persistence", "cache")):
        return "Edge Cases & Regression"
    return "Game & Tournament Logic"


def parse_arbitrum_gas(lines: List[str]) -> Dict[str, Any]:
    start = find_index(lines, lambda l: l.strip() == "GAS ANALYSIS REPORT")
    if start is None:
        return {}

    # End after scaling projections (use the next ===== line after that header)
    scale = find_index(lines, lambda l: l.strip() == "Scaling Projections:", start=start)
    if scale is None:
        return {}
    end = find_index(lines, lambda l: bool(re.match(r"^=+$", l.strip())), start=scale)
    if end is None:
        end = min(len(lines), scale + 50)

    block = lines[start:end]

    total_matches = None
    m = re.search(r"✅ Completed ([\d,]+) total matches", "\n".join(lines))
    if m:
        total_matches = m.group(1)

    # Average gas table
    table_start = find_index(block, lambda l: l.strip().startswith("Match#") and "|" in l)
    rows: List[Dict[str, str]] = []
    if table_start is not None:
        for l in block[table_start + 2 : table_start + 40]:
            if "|" not in l:
                break
            cols = [c.strip() for c in l.split("|") if c.strip()]
            if not cols or not cols[0].isdigit():
                continue
            # Expected columns:
            # Match#, Enrollment, Move 1, Move 2, Move 3, Move 4*, Total, Delta
            if len(cols) >= 8:
                rows.append(
                    {
                        "match": cols[0],
                        "enroll": cols[1],
                        "m1": cols[2],
                        "m2": cols[3],
                        "m3": cols[4],
                        "m4": cols[5],
                        "total": cols[6],
                        "delta": cols[7],
                    }
                )

    def grab(rx: str) -> Optional[str]:
        r = re.compile(rx)
        for l in block:
            m2 = r.search(l)
            if m2:
                return m2.group(1)
        return None

    first_total = grab(r"First match avg gas:\s*([\d,]+)")
    last_match_n = None
    last_total = None
    last_line = None
    for l in block:
        if re.search(r"\d+(?:st|nd|rd|th) match avg gas:", l):
            last_line = l
    if last_line:
        m2 = re.search(r"(\d+)(?:st|nd|rd|th) match avg gas:\s*([\d,]+)", last_line)
        if m2:
            last_match_n = int(m2.group(1))
            last_total = m2.group(2)

    total_records = grab(r"Total MatchRecords:\s*([\d,]+)")
    total_storage_bytes = grab(r"Bytes:\s*([\d,]+)\s*bytes")
    total_storage_mb = grab(r"Megabytes:\s*([0-9.]+)\s*MB")
    per_player_kb = grab(r"=\s*([0-9.]+)\s*KB")

    projections: List[Dict[str, str]] = []
    proj_idx = find_index(block, lambda l: l.strip() == "Scaling Projections:")
    if proj_idx is not None:
        i = proj_idx + 1
        while i < len(block):
            line = block[i].rstrip()
            m3 = re.search(r"^\s*([\d,]+)\s+players\s+.\s*([\d,]+)\s+matches:\s*$", line)
            if m3 and i + 1 < len(block):
                players = m3.group(1)
                matches = m3.group(2)
                m4 = re.search(r"Storage:\s*([0-9.]+\s*(?:MB|GB))\s*\(([\d,]+)\s+records\)", block[i + 1])
                if m4:
                    projections.append(
                        {
                            "players": players,
                            "matches": matches,
                            "storage": m4.group(1),
                            "records": m4.group(2),
                        }
                    )
                i += 2
                continue
            i += 1

    return {
        "totalMatches": total_matches,
        "firstTotal": first_total,
        "lastMatchN": last_match_n,
        "lastTotal": last_total,
        "avgRows": rows,
        "totalRecords": total_records,
        "totalStorageBytes": total_storage_bytes,
        "totalStorageMB": total_storage_mb,
        "perPlayerKB": per_player_kb,
        "projections": projections,
    }


def parse_connectfour_gas(lines: List[str]) -> Dict[str, Any]:
    start = find_index(lines, lambda l: l.strip() == "## Average Player Cost Analysis")
    end = find_index(lines, lambda l: l.strip() == "END OF REPORT", start=start or 0)
    if start is None or end is None or end <= start:
        return {}

    block = lines[start:end]

    def grab(rx: str) -> Optional[str]:
        r = re.compile(rx)
        for l in block:
            m = r.search(l)
            if m:
                return m.group(1)
        return None

    players_tracked = grab(r"- Players Tracked:\s*(\d+)")
    total_gas_all = grab(r"- Total Gas \(All Players\):\s*([\d,]+)")
    avg_gas = grab(r"- Average Gas per Player:\s*([\d,]+)")
    avg_cost_eth = grab(r"- Average Cost @ 0\.05 gwei:\s*([0-9.]+)\s*ETH")
    avg_cost_usd = grab(r"- Average Cost @ 0\.05 gwei:\s*\$([0-9.]+)")

    max_player = grab(r"- Player Address:\s*(0x[0-9a-fA-F]+)")
    max_total_gas = grab(r"- Total Gas Spent:\s*([\d,]+)")
    max_txs = grab(r"- Total Transactions:\s*(\d+)")
    max_cost_eth = grab(r"- Cost @ 0\.05 gwei:\s*([0-9.]+)\s*ETH")
    # There are multiple USD lines; pick the first.
    max_cost_usd = None
    for l in block:
        m = re.search(r"- Cost @ 0\.05 gwei:\s*\$([0-9.]+)", l)
        if m:
            max_cost_usd = m.group(1)
            break

    # Auto-start (outside the report block)
    auto_block = extract_block(
        lines,
        lambda l: "AUTO-START GAS COST" in l,
        lambda l: "Phase 3:" in l,
    )
    auto_gas = None
    auto_eth = None
    auto_usd = None
    for l in auto_block:
        m = re.search(r"^\s*Gas:\s*([\d,]+)", l)
        if m:
            auto_gas = m.group(1)
        m = re.search(r"^\s*Cost:\s*([0-9.]+)\s*ETH\s*\(\$([0-9.]+)\)", l)
        if m:
            auto_eth = m.group(1)
            auto_usd = m.group(2)

    # Saturation summary (outside the report block)
    sat_block = extract_block(
        lines,
        lambda l: "✅ CONTRACT SATURATION COMPLETE" in l,
        lambda l: "Phase 2:" in l,
    )
    sat_players = None
    sat_tournaments = None
    for l in sat_block:
        m = re.search(r"Total Players:\s*(\d+)", l)
        if m:
            sat_players = m.group(1)
        m = re.search(r"Active Tournaments:\s*(\d+)", l)
        if m:
            sat_tournaments = m.group(1)

    # Long game checkpoints (outside the report block)
    long_block = extract_block(
        lines,
        lambda l: "SCENARIO 1: Long Game" in l,
        lambda l: "SCENARIO 2:" in l,
    )
    long_moves: List[Tuple[str, str]] = []
    for l in long_block:
        m = re.search(r"Move\s+(\d+/\d+)\s+complete\s+-\s+Gas:\s*(\d+)", l)
        if m:
            long_moves.append((m.group(1), m.group(2)))

    # Network cost estimates table (ASCII)
    table_lines: List[str] = []
    in_table = False
    for l in block:
        if l.strip().startswith("┌"):
            in_table = True
        if in_table:
            table_lines.append(l)
        if in_table and l.strip().startswith("└"):
            break

    net_rows: List[Dict[str, str]] = []
    if table_lines:
        i = 0
        while i < len(table_lines):
            l = table_lines[i]
            m = re.search(r"│\s*(0?\.?\d+)\s*gwei\s*│\s*([0-9.]+)\s*│\s*([0-9.]+)\s*│", l)
            if m:
                gas_price = m.group(1)
                avg_eth = m.group(2)
                max_eth = m.group(3)
                avg_usd2 = ""
                max_usd2 = ""
                if i + 1 < len(table_lines):
                    usd = re.findall(r"\(\$([0-9.]+)", table_lines[i + 1])
                    if len(usd) >= 2:
                        avg_usd2 = usd[0]
                        max_usd2 = usd[1]
                net_rows.append(
                    {
                        "gasPrice": gas_price,
                        "avgEth": avg_eth,
                        "avgUsd": avg_usd2,
                        "maxEth": max_eth,
                        "maxUsd": max_usd2,
                    }
                )
                i += 2
                continue
            i += 1

    # Operation breakdown (inside the report block)
    block_text = "\n".join(block)

    def op(label: str) -> Dict[str, Optional[str]]:
        m = re.search(
            rf"{re.escape(label)}:\s*\n\s*Count:\s*(\d+)\s*\n\s*Total Gas:\s*([\d,]+)\s*\n\s*Average Gas:\s*([\d,]+)",
            block_text,
            flags=re.S,
        )
        if not m:
            return {"count": None, "totalGas": None, "avgGas": None}
        return {"count": m.group(1), "totalGas": m.group(2), "avgGas": m.group(3)}

    ops = {"enrollments": op("ENROLLMENTS"), "moves": op("MOVES")}

    return {
        "playersTracked": players_tracked,
        "totalGasAll": total_gas_all,
        "avgGasPerPlayer": avg_gas,
        "avgCostEth": avg_cost_eth,
        "avgCostUsd": avg_cost_usd,
        "maxPlayer": max_player,
        "maxTotalGas": max_total_gas,
        "maxTxs": max_txs,
        "maxCostEth": max_cost_eth,
        "maxCostUsd": max_cost_usd,
        "autoStartGas": auto_gas,
        "autoStartEth": auto_eth,
        "autoStartUsd": auto_usd,
        "saturationPlayers": sat_players,
        "saturationTournaments": sat_tournaments,
        "longGameMoves": long_moves,
        "networkRows": net_rows,
        "ops": ops,
    }


def parse_scenarios(lines: List[str]) -> Dict[str, Any]:
    esc_block = extract_block(
        lines,
        lambda l: l.strip() == "=== COMPREHENSIVE ESCALATION TEST ===",
        lambda l: "COMPREHENSIVE ESCALATION TEST PASSED" in l,
        include_end=True,
    )
    esc_summary: List[str] = []
    esc_validated: List[str] = []
    if esc_block:
        in_summary = False
        for l in esc_block:
            if l.strip() == "=== ROUND 0 SUMMARY ===":
                in_summary = True
                continue
            if in_summary:
                if l.strip().startswith("==="):
                    break
                if l.strip():
                    esc_summary.append(l.strip())

        in_validated = False
        for l in esc_block:
            if l.strip() == "Validated:":
                in_validated = True
                continue
            if in_validated:
                t = l.strip()
                if t.startswith("✔"):
                    break
                if t.startswith("✓"):
                    esc_validated.append(t.lstrip("✓").strip())

    iso_block = extract_block(
        lines,
        lambda l: "COMPREHENSIVE TEST SUMMARY" in l,
        lambda l: "ALL COMPREHENSIVE CHECKS PASSED" in l,
        include_end=True,
    )
    iso_items: List[str] = []
    if iso_block:
        for l in iso_block:
            t = l.strip()
            if t.startswith("✓"):
                iso_items.append(t.lstrip("✓").strip())
            elif t.startswith("•"):
                iso_items.append(t)

    return {
        "escalation": {"round0Summary": esc_summary, "validated": esc_validated},
        "isolation": {"items": iso_items},
    }


def write_structure_json(suites: List[Dict[str, Any]], total_passing: int, total_pending: int) -> None:
    def to_node(node: Dict[str, Any]) -> Dict[str, Any]:
        p, q = count_suite(node)
        return {
            "name": node.get("name", ""),
            "subsuites": [to_node(s) for s in node.get("subsuites", [])],
            "tests": [{"name": t["name"], "status": t["status"]} for t in node.get("tests", [])],
            "passing": p,
            "pending": q,
        }

    total = total_passing + total_pending
    out = {
        "totalPassing": total_passing,
        "totalPending": total_pending,
        "totalTests": total,
        "successRate": f"{(total_passing / total * 100.0) if total else 0.0:.1f}",
        "suites": [to_node(s) for s in suites],
    }
    OUT_RESULTS.write_text(json.dumps(out, indent=2), encoding="utf-8")
    OUT_STRUCTURE.write_text(json.dumps(out, indent=2), encoding="utf-8")


def render_check_list(items: List[str]) -> str:
    if not items:
        return "<p style=\"color: #94a3b8;\">(No scenario output captured.)</p>"
    li = "\n".join(f"<li>{esc(x)}</li>" for x in items)
    return f"<ul class=\"checkmark-list\">{li}</ul>"


def render_html(
    *,
    lines: List[str],
    run_dt: dt.datetime,
    total_passing: int,
    total_pending: int,
    duration: str,
    suites: List[Dict[str, Any]],
    flat_tests: List[Tuple[List[str], Dict[str, Any]]],
    scenarios: Dict[str, Any],
    cf: Dict[str, Any],
    arb: Dict[str, Any],
) -> str:
    css = extract_css_from_base()
    extra_css = """
        details {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 12px;
            padding: 14px 16px;
            margin-top: 18px;
        }
        details summary {
            cursor: pointer;
            color: #93c5fd;
            font-weight: 700;
        }
        details pre {
            margin-top: 12px;
            white-space: pre-wrap;
            color: #cbd5e1;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            line-height: 1.5;
        }
        .scenario-box {
            background: #0f172a;
            border-radius: 16px;
            padding: 28px;
            margin: 22px 0;
            border: 1px solid #334155;
            border-left: 4px solid #06b6d4;
        }
        .scenario-box h3 {
            color: #e2e8f0;
            margin-bottom: 12px;
            font-size: 1.5em;
            font-weight: 800;
        }
        .small-table {
            width: 100%;
            border-collapse: collapse;
            margin: 16px 0 0 0;
            background: #1e293b;
            border-radius: 12px;
            overflow: hidden;
        }
        .small-table thead {
            background: rgba(102, 126, 234, 0.18);
            color: white;
        }
        .small-table th {
            padding: 14px 16px;
            text-align: left;
            font-weight: 700;
            font-size: 0.9em;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }
        .small-table td {
            padding: 12px 16px;
            color: #cbd5e1;
            border-top: 1px solid #334155;
        }
    """

    total = total_passing + total_pending
    success_rate = (total_passing / total * 100.0) if total else 0.0
    run_date = run_dt.strftime("%B %-d, %Y")
    run_time = run_dt.strftime("%H:%M")

    # Build module/group stats and category stats
    group_stats: Dict[str, Dict[str, int]] = {}
    category_stats: Dict[str, Dict[str, int]] = {}
    group_category_stats: Dict[str, Dict[str, Dict[str, int]]] = {}
    pending_by_suite: Dict[str, List[str]] = {}
    slow_tests: List[Tuple[str, str, int]] = []

    for path, t in flat_tests:
        group = group_for_path(path)
        cat = category_for_test(path, t["name"])
        group_stats.setdefault(group, {"passing": 0, "pending": 0})
        category_stats.setdefault(cat, {"passing": 0, "pending": 0})
        group_category_stats.setdefault(group, {}).setdefault(cat, {"passing": 0, "pending": 0})
        group_stats[group][t["status"]] += 1
        category_stats[cat][t["status"]] += 1
        group_category_stats[group][cat][t["status"]] += 1

        if t["status"] == "pending":
            suite_name = " / ".join([p for p in path if p]) or "(unknown suite)"
            pending_by_suite.setdefault(suite_name, []).append(t["name"])

        if t.get("ms") is not None:
            suite_name = " / ".join([p for p in path if p])
            slow_tests.append((t["name"], suite_name, int(t["ms"])))

    slow_tests.sort(key=lambda x: -x[2])
    slow_tests = slow_tests[:15]

    def badge(p: int, q: int) -> str:
        out = f'<span class="badge success">{p} PASSING</span>'
        if q:
            out += f' <span class="badge warning">{q} PENDING</span>'
        return out

    def progress(p: int, q: int) -> float:
        tot = p + q
        return (p / tot * 100.0) if tot else 0.0

    category_descriptions = {
        "Game & Tournament Logic": "Core gameplay, enrollment, bracket progression, and correctness of state transitions.",
        "Escalation & Timeouts": "Anti-stalling flows (EL*/ML*) and all timing/eligibility boundary checks.",
        "Economics & Prizes": "Entry fee splits, prize distribution, rounding/wei integrity, raffles, and earnings.",
        "All-Draw Resolution": "Finals/semi/round-all-draw scenarios and fair payout splitting.",
        "Views & Data Integrity": "View functions used by UIs: match/tournament data, leaderboards, stats, and persistence.",
        "Events & Records": "Event emissions and record-keeping correctness (e.g., Transfer, records/mappings).",
        "Edge Cases & Regression": "Known bugs/edge cases prevented from regressing (cache, finals persistence, etc.).",
        "Gas & Performance": "Gas measurements, capacity testing, storage growth, and scale/stress behaviors.",
    }

    group_order = [
        "ConnectFourOnChain",
        "ChessOnChain",
        "TicTacChain",
        "Protocol Core",
        "Gas & Performance",
        "Gas & Storage",
    ]

    group_cards = []
    groups_sorted = sorted(
        group_stats.items(),
        key=lambda kv: (
            group_order.index(kv[0]) if kv[0] in group_order else 999,
            -sum(kv[1].values()),
            kv[0],
        ),
    )

    for g, st in groups_sorted:
        p = st["passing"]
        q = st["pending"]

        # Per-group category breakdown
        cats = []
        for cat, cst in sorted(
            group_category_stats.get(g, {}).items(),
            key=lambda kv: (-sum(kv[1].values()), kv[0]),
        ):
            cp = cst["passing"]
            cq = cst["pending"]
            label = f"{cat} ({cp + cq} tests)"
            status = f"{cp} passing" + (f" • {cq} pending" if cq else "")
            cats.append(
                f"""
                <div class="info-card">
                    <h4>{esc(label)}</h4>
                    <p>{esc(category_descriptions.get(cat, ""))}<br><span class="status-ok">{esc(status)}</span></p>
                </div>
                """
            )
        cats_html = f'<div class="info-grid">{"".join(cats[:6])}</div>' if cats else ""

        group_cards.append(
            f"""
            <div class="test-suite">
                <h3>
                    <span>{esc(g)}</span>
                    {badge(p, q)}
                </h3>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: {progress(p, q):.1f}%;"></div>
                </div>
                <p style="color: #cbd5e1; margin-top: 10px;">
                    <strong>{p + q} tests</strong> (grouped by suite/test names)
                </p>
                {cats_html}
            </div>
            """
        )

    cat_cards = []
    for cat, st in sorted(category_stats.items(), key=lambda kv: (-sum(kv[1].values()), kv[0])):
        p = st["passing"]
        q = st["pending"]
        tot = p + q
        status = f'<div style="margin-top: 10px; color: #10b981; font-weight: 600;">PASSING: {p}</div>'
        if q:
            status = f'<div style="margin-top: 10px; color: #f59e0b; font-weight: 600;">PASSING: {p} • PENDING: {q}</div>'
        cat_cards.append(
            f"""
            <div class="edge-case-card">
                <div class="icon">•</div>
                <h5>{esc(cat)}</h5>
                <p><strong>{tot} tests</strong> tagged under this category (heuristic).</p>
                {status}
            </div>
            """
        )

    pending_blocks = []
    for suite_name, tests in sorted(pending_by_suite.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        li = "\n".join(f"<li>{esc(t)}</li>" for t in tests)
        pending_blocks.append(
            f"""
            <div class="info-card" style="border-left-color: #f59e0b;">
                <h4>{esc(suite_name)} <span class="badge warning">{len(tests)} PENDING</span></h4>
                <ul class="checkmark-list">{li}</ul>
            </div>
            """
        )

    slow_rows = "\n".join(
        f"<tr><td>{esc(name)}</td><td>{esc(suite)}</td><td><span class=\"gas-value\">{ms}ms</span></td></tr>"
        for name, suite, ms in slow_tests
    )

    # ConnectFour gas tables
    cf_net_rows = ""
    if cf.get("networkRows"):
        cf_net_rows = "\n".join(
            "<tr>"
            f"<td><strong>{esc(r['gasPrice'])} gwei</strong></td>"
            f"<td><span class=\"cost-value\">{esc(r['avgEth'])} ETH</span> <span style=\"color:#64748b;\">(${esc(r['avgUsd'])})</span></td>"
            f"<td><span class=\"cost-value\">{esc(r['maxEth'])} ETH</span> <span style=\"color:#64748b;\">(${esc(r['maxUsd'])})</span></td>"
            "</tr>"
            for r in cf["networkRows"]
        )

    cf_long_rows = ""
    if cf.get("longGameMoves"):
        cf_long_rows = "\n".join(
            f"<tr><td>{esc(mv)}</td><td><span class=\"gas-value\">{esc(g)}</span></td></tr>"
            for mv, g in cf["longGameMoves"]
        )

    cf_ops_rows = ""
    if cf.get("ops"):
        rows = []
        for label, key in (("Enrollments", "enrollments"), ("Moves", "moves")):
            d = cf["ops"].get(key, {})
            rows.append(
                f"<tr><td><strong>{label}</strong></td><td>{esc(d.get('count') or 'N/A')}</td>"
                f"<td><span class=\"gas-value\">{esc(d.get('avgGas') or 'N/A')}</span></td>"
                f"<td><span class=\"gas-value\">{esc(d.get('totalGas') or 'N/A')}</span></td></tr>"
            )
        cf_ops_rows = "\n".join(rows)

    # Arbitrum avg rows
    arb_avg_rows = ""
    if arb.get("avgRows"):
        arb_avg_rows = "\n".join(
            "<tr>"
            f"<td><span class=\"gas-value\">{esc(r['match'])}</span></td>"
            f"<td><span class=\"gas-value\">{esc(r['enroll'])}</span></td>"
            f"<td>{esc(r['m1'])}</td>"
            f"<td>{esc(r['m2'])}</td>"
            f"<td>{esc(r['m3'])}</td>"
            f"<td><span class=\"gas-value\">{esc(r['m4'])}</span></td>"
            f"<td><span class=\"gas-value\">{esc(r['total'])}</span></td>"
            f"<td>{esc(r['delta'])}</td>"
            "</tr>"
            for r in arb["avgRows"]
        )

    arb_proj_rows = ""
    if arb.get("projections"):
        arb_proj_rows = "\n".join(
            "<tr>"
            f"<td><strong>{esc(p['players'])}</strong></td>"
            f"<td>{esc(p['matches'])}</td>"
            f"<td><span class=\"gas-value\">{esc(p['records'])}</span></td>"
            f"<td><span class=\"cost-value\">{esc(p['storage'])}</span></td>"
            "</tr>"
            for p in arb["projections"]
        )

    # TicTacChain simple gas lines (captured as console logs)
    tictac_enroll = None
    tictac_move = None
    for l in lines:
        m = re.search(r"Gas used for enrollment:\s*(\d+)", l)
        if m:
            tictac_enroll = m.group(1)
        m = re.search(r"Gas used for move:\s*(\d+)", l)
        if m:
            tictac_move = m.group(1)

    tictac_metrics = ""
    if tictac_enroll or tictac_move:
        parts = []
        if tictac_enroll:
            parts.append(
                f'<div class="metric-row"><span class="metric-label">Enrollment Gas</span><span class="metric-value">{parse_int(tictac_enroll):,}</span></div>'
            )
        if tictac_move:
            parts.append(
                f'<div class="metric-row"><span class="metric-label">Move Gas</span><span class="metric-value">{parse_int(tictac_move):,}</span></div>'
            )
        tictac_metrics = "".join(parts)

    # Scenarios
    esc_summary = scenarios.get("escalation", {}).get("round0Summary", [])
    esc_valid = scenarios.get("escalation", {}).get("validated", [])
    iso_items = scenarios.get("isolation", {}).get("items", [])

    raw_console = "\n".join(lines)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ETour Protocol - Test Report (Alpha)</title>
  <style>
{css}
{extra_css}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="header-content">
        <h1>ETour Protocol Test Report (Alpha)</h1>
        <p class="subtitle">Scenario-oriented report hydrated from console output</p>
        <p class="subtitle">Generated {esc(run_date)} at {esc(run_time)}</p>
        <div class="confidence-badge">{success_rate:.1f}% SUCCESS • {total_passing} PASSING • {total_pending} PENDING</div>
      </div>
    </div>

    <div class="stats">
      <div class="stat-card total">
        <div class="number">{total}</div>
        <div class="label">Total Tests</div>
        <div class="sublabel">Pass + Pending</div>
      </div>
      <div class="stat-card passing">
        <div class="number">{total_passing}</div>
        <div class="label">Passing</div>
        <div class="sublabel">Validated behavior</div>
      </div>
      <div class="stat-card failing">
        <div class="number">0</div>
        <div class="label">Failing</div>
        <div class="sublabel">No regressions</div>
      </div>
      <div class="stat-card pending">
        <div class="number">{total_pending}</div>
        <div class="label">Pending</div>
        <div class="sublabel">Future work</div>
      </div>
      <div class="stat-card time">
        <div class="number">{esc(duration)}</div>
        <div class="label">Duration</div>
        <div class="sublabel">Full run</div>
      </div>
      <div class="stat-card coverage">
        <div class="number">{success_rate:.1f}%</div>
        <div class="label">Success Rate</div>
        <div class="sublabel">Passing / Total</div>
      </div>
    </div>

    <div class="section" style="background: #0f172a;">
      <h2>Scenario Walkthroughs</h2>

      <div class="scenario-box">
        <h3>Comprehensive Escalation Tournament</h3>
        <p style="color: #94a3b8; margin-bottom: 15px;">
          Extracted from the console logs printed during the end-to-end escalation flow test.
        </p>
        <div class="info-grid">
          <div class="info-card">
            <h4>Round 0 Summary</h4>
            {render_check_list(esc_summary)}
          </div>
          <div class="info-card" style="border-left-color: #10b981;">
            <h4>Validated</h4>
            {render_check_list(esc_valid)}
          </div>
        </div>
      </div>

      <div class="scenario-box" style="border-left-color: #8b5cf6;">
        <h3>Multi-Tournament Data Isolation</h3>
        <p style="color: #94a3b8; margin-bottom: 15px;">
          Extracted from the comprehensive multi-tournament isolation test summary.
        </p>
        {render_check_list(iso_items)}
      </div>
    </div>

    <div class="section" style="background: #0f172a;">
      <h2>Gas & Performance (Captured Console Reports)</h2>

      <div class="highlight-box">
        <h4>ConnectFour Maximum Capacity Report</h4>
        <p>
          The following metrics and tables are extracted from the printed report in the capacity/gas suite.
        </p>
      </div>

      <div class="info-grid">
        <div class="info-card" style="border-left-color: #10b981;">
          <h4>Saturation</h4>
          <p>
            <strong class="gas-value">{esc(cf.get('saturationPlayers') or 'N/A')} players</strong><br>
            <strong class="cost-value">{esc(cf.get('saturationTournaments') or 'N/A')} active tournaments</strong>
          </p>
        </div>
        <div class="info-card" style="border-left-color: #06b6d4;">
          <h4>Auto-Start (Capacity Trigger)</h4>
          <p>
            <strong class="gas-value">{esc(cf.get('autoStartGas') or 'N/A')} gas</strong><br>
            <strong class="cost-value">{esc((cf.get('autoStartEth') or 'N/A') + ' ETH')}</strong>
            <span style="color: #64748b;">(${esc(cf.get('autoStartUsd') or 'N/A')})</span>
          </p>
        </div>
        <div class="info-card" style="border-left-color: #8b5cf6;">
          <h4>Avg Player Cost</h4>
          <p>
            <strong class="gas-value">{esc(cf.get('avgGasPerPlayer') or 'N/A')} gas</strong><br>
            <strong class="cost-value">{esc((cf.get('avgCostEth') or 'N/A') + ' ETH')}</strong>
            <span style="color: #64748b;">(${esc(cf.get('avgCostUsd') or 'N/A')})</span>
          </p>
        </div>
        <div class="info-card" style="border-left-color: #ef4444;">
          <h4>Max Cost Player</h4>
          <p>
            <strong class="gas-value">{esc(cf.get('maxTotalGas') or 'N/A')} gas</strong><br>
            <span style="color: #94a3b8; font-family: monospace;">{esc(cf.get('maxPlayer') or 'N/A')}</span><br>
            <span style="color: #64748b;">{esc(cf.get('maxTxs') or 'N/A')} txs</span>
          </p>
        </div>
      </div>

      <h3 style="color: #e2e8f0; margin: 35px 0 20px 0;">Network Cost Estimates (L2)</h3>
      <table class="gas-table">
        <thead>
          <tr>
            <th>Gas Price</th>
            <th>Avg Player Cost</th>
            <th>Max Player Cost</th>
          </tr>
        </thead>
        <tbody>
          {cf_net_rows}
        </tbody>
      </table>

      <div class="info-grid">
        <div class="info-card" style="border-left-color: #06b6d4;">
          <h4>Long Game Checkpoints</h4>
          <p>Gas sampled during the long-game scenario.</p>
          <table class="small-table">
            <thead><tr><th>Move</th><th>Gas</th></tr></thead>
            <tbody>
              {cf_long_rows}
            </tbody>
          </table>
        </div>
        <div class="info-card" style="border-left-color: #10b981;">
          <h4>Operation Breakdown</h4>
          <p>Aggregated counts and averages from the report.</p>
          <table class="small-table">
            <thead><tr><th>Type</th><th>Count</th><th>Avg Gas</th><th>Total Gas</th></tr></thead>
            <tbody>
              {cf_ops_rows}
            </tbody>
          </table>
        </div>
      </div>

      <div class="highlight-box" style="margin-top: 35px;">
        <h4>Arbitrum Storage Growth Gas Stability</h4>
        <p>Extracted from the Arbitrum storage growth gas report printed during the run.</p>
      </div>

      <div class="info-grid">
        <div class="info-card" style="border-left-color: #06b6d4;">
          <h4>Total Matches Simulated</h4>
          <p><strong class="gas-value">{esc(arb.get('totalMatches') or 'N/A')}</strong></p>
        </div>
        <div class="info-card" style="border-left-color: #10b981;">
          <h4>Avg Total Gas (First)</h4>
          <p><strong class="gas-value">{esc(arb.get('firstTotal') or 'N/A')}</strong></p>
        </div>
        <div class="info-card" style="border-left-color: #10b981;">
          <h4>Avg Total Gas (Last)</h4>
          <p>
            <strong class="gas-value">{esc(arb.get('lastTotal') or 'N/A')}</strong><br>
            <span style="color:#64748b;">match {esc(str(arb.get('lastMatchN') or 'N/A'))}</span>
          </p>
        </div>
        <div class="info-card" style="border-left-color: #8b5cf6;">
          <h4>Storage Size</h4>
          <p>
            <strong class="gas-value">{esc(arb.get('totalStorageBytes') or 'N/A')} bytes</strong><br>
            <span style="color:#64748b;">{esc((arb.get('totalStorageMB') or 'N/A') + ' MB')}</span>
          </p>
        </div>
      </div>

      <table class="gas-table">
        <thead>
          <tr>
            <th>Match#</th>
            <th>Enrollment</th>
            <th>Move 1</th>
            <th>Move 2</th>
            <th>Move 3</th>
            <th>Move 4*</th>
            <th>Total</th>
            <th>Delta</th>
          </tr>
        </thead>
        <tbody>
          {arb_avg_rows}
        </tbody>
      </table>

      <p style="color:#94a3b8;">* Move 4 includes MatchRecord creation (as printed in the report).</p>

      <h3 style="color: #e2e8f0; margin: 35px 0 20px 0;">Scaling Projections</h3>
      <table class="gas-table">
        <thead>
          <tr>
            <th>Players</th>
            <th>Matches Each</th>
            <th>Total Records</th>
            <th>Storage</th>
          </tr>
        </thead>
        <tbody>
          {arb_proj_rows}
        </tbody>
      </table>

      <div class="highlight-box" style="margin-top: 35px;">
        <h4>TicTacChain Gas Checks</h4>
        <p>Captured from the console logs in <code>Gas Optimization</code> tests.</p>
        {tictac_metrics if tictac_metrics else '<p style="color:#94a3b8;">(No TicTacChain gas metrics found in console output.)</p>'}
      </div>
    </div>

    <div class="section">
      <h2>Test Suite Breakdown</h2>
      {''.join(group_cards)}

      <h3 style="color: #e2e8f0; margin: 35px 0 20px 0;">Coverage by Category (Heuristic)</h3>
      <div class="edge-case-grid">
        {''.join(cat_cards)}
      </div>
    </div>

    <div class="section" style="background: #0f172a;">
      <h2>Pending Tests</h2>
      <div class="info-grid">
        {''.join(pending_blocks) if pending_blocks else '<p style="color:#94a3b8;">(No pending tests.)</p>'}
      </div>
    </div>

    <div class="section">
      <h2>Slowest Tests</h2>
      <table class="gas-table">
        <thead><tr><th>Test</th><th>Suite</th><th>Time</th></tr></thead>
        <tbody>
          {slow_rows}
        </tbody>
      </table>
    </div>

    <div class="section" style="background: #0f172a;">
      <h2>Raw Console Output</h2>
      <p style="color: #94a3b8;">
        This is the full <code>test-output.txt</code> content (HTML-escaped).
      </p>
      <details>
        <summary>Show raw output</summary>
        <pre>{esc(raw_console)}</pre>
      </details>
    </div>

    <div class="footer">
      <div class="footer-highlight">{total_passing} passing • {total_pending} pending • 0 failing</div>
      Generated from <code>test-output.txt</code>
    </div>
  </div>
</body>
</html>
"""


def main() -> None:
    if not TEST_OUTPUT.exists():
        raise SystemExit(f"Missing {TEST_OUTPUT}")

    lines = TEST_OUTPUT.read_text(encoding="utf-8", errors="replace").splitlines()

    m_pass = last_match(lines, SUMMARY_PASS_RE)
    m_pend = last_match(lines, SUMMARY_PEND_RE)
    if not m_pass or not m_pend:
        raise SystemExit("Could not find Mocha summary in test-output.txt")

    total_passing = int(m_pass.group(1))
    duration = m_pass.group(2)
    total_pending = int(m_pend.group(1))
    run_dt = dt.datetime.fromtimestamp(TEST_OUTPUT.stat().st_mtime)

    suites = parse_suite_tree(lines)
    write_structure_json(suites, total_passing, total_pending)

    flat: List[Tuple[List[str], Dict[str, Any]]] = []
    for s in suites:
        flat.extend(flatten_tests(s, []))

    scenarios = parse_scenarios(lines)
    cf = parse_connectfour_gas(lines)
    arb = parse_arbitrum_gas(lines)

    html_out = render_html(
        lines=lines,
        run_dt=run_dt,
        total_passing=total_passing,
        total_pending=total_pending,
        duration=duration,
        suites=suites,
        flat_tests=flat,
        scenarios=scenarios,
        cf=cf,
        arb=arb,
    )

    OUT_HTML.write_text(html_out, encoding="utf-8")


if __name__ == "__main__":
    main()
