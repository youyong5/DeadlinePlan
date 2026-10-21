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
- `schedule(availability, fixed_events, tasks)` validates the input and returns `Result[Schedule, ValidationError]`.

`task(...)` leaves `Task.earliest_start` and `Task.minimum_block_minutes` as `None`: the task must occupy one continuous block. The earliest-start constructor sets `earliest_start` to `Some(minute)`. The splittable constructors set `minimum_block_minutes` to `Some(minutes)`. Minute `0` is an ordinary UTC minute, not an unset marker. All constructors produce tasks for the same `schedule(...)` call.

`Schedule.blocks` contains placed work blocks; a splittable task can have several blocks with the same task ID. `Schedule.unscheduled` records `NoContinuousSlot` for a continuous task without a slot, `SplitWorkIncomplete(remaining_minutes)` for a splittable task that cannot fit in the free time available at its turn, or `DependencyNotScheduled(dependency_id)` for a blocked successor. A failed split task leaves no blocks or reservations behind, so `remaining_minutes` is its **entire duration**, not a partially placed deficit. A successor can begin only after its predecessor's last block ends.

Validation rejects empty or inverted windows, non-positive task durations, duplicate task IDs, unknown dependencies, and dependency cycles. It returns `InvalidEarliestStart(task_id, earliest_start, deadline)` when an explicit earliest start is at or after the deadline, and `InvalidMinimumBlock(task_id, minimum_block_minutes, duration_minutes)` when the minimum is non-positive or exceeds total work. An earlier start with too little time to fit a continuous task is valid input and yields `NoContinuousSlot`; so does a deadline before all available time on a task without an explicit start.

## Behaviour

This is an initial deterministic greedy scheduler **across tasks**. Once all dependencies of a task are scheduled, it chooses the ready task with the earliest deadline (input order breaks equal deadlines). Continuous tasks use the earliest whole slot. For each selected splittable task, the scheduler considers free gaps in time order and takes as much as possible from the current gap while preserving a feasible allocation in later gaps. A task starts no earlier than its explicit earliest start or the completion of any prerequisite, and every block must end by its deadline. Fixed events and already scheduled work occupy time.

Every block of a splittable task, including the final block, must be at least `minimum_block_minutes` long, and the block lengths sum exactly to its total duration. A gap may be shortened or skipped so that later gaps can hold the remainder. For the *currently free gaps* of one task, the allocation test is complete: choosing the `k` largest-capacity later gaps can hold every integer amount from `k × minimum_block_minutes` through the sum of those gaps' capacities. This works on gap lengths, without a per-minute time table. Thus `SplitWorkIncomplete(remaining_minutes)` means no full allocation exists for that task **with already scheduled tasks kept in place**. It does not mean another task order or a reschedule of earlier work could not make room.

Availability windows may be unordered, overlapping, duplicated, or touching; their union is treated as continuous available time. Task blocks do not overlap fixed events or other task blocks, even if several availability windows cover the same minutes. `Schedule.blocks` records scheduling decision order, which may differ from chronological order. The scheduler never changes the caller's input arrays.

An unscheduled task **does not mean** that no feasible schedule for all tasks exists mathematically. A different ordering can produce a better outcome. This library does not parse iCalendar data, implement recurrence rules, or provide general resource reservation; those directions are already covered by Mooncakes projects.

## Example outcomes

The examples are public-API tests in `tests/scheduling_test.mbt` and `tests/splittable_test.mbt`.

- Student example: homework is assigned at minute `15`; `math-homework` is `[15, 60)`. Two lectures occupy `[60, 90)` and `[120, 150)`, so splittable `biology-exam-review` completes before minute `180` in `[90, 120)` and `[150, 180)`. `history-essay` remains unscheduled with `NoContinuousSlot`.
- Project delivery example: materials arrive at minute `170`; `draft` is `[0, 90)`, `review` `[90, 120)`, and `release-package` `[170, 230)`; all tasks are scheduled.
- Split project handoff example: `draft` is `[0, 30)`, `handoff` is `[60, 100)` and `[120, 140)` around two fixed events, and dependent `delivery-review` begins at `[140, 150)`.

## Development

```sh
moon fmt
moon check --deny-warn
moon test
```
