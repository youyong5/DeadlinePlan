# deadlineplan

`youyong5/deadlineplan` is a small, reusable MoonBit library for planning deadline-bound tasks. It deliberately models generic work rather than a particular domain: a student timetable and a software delivery plan can use the same API.

The **MoonBit scheduling library is the primary deliverable**. The CLI and interactive academic/project page are application examples; no `Course`, `Homework`, or `Exam` type is part of the core API.

## Start from a clone

Install the [MoonBit toolchain](https://docs.moonbitlang.com/en/latest/tutorial/tour.html) and Node.js 24 or newer, then run these commands from a terminal:

```sh
git clone https://github.com/youyong5/DeadlinePlan.git
cd DeadlinePlan
moon run examples/library_demo
moon run --target js cmd/deadlineplan -- examples/student-plan.v1.json
node demo/build.mjs
node demo/serve.mjs
```

The first command after cloning invokes the public MoonBit `schedule(...)` API directly and prints `draft: [0, 30)`, `review: [50, 70)`, and `Unscheduled: 0`. The second uses the CLI to parse the versioned JSON example and schedule it through the same public library. The last two build and serve the browser example at <http://127.0.0.1:4173>; stop its server with Ctrl+C. Switch to **项目交付** in the page for a non-academic example. See the sections below for the full API, JSON rules, and alternative CLI commands.

All times are signed 32-bit integer UTC minutes relative to the Unix epoch. Negative values are valid. Every interval is half-open: `[start, end)`. An event ending at minute `60` does not conflict with work beginning at minute `60`; a task may finish exactly at its deadline.

## Public API

- `window(start, end)` creates an available time window.
- `fixed_event(id, start, end)` creates occupied time.
- `task(id, duration_minutes, deadline, dependencies)` creates a task.
- `task_with_earliest_start(id, duration_minutes, deadline, dependencies, earliest_start)` creates a task that cannot begin before `earliest_start`.
- `splittable_task(id, duration_minutes, deadline, dependencies, minimum_block_minutes)` creates a task whose total work may span several blocks.
- `splittable_task_with_earliest_start(id, duration_minutes, deadline, dependencies, earliest_start, minimum_block_minutes)` also sets its earliest start.
- `completed_task(id, completed_at)` records a task's actual completion minute.
- `schedule(availability, fixed_events, tasks)` validates the input and returns `Result[Schedule, ValidationError]`.
- `schedule_with_completed(availability, fixed_events, tasks, completed)` also accepts an array of completion records. The original `schedule(...)` is equivalent to passing an empty array.
- `schedule_with_confirmed_blocks(availability, fixed_events, tasks, completed, confirmed_blocks)` keeps `ScheduledBlock` values in place while replanning other tasks and the unconfirmed remainder of splittable tasks.
- `parse_plan_json(source)` parses a versioned plan document, checks field shape and then calls `schedule_with_confirmed_blocks(...)` for input validation. It returns `Result[PlanDocument, PlanJsonError]`.
- `serialize_plan_json(document)` validates a document through the same entry and returns `Result[String, PlanJsonError]`. Array order is preserved.

## JSON plan format (schema version 1)

Every numeric time is a signed 32-bit **integer UTC minute since 1970-01-01T00:00:00Z**; intervals are `[start, end)`. This is a complete example (also present as `examples/student-plan.v1.json`):

```json
{
  "schema_version": 1,
  "availability": [{ "start": 29875680, "end": 29876220 }],
  "fixed_events": [
    { "id": "morning-lecture", "start": 29875740, "end": 29875830 },
    { "id": "afternoon-lecture", "start": 29875980, "end": 29876070 },
    { "id": "biology-exam", "start": 29876160, "end": 29876220 }
  ],
  "tasks": [
    { "id": "topic-announced", "duration_minutes": 1, "deadline": 29875681, "dependencies": [] },
    { "id": "calculus-homework", "duration_minutes": 60, "deadline": 29875980, "dependencies": ["topic-announced"], "earliest_start": 29875830 },
    { "id": "biology-review", "duration_minutes": 210, "deadline": 29876160, "dependencies": ["topic-announced"], "minimum_block_minutes": 60 },
    { "id": "exam-setup", "duration_minutes": 30, "deadline": 29876220, "dependencies": ["biology-review"] }
  ],
  "completed": [{ "id": "topic-announced", "completed_at": 29875680 }],
  "confirmed_blocks": [{ "task_id": "biology-review", "start": 29875680, "end": 29875740 }]
}
```

All six top-level fields are required. `fixed_events`, `completed`, and `confirmed_blocks` may be empty arrays. Every task needs `id`, `duration_minutes`, `deadline`, and `dependencies`; `earliest_start` and `minimum_block_minutes` may be absent or `null`. A missing minimum means a continuous task; a positive minimum means splittable work. `0` is an actual minute, never an unset marker. An application can attach display names and locations to IDs outside this scheduling document.

Version 1 readers accept only `schema_version: 1`; a missing, mistyped, old, or future version is not guessed or migrated. `PlanJsonError` distinguishes `JsonSyntax(message)`, `MissingField(path)`, `WrongType(path, expected)`, `UnexpectedField(path)`, `UnsupportedSchemaVersion(version)`, and `InvalidPlanInput(path, ValidationError)`. Paths are JSON Pointers such as `/tasks/1/dependencies/0` (the root is `""`). Syntax messages come from the MoonBit JSON parser and include its position when available. Scheduler validation remains the single source of truth for dependencies, durations, time windows, completed records, and confirmed blocks. Unknown object fields are rejected, rather than silently dropped during a round trip; keep application-only display data outside this format. Parsed record-array order is preserved on serialization, including task order, which breaks equal-deadline ties. A version 1 writer should preserve this order and must not reinterpret minutes as local time or seconds.

`task(...)` leaves `Task.earliest_start` and `Task.minimum_block_minutes` as `None`: the task must occupy one continuous block. The earliest-start constructor sets `earliest_start` to `Some(minute)`. The splittable constructors set `minimum_block_minutes` to `Some(minutes)`. Minute `0` is an ordinary UTC minute, not an unset marker. All constructors produce tasks for the same `schedule(...)` call.

`Schedule.blocks` contains placed work blocks; a splittable task can have several blocks with the same task ID. A completed task stays in `tasks` so its ID and dependencies are known, but it produces no new block, does not appear in `Schedule.unscheduled`, and reserves no availability. Its actual `completed_at` constrains successors, even if it lies outside availability or after that task's own deadline. Minute `0` is a real completion time, not an unset marker. A successor starts no earlier than the latest of its explicit earliest start, each completed prerequisite's `completed_at`, and each newly scheduled prerequisite's last block end.

`Schedule.unscheduled` records `NoContinuousSlot` for a continuous task without a slot, `SplitWorkIncomplete(remaining_minutes)` for a splittable task that cannot fit in the free time available at its turn, or `DependencyNotScheduled(dependency_id)` for a blocked successor. A completed prerequisite whose time falls at or after a successor's deadline is **scheduled**, not missing: the successor receives `NoContinuousSlot` or `SplitWorkIncomplete` as appropriate. For a split task without confirmed progress, `remaining_minutes` is its entire duration. With partial confirmation, it is **total duration minus confirmed minutes**. Failed attempts commit no *new* blocks; existing confirmed blocks remain in `Schedule.blocks` and reserve time, even though that task is in `Schedule.unscheduled`.

The replanning entry accepts complete or **partial confirmation of splittable tasks**. A continuous task still needs exactly one confirmed block of its full duration. Each confirmed split block must meet its minimum length; the confirmed lengths may sum to less than the task duration, but never more. Only the missing minutes are newly scheduled. A partially confirmed task becomes a satisfied prerequisite **only when all missing minutes have also been placed**. Confirmed blocks are returned first in input order at their original times; newly scheduled blocks follow in decision order. They reserve time but are never moved. Completed tasks still reserve no time, and a task cannot be both completed and confirmed.

Validation rejects empty or inverted windows, non-positive task durations, duplicate task IDs, unknown dependencies, and dependency cycles, including cycles involving completed tasks. Completion records must reference a task in `tasks`, with at most one record per task; violations return `UnknownCompletedTaskId(id)` or `DuplicateCompletedTaskId(id)`. It returns `InvalidEarliestStart(task_id, earliest_start, deadline)` when an explicit earliest start is at or after the deadline, and `InvalidMinimumBlock(task_id, minimum_block_minutes, duration_minutes)` when the minimum is non-positive or exceeds total work. An earlier start with too little time to fit a continuous task is valid input and yields `NoContinuousSlot`; so does a deadline before all available time on a task without an explicit start.

`schedule_with_confirmed_blocks` additionally validates every confirmed block's task ID, positive length, containment in the union of availability windows, explicit earliest start, deadline, split minimum, and absence of overlap with fixed events or other confirmed blocks. It rejects wrong continuous block counts, continuous partial durations, and any over-confirmed duration. These cases have dedicated `ValidationError` variants such as `InvalidConfirmedWindow`, `ConfirmedOutsideAvailability`, `ConfirmedDurationMismatch`, `ConfirmedOverlapsFixedEvent`, and `ConfirmedBlocksOverlap`.

This entry also checks the actual timeline of tasks already completed or with confirmed blocks. Every prerequisite of such a task must itself be completed or **fully** confirmed; a partially confirmed prerequisite is not finished and produces `UnresolvedPriorDependency(task_id, prerequisite_id)`. A prerequisite finishing after the completed task's actual completion, or after the first confirmed block of a task, returns `PriorDependencyFinishesLate(task_id, prerequisite_id, finished_at, actual_time)`. Equal boundary minutes are allowed. The older `schedule(...)` and `schedule_with_completed(...)` keep their previous behavior; this additional timeline check belongs to the replanning entry.

## Behaviour

This is an initial deterministic greedy scheduler **across tasks**. Once all dependencies of a task are scheduled, it chooses the ready task with the earliest deadline (input order breaks equal deadlines). Continuous tasks use the earliest whole slot. For each selected splittable task, the scheduler considers free gaps in time order and takes as much as possible from the current gap while preserving a feasible allocation in later gaps. A task starts no earlier than its explicit earliest start or the completion of any prerequisite, and every block must end by its deadline. Fixed events and already scheduled work occupy time.

Without confirmed progress, every block of a splittable task, including the final block, must be at least `minimum_block_minutes` long. **Only when some work is already confirmed**, at most one final *newly placed* block may be shorter than that minimum to finish the exact remaining duration. For example, a 60-minute task with a 40-minute minimum and one confirmed 50-minute block may take a final 10-minute block. Other new blocks and all confirmed blocks still meet the minimum. A gap may be shortened or skipped so that later gaps can hold the remainder. The allocation test works on gap lengths, without a per-minute time table. `SplitWorkIncomplete(remaining_minutes)` is not proof that another task order or reschedule of earlier work could not make room.

Availability windows may be unordered, overlapping, duplicated, or touching; their union is treated as continuous available time. Task blocks do not overlap fixed events or other task blocks, even if several availability windows cover the same minutes. Without confirmed blocks, `Schedule.blocks` records scheduling decision order; with confirmed blocks, their input order comes first, so the array need not be chronological. New work for a partially confirmed task may be placed before an existing confirmed block if a legal earlier gap exists; its successor still waits for the latest end among **all** of that task's blocks. The scheduler never changes the caller's input arrays.

An unscheduled task **does not mean** that no feasible schedule for all tasks exists mathematically. A different ordering can produce a better outcome. This library does not parse iCalendar data, implement recurrence rules, or provide general resource reservation; those directions are already covered by Mooncakes projects.

## Example outcomes

The examples are public-API tests in `tests/scheduling_test.mbt`, `tests/splittable_test.mbt`, `tests/completed_test.mbt`, `tests/confirmed_test.mbt`, and `tests/partial_confirmed_test.mbt`.

- Student example: homework is assigned at minute `15`; `math-homework` is `[15, 60)`. Two lectures occupy `[60, 90)` and `[120, 150)`, so splittable `biology-exam-review` completes before minute `180` in `[90, 120)` and `[150, 180)`. `history-essay` remains unscheduled with `NoContinuousSlot`.
- Project delivery example: materials arrive at minute `170`; `draft` is `[0, 90)`, `review` `[90, 120)`, and `release-package` `[170, 230)`; all tasks are scheduled.
- Split project handoff example: `draft` is `[0, 30)`, `handoff` is `[60, 100)` and `[120, 140)` around two fixed events, and dependent `delivery-review` begins at `[140, 150)`.
- Student to-do example with a completed prerequisite: `assignment-briefing` finished at minute `30` without occupying the new plan. A lecture occupies `[40, 50)`, so `homework` is `[50, 70)` and `quiz-preparation` is `[70, 80)`.
- Project to-do example with completed prerequisites: `materials-ready` finished at `25` and `approval` at `72`. `assembly` is `[25, 40)`, split `documentation` is `[40, 50)` and `[60, 70)`, and `handoff` waits for both documentation and approval before occupying `[72, 77)`.
- Student replan: confirmed `homework` stays `[0, 10)` when a new lecture occupies `[20, 35)`. `exam-review` moves from `[10, 25)` to `[35, 50)`, and `summary` moves from `[25, 35)` to `[50, 60)`.
- Project replan: confirmed split `design` stays `[0, 10)` and `[20, 30)`. A new vendor call occupies `[30, 45)`, so `build` takes `[45, 60)`; `handoff` waits for both `build` and an approval completed at `65`, then takes `[65, 75)`.
- Student partial-progress replan: `biology-review` keeps confirmed `[0, 20)` and finishes around two lectures in `[40, 60)` and `[80, 100)`; dependent `exam-setup` is `[100, 110)`.
- Project partial-progress replan: `design` keeps confirmed `[0, 30)` and adds `[50, 90)` after a vendor call. `release` waits for design and an approval completed at `100`, then takes `[100, 110)`.
- JSON student file: a completed `topic-announced` record and confirmed 2026-10-21 00:00–01:00 UTC `biology-review` block leave room for `calculus-homework` at 02:30–03:30, review at 03:30–05:00 and 06:30–07:30, and `exam-setup` at 07:30–08:00 UTC. The fixed biology exam follows at 08:00–09:00 UTC.
- JSON project file: on 2026-10-22 UTC, `design` keeps 00:00–00:30 and adds 00:50–01:30 around a vendor call; with `approval` completed at 01:40, `release` is 01:40–01:50.

## Command-line demo

The runnable package is `cmd/deadlineplan`. It uses the library's public `parse_plan_json(...)` and `schedule_with_confirmed_blocks(...)`; no JSON schema or scheduling logic is copied into the CLI. It is a JS-target demo using Node's file API and UTC `Date` formatter, so Node.js must be installed. Run these commands from the project root. The `--` passes CLI flags through `moon run`:

```sh
moon run --target js cmd/deadlineplan -- examples/student-plan.v1.json
moon run --target js cmd/deadlineplan -- examples/project-plan.v1.json
moon run --target js cmd/deadlineplan -- --json examples/student-plan.v1.json
moon run --target js cmd/deadlineplan -- --help
```

The student command prints:

```text
Scheduled blocks (5):
  confirmed biology-review: [2026-10-21T00:00Z, 2026-10-21T01:00Z)
  planned calculus-homework: [2026-10-21T02:30Z, 2026-10-21T03:30Z)
  planned biology-review: [2026-10-21T03:30Z, 2026-10-21T05:00Z)
  planned biology-review: [2026-10-21T06:30Z, 2026-10-21T07:30Z)
  planned exam-setup: [2026-10-21T07:30Z, 2026-10-21T08:00Z)
Unscheduled tasks (0):
```

The project command prints three blocks: confirmed `design` `[2026-10-22T00:00Z, 00:30Z)`, planned `design` `[00:50Z, 01:30Z)`, and `release` `[01:40Z, 01:50Z)`. The `--json` result has `result_version: 1`, `time_unit: "utc_minutes_since_unix_epoch"`, chronological `blocks` with `task_id`, `start`, `end`, and `confirmed`, plus `unscheduled` entries whose `reason.code` and detail fields state the failure. JSON mode writes only one JSON object to stdout. Text mode formats ordinary minutes as UTC dates; minutes outside its safe date formatter are shown as raw `minute N`. No local time zone is inferred.

`--help` and successful planning exit `0`, including plans with unscheduled tasks; their reasons remain visible in either output mode. File-read, JSON, or input-validation failures exit `1`; invalid or unknown command-line arguments exit `2`. Errors and usage failures go to stderr, leaving stdout empty. The machine-readable result format is separate from the input schema and is versioned independently.

## Local interactive demo

The single-page demo uses the same version 1 JSON example files. From the repository root, with MoonBit and Node.js installed:

```sh
node demo/build.mjs
node demo/serve.mjs
```

Open <http://127.0.0.1:4173> in a browser. The build command runs `moon build --target js demo/bridge`, then copies its JS module, the page, and both JSON examples into `demo/dist/`; the server serves only that local directory. Stop it with Ctrl+C. Re-run the build after changing MoonBit or page source. No account, cloud service, publication, or iCalendar parser is involved.

The initial academic view shows two classes with room labels, a fixed exam, assignments/review, their deadlines, and the five scheduled work blocks (one confirmed). Select **项目交付** to show the 2026-10-22 vendor meeting, design, completed approval, and release using the same widgets and core call. Edit a task's work minutes or deadline, or add/remove a temporary fixed event: every change sends the current plan JSON to MoonBit and updates the timeline and unscheduled reasons immediately. A new event that overlaps a confirmed block gives `ConfirmedOverlapsFixedEvent` instead of moving that block; on invalid input, the error banner is current and the timeline is explicitly the **last valid** schedule. Valid inputs with unscheduled work show `NoContinuousSlot`, `SplitWorkIncomplete`, or `DependencyNotScheduled` as returned by the library. Refreshing or switching scenarios resets local edits.

Display labels, event categories, classrooms, and meeting places live only in `demo/web/app.js`, keyed by task/event ID. `demo/bridge/bridge.mbt` calls the public `parse_plan_json(...)` and `schedule_with_confirmed_blocks(...)`; JavaScript handles editing, local-time display, and rendering only. The plan format still stores Unix UTC integer minutes; the browser converts them to its local timezone when displaying or accepting `datetime-local` values. The [browser screenshot](demo/screenshot.png) shows the initial academic view in Asia/Shanghai time.

To repeat the actual browser checks and refresh the screenshot on Windows with Chrome installed (set `CHROME_BIN` if Chrome is elsewhere):

```sh
node demo/build.mjs
node tests/demo-browser-smoke.mjs
```

That check starts and stops its own local server and headless browser, then verifies both scenes, an edited task, a valid temporary event, a conflicting event, unchanged confirmed blocks, and a browser-captured screenshot.

## Development

```sh
moon fmt
moon check --deny-warn
moon test
moon test --target js # also reads and schedules both JSON example files from disk
node demo/build.mjs
node tests/demo-browser-smoke.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests/cli-smoke.ps1
```

GitHub Actions runs these checks in a clean Ubuntu environment, installs MoonBit and Node.js, builds the JS bridge, and verifies the CLI and both browser scenarios in headless Chrome. The browser test can use `CHROME_BIN` to select Chrome and `DEADLINEPLAN_SCREENSHOT=0` to avoid rewriting the checked-in screenshot.

## Packaging and release scope

`moon.mod` declares the `youyong5/deadlineplan` module at version `0.1.0`, Apache-2.0, this README, and the repository URL. The root package is the reusable library. `moon package --list` inspects the prospective Mooncakes archive without publishing it: `.moonignore` keeps local tooling, tests, the CLI, and the browser demo out of that archive, while retaining the library and runnable example inputs. The GitHub repository contains the full source and demos. No `moon publish` step is part of CI.
