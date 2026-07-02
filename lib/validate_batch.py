#!/usr/bin/env python3
"""Validate a Stride batch JSON document produced by /stride-ideation:decompose.

Usage:
    python3 lib/validate_batch.py <path-to-stride-batch.json>

Exits 0 on success; advisory warnings (see below) print to stdout and never
change the exit code.
Exits 1 on the first violation, printing a single line of the form:

    stride-ideation: <error message naming the failing JSON path>

The named error variants:

  (a) parse_error           - input is not valid JSON
  (b) wrong_root_key        - root has 'tasks' or any key other than 'goals'
  (c) empty_goals           - 'goals' is missing, not an array, or empty
  (d) goal_missing_field    - a goal entry lacks title, type, or tasks
  (e) bad_dependency_index  - a task's dependencies[] index references an
                              array slot that does not exist OR points to a
                              task at or after the referencing task's own
                              position (forward reference)
  (f) length_limit          - a goal/task title or a security_considerations
                              element exceeds 255 Unicode code points — the
                              server binds these to varchar(255) and rejects
                              longer values with an opaque error

After all fatal checks pass, an ADVISORY scored-field completeness pass
warns (stdout, prefix "stride-ideation: warning:") for any task whose
review-queue scored field (acceptance_criteria, testing_strategy,
security_considerations, pitfalls, patterns_to_follow) is missing or empty —
each renders an empty review-queue pill once the task ships. Warnings are
non-fatal by design: the exit code stays 0.

Beyond (f) and the advisory pass, the validator still does NOT enforce
per-task Stride-API field shapes (pitfalls-as-array-of-strings,
verification_steps-as-objects, etc.). Those are the decomposer agent's
responsibility; /ship surfaces the API's own error if anything slips
through. Length is checked ONLY on the fields the server actually bounds:
title (goal and task) and each security_considerations element. pitfalls
elements and key_files notes are JSONB on the server (unbounded) — checking
them would reject batches the server accepts.
"""

import json
import sys
from typing import Any


def fail(message: str) -> "None":
    sys.stderr.write(f"stride-ideation: {message}\n")
    sys.exit(1)


def warn(message: str) -> "None":
    sys.stdout.write(f"stride-ideation: warning: {message}\n")


# The server binds these columns to varchar(255), which limits by Unicode
# code point — Python's len() on a str counts code points identically.
MAX_VARCHAR = 255

# The five review-queue scored fields; a missing or empty one renders an
# empty pill on every task of every goal shipped through /stridify.
SCORED_FIELDS = (
    "acceptance_criteria",
    "testing_strategy",
    "security_considerations",
    "pitfalls",
    "patterns_to_follow",
)


def check_length(json_path: str, value: "Any") -> "None":
    # Only strings are measured — shape enforcement stays out of scope.
    if isinstance(value, str) and len(value) > MAX_VARCHAR:
        fail(
            f"{json_path} is {len(value)} characters — the server column "
            f"is varchar(255) and rejects longer values"
        )


def validate(path: str) -> "None":
    try:
        with open(path, "r", encoding="utf-8") as fp:
            text = fp.read()
    except OSError as exc:
        fail(f"could not read {path}: {exc}")

    # (a) parse_error
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as exc:
        fail(
            f"JSON parse failed at line {exc.lineno} col {exc.colno} "
            f"(char {exc.pos}): {exc.msg}"
        )

    if not isinstance(doc, dict):
        fail(
            f"top-level JSON value must be an object, got {type(doc).__name__}"
        )

    # (b) wrong_root_key
    if "goals" not in doc:
        if "tasks" in doc:
            fail(
                "root key 'tasks' is the most common batch-API mistake — "
                "Stride's POST /api/tasks/batch requires root key 'goals'. "
                "Rename 'tasks' to 'goals' at the JSON root and retry."
            )
        # Surface whatever non-'goals' key the agent picked instead.
        unexpected = [k for k in doc.keys() if k not in (
            "source_spec",
            "source_spec_sha256",
            "decomposition_notes",
        )]
        if unexpected:
            fail(
                f"root object is missing the required 'goals' array "
                f"(saw unexpected key(s): {sorted(unexpected)})"
            )
        fail("root object is missing the required 'goals' array")

    # (c) empty_goals
    goals = doc["goals"]
    if not isinstance(goals, list):
        fail(
            f"root.goals must be an array, got {type(goals).__name__}"
        )
    if len(goals) == 0:
        fail(
            "root.goals is an empty array — the decomposer returned no goals; "
            "check the requirements doc for under-specification"
        )

    # (d) goal_missing_field
    for goal_idx, goal in enumerate(goals):
        if not isinstance(goal, dict):
            fail(
                f"goals[{goal_idx}] must be an object, "
                f"got {type(goal).__name__}"
            )
        for required in ("title", "type", "tasks"):
            if required not in goal:
                fail(
                    f"goals[{goal_idx}] is missing required field '{required}'"
                )
        if not isinstance(goal["title"], str) or not goal["title"].strip():
            fail(f"goals[{goal_idx}].title must be a non-empty string")
        if goal["type"] != "goal":
            fail(
                f"goals[{goal_idx}].type must be 'goal', "
                f"got {goal['type']!r}"
            )
        if not isinstance(goal["tasks"], list):
            fail(
                f"goals[{goal_idx}].tasks must be an array, "
                f"got {type(goal['tasks']).__name__}"
            )
        if len(goal["tasks"]) == 0:
            fail(
                f"goals[{goal_idx}].tasks is empty — every goal must "
                f"own at least one task"
            )

        # (f) length_limit — goal level
        check_length(f"goals[{goal_idx}].title", goal["title"])
        goal_sec = goal.get("security_considerations")
        if isinstance(goal_sec, list):
            for elem_idx, elem in enumerate(goal_sec):
                check_length(
                    f"goals[{goal_idx}].security_considerations[{elem_idx}]",
                    elem,
                )

        # (e) bad_dependency_index + (f) length_limit — task level
        for task_idx, task in enumerate(goal["tasks"]):
            if not isinstance(task, dict):
                fail(
                    f"goals[{goal_idx}].tasks[{task_idx}] must be an object, "
                    f"got {type(task).__name__}"
                )
            check_length(
                f"goals[{goal_idx}].tasks[{task_idx}].title",
                task.get("title"),
            )
            task_sec = task.get("security_considerations")
            if isinstance(task_sec, list):
                for elem_idx, elem in enumerate(task_sec):
                    check_length(
                        f"goals[{goal_idx}].tasks[{task_idx}]"
                        f".security_considerations[{elem_idx}]",
                        elem,
                    )
            deps = task.get("dependencies", [])
            if not isinstance(deps, list):
                fail(
                    f"goals[{goal_idx}].tasks[{task_idx}].dependencies must "
                    f"be an array, got {type(deps).__name__}"
                )
            for dep_pos, dep in enumerate(deps):
                # String identifiers (e.g. 'W47') reference pre-existing tasks
                # outside the batch — they are not validated here.
                if isinstance(dep, str):
                    continue
                if not isinstance(dep, int) or isinstance(dep, bool):
                    fail(
                        f"goals[{goal_idx}].tasks[{task_idx}]"
                        f".dependencies[{dep_pos}] must be a non-negative "
                        f"integer index or a string identifier, "
                        f"got {dep!r}"
                    )
                if dep < 0:
                    fail(
                        f"goals[{goal_idx}].tasks[{task_idx}]"
                        f".dependencies[{dep_pos}] = {dep} is negative"
                    )
                if dep >= len(goal["tasks"]):
                    fail(
                        f"goals[{goal_idx}].tasks[{task_idx}]"
                        f".dependencies references index {dep} but goal "
                        f"only has {len(goal['tasks'])} tasks "
                        f"(valid indices 0..{len(goal['tasks']) - 1})"
                    )
                if dep >= task_idx:
                    # Self-reference or forward reference — both are invalid;
                    # array-index dependencies must point to a task that
                    # appears EARLIER in the same goal's tasks array.
                    fail(
                        f"goals[{goal_idx}].tasks[{task_idx}]"
                        f".dependencies references index {dep} which is at "
                        f"or after the referencing task's own position "
                        f"{task_idx} — array-index dependencies must point "
                        f"to an earlier sibling"
                    )

    # All fatal checks passed — advisory scored-field completeness pass.
    # Warnings never precede a fatal exit (every fail() above returns first)
    # and never change the exit code.
    for goal_idx, goal in enumerate(goals):
        for task_idx, task in enumerate(goal["tasks"]):
            for field in SCORED_FIELDS:
                value = task.get(field)
                if (
                    value is None
                    or value == []
                    or value == {}
                    or (isinstance(value, str) and not value.strip())
                ):
                    warn(
                        f"goals[{goal_idx}].tasks[{task_idx}].{field} is "
                        f"empty or missing — scored field will render an "
                        f"empty review-queue pill"
                    )


def main(argv: "list[str]") -> "None":
    if len(argv) != 2:
        sys.stderr.write(
            "usage: validate_batch.py <path-to-stride-batch.json>\n"
        )
        sys.exit(2)
    validate(argv[1])


if __name__ == "__main__":
    main(sys.argv)
