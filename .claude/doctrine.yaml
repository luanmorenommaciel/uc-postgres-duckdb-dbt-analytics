# .claude/doctrine.yaml — Fleet-wide numeric truth for tech-stack agents.
#
# Purpose: single source of numeric truth for every architect / developer /
# troubleshooter scaffolded by agents-kbs-tech-stack.
#
# Why this file exists:
#   Each agent template (architect.md.tpl, developer.md.tpl, troubleshooter.md.tpl)
#   embeds three numeric tables — the Agreement Matrix, the Confidence Modifiers,
#   and the Task Thresholds. Without a doctrine, those numbers freeze at scaffold
#   time. If you ever decide "0.50 is too low for KB-disagrees-MCP", you would
#   have to hand-edit every agent in every repo. This file flips the relationship:
#   the agents reference doctrine.yaml as the canonical source, and
#   scripts/refresh-doctrine.sh propagates changes back into the agent bodies.
#
# Workflow:
#   1. Edit a value here.
#   2. From the skill source, run: TARGET_REPO=/path/to/repo scripts/refresh-doctrine.sh
#   3. The script rewrites the numeric cells in every *-architect.md / *-developer.md /
#      *-troubleshooter.md in <repo>/.claude/agents/ — body content stays intact.
#
# Schema (do NOT rename fields without also updating refresh-doctrine.sh):

schema_version: 1

# ─── Agreement Matrix ───────────────────────────────────────────────────────
# Confidence score for each (KB-state × MCP-state) combination. These are the
# five non-N/A cells from the 2×3 matrix rendered as ASCII inside the agents.
#
#   KB HAS PATTERN  + MCP AGREES     → kb_has_pattern_mcp_agrees    (HIGH)
#   KB HAS PATTERN  + MCP DISAGREES  → kb_has_pattern_mcp_disagrees (CONFLICT)
#   KB HAS PATTERN  + MCP SILENT     → kb_has_pattern_mcp_silent    (MEDIUM)
#   KB SILENT       + MCP AGREES     → kb_silent_mcp_agrees         (MCP-ONLY)
#   KB SILENT       + MCP SILENT     → kb_silent_mcp_silent         (LOW)
agreement_matrix:
  kb_has_pattern_mcp_agrees: 0.95
  kb_has_pattern_mcp_disagrees: 0.50
  kb_has_pattern_mcp_silent: 0.75
  kb_silent_mcp_agrees: 0.85
  kb_silent_mcp_silent: 0.50

# ─── Confidence Modifiers ───────────────────────────────────────────────────
# Adjustments applied on top of the base agreement-matrix score. Positive
# values raise confidence; negative values lower it. Keep these symmetric
# (a +X modifier should have a -X counterpart for the inverse condition).
modifiers:
  fresh_info_plus: 0.05            # MCP result < 1 month old
  stale_info_minus: -0.05          # KB not updated in > 6 months
  breaking_change_minus: -0.15     # major version known to break callers
  production_examples_plus: 0.05   # real implementations found in the wild
  no_examples_minus: -0.05         # no production references located
  exact_match_plus: 0.05           # KB pattern matches the request precisely
  tangential_minus: -0.05          # KB pattern only loosely related

# ─── Task Thresholds ────────────────────────────────────────────────────────
# Minimum confidence score required to act without escalation, indexed by task
# severity. Below the threshold, the agent must refuse, ask the user, or
# escalate to its counterpart (architect ↔ developer ↔ troubleshooter).
thresholds:
  critical: 0.98    # security, data integrity, prod hot path
  important: 0.95   # public API, contract change, perf regression
  standard: 0.90    # internal refactor, bug fix, slow query
  advisory: 0.80    # formatting, naming, dead code, minor nits
