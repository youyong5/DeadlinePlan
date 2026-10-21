# deadlineplan

`youyong5/deadlineplan` is a small, reusable MoonBit library for planning deadline-bound tasks. It deliberately models generic work rather than a particular domain: a student timetable and a software delivery plan can use the same API.

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

`task(...)` leaves `Task.earliest_start` and `Task.minimum_block_minutes` as `None`: the task must occupy one continuous block. The earliest-start constructor sets `earliest_start` to `Some(minute)`. The splittable constructors set `minimum_block_minutes` to `Some(minutes)`. Minute `0` is an ordinary UTC minute, not an unset marker. All constructors produce tasks for the same `schedule(...)` call.

`Schedule.blocks` contains placed work blocks; a splittable task can have several blocks with the same task ID. A completed task stays in `tasks` so its ID and dependencies are known, but it produces no new block, does not appear in `Schedule.unscheduled`, and reserves no availability. Its actual `completed_at` constrains successors, even if it lies outside availability or after that task's own deadline. Minute `0` is a real completion time, not an unset marker. A successor starts no earlier than the latest of its explicit earliest start, each completed prerequisite's `completed_at`, and each newly scheduled prerequisite's last block end.

`Schedule.unscheduled` records `NoContinuousSlot` for a continuous task without a slot, `SplitWorkIncomplete(remaining_minutes)` for a splittable task that cannot fit in the free time available at its turn, or `DependencyNotScheduled(dependency_id)` for a blocked successor. A completed prerequisite whose time falls at or after a successor's deadline is **scheduled**, not missing: the successor receives `NoContinuousSlot` or `SplitWorkIncomplete` as appropriate. A failed split task leaves no blocks or reservations behind, so `remaining_minutes` is its **entire duration**, not a partially placed deficit.

Validation rejects empty or inverted windows, non-positive task durations, duplicate task IDs, unknown dependencies, and dependency cycles, including cycles involving completed tasks. Completion records must reference a task in `tasks`, with at most one record per task; violations return `UnknownCompletedTaskId(id)` or `DuplicateCompletedTaskId(id)`. It returns `InvalidEarliestStart(task_id, earliest_start, deadline)` when an explicit earliest start is at or after the deadline, and `InvalidMinimumBlock(task_id, minimum_block_minutes, duration_minutes)` when the minimum is non-positive or exceeds total work. An earlier start with too little time to fit a continuous task is valid input and yields `NoContinuousSlot`; so does a deadline before all available time on a task without an explicit start.

## Behaviour

This is an initial deterministic greedy scheduler **across tasks**. Once all dependencies of a task are scheduled, it chooses the ready task with the earliest deadline (input order breaks equal deadlines). Continuous tasks use the earliest whole slot. For each selected splittable task, the scheduler considers free gaps in time order and takes as much as possible from the current gap while preserving a feasible allocation in later gaps. A task starts no earlier than its explicit earliest start or the completion of any prerequisite, and every block must end by its deadline. Fixed events and already scheduled work occupy time.

Every block of a splittable task, including the final block, must be at least `minimum_block_minutes` long, and the block lengths sum exactly to its total duration. A gap may be shortened or skipped so that later gaps can hold the remainder. For the *currently free gaps* of one task, the allocation test is complete: choosing the `k` largest-capacity later gaps can hold every integer amount from `k × minimum_block_minutes` through the sum of those gaps' capacities. This works on gap lengths, without a per-minute time table. Thus `SplitWorkIncomplete(remaining_minutes)` means no full allocation exists for that task **with already scheduled tasks kept in place**. It does not mean another task order or a reschedule of earlier work could not make room.

Availability windows may be unordered, overlapping, duplicated, or touching; their union is treated as continuous available time. Task blocks do not overlap fixed events or other task blocks, even if several availability windows cover the same minutes. `Schedule.blocks` records scheduling decision order, which may differ from chronological order. The scheduler never changes the caller's input arrays.

An unscheduled task **does not mean** that no feasible schedule for all tasks exists mathematically. A different ordering can produce a better outcome. This library does not parse iCalendar data, implement recurrence rules, or provide general resource reservation; those directions are already covered by Mooncakes projects.

## Example outcomes

The examples are public-API tests in `tests/scheduling_test.mbt`, `tests/splittable_test.mbt`, and `tests/completed_test.mbt`.

- Student example: homework is assigned at minute `15`; `math-homework` is `[15, 60)`. Two lectures occupy `[60, 90)` and `[120, 150)`, so splittable `biology-exam-review` completes before minute `180` in `[90, 120)` and `[150, 180)`. `history-essay` remains unscheduled with `NoContinuousSlot`.
- Project delivery example: materials arrive at minute `170`; `draft` is `[0, 90)`, `review` `[90, 120)`, and `release-package` `[170, 230)`; all tasks are scheduled.
- Split project handoff example: `draft` is `[0, 30)`, `handoff` is `[60, 100)` and `[120, 140)` around two fixed events, and dependent `delivery-review` begins at `[140, 150)`.
- Student to-do example with a completed prerequisite: `assignment-briefing` finished at minute `30` without occupying the new plan. A lecture occupies `[40, 50)`, so `homework` is `[50, 70)` and `quiz-preparation` is `[70, 80)`.
- Project to-do example with completed prerequisites: `materials-ready` finished at `25` and `approval` at `72`. `assembly` is `[25, 40)`, split `documentation` is `[40, 50)` and `[60, 70)`, and `handoff` waits for both documentation and approval before occupying `[72, 77)`.

## Development

```sh
moon fmt
moon check --deny-warn
moon test
```
