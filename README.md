# deadlineplan

`youyong5/deadlineplan` is a small, reusable MoonBit library for planning deadline-bound tasks. It deliberately models generic work rather than a particular domain: a student timetable and a software delivery plan can use the same API.

All times are signed 32-bit integer UTC minutes relative to the Unix epoch. Negative values are valid. Every interval is half-open: `[start, end)`. An event ending at minute `60` does not conflict with work beginning at minute `60`; a task may finish exactly at its deadline.

## Public API

- `window(start, end)` creates an available time window.
- `fixed_event(id, start, end)` creates occupied time.
- `task(id, duration_minutes, deadline, dependencies)` creates a task.
- `task_with_earliest_start(id, duration_minutes, deadline, dependencies, earliest_start)` creates a task that cannot begin before `earliest_start`.
- `schedule(availability, fixed_events, tasks)` validates the input and returns `Result[Schedule, ValidationError]`.

`task(...)` leaves `Task.earliest_start` as `None`; the new constructor sets it to `Some(minute)`. Minute `0` is an ordinary UTC minute, not an unset marker. Both constructors produce tasks for the same `schedule(...)` call.

`Schedule.blocks` contains the placed continuous task blocks and `Schedule.unscheduled` records each task that could not be placed, as either `NoContinuousSlot` or `DependencyNotScheduled(dependency_id)`.

Validation rejects empty or inverted windows, non-positive task durations, duplicate task IDs, unknown dependencies, and dependency cycles. It returns `InvalidEarliestStart(task_id, earliest_start, deadline)` when an explicit earliest start is at or after the deadline. An earlier start with too little time to fit the task is valid input and yields `NoContinuousSlot`; so does a deadline before all available time on a task without an explicit start.

## Behaviour

This is an initial deterministic greedy scheduler. Once all dependencies of a task are scheduled, it chooses the ready task with the earliest deadline (input order breaks equal deadlines) and places it in the earliest continuous feasible window. A task starts no earlier than its explicit earliest start or the completion of any prerequisite, and its whole block must end by its deadline. Fixed events and already scheduled work occupy time.

Availability windows may be unordered, overlapping, duplicated, or touching; their union is treated as continuous available time. Task blocks do not overlap fixed events or other task blocks, even if several availability windows cover the same minutes. `Schedule.blocks` records scheduling decision order, which may differ from chronological order. The scheduler never changes the caller's input arrays.

An unscheduled task **does not mean** that no feasible solution exists mathematically. A different ordering can produce a better outcome. This library does not parse iCalendar data, implement recurrence rules, or provide general resource reservation; those directions are already covered by Mooncakes projects.

## Two example outcomes

The public-API tests in `tests/scheduling_test.mbt` include both scenarios.

- Student example: homework is assigned at minute `15`; `math-homework` is scheduled `[15, 60)`, `biology-exam-review` `[90, 130)`, and `history-essay` is unscheduled with `NoContinuousSlot`.
- Project delivery example: materials arrive at minute `170`; `draft` is `[0, 90)`, `review` `[90, 120)`, and `release-package` `[170, 230)`; all tasks are scheduled.

## Development

```sh
moon fmt
moon check --deny-warn
moon test
```
