# deadlineplan

`youyong5/deadlineplan` is a small, reusable MoonBit library for planning deadline-bound tasks. It deliberately models generic work rather than a particular domain: a student timetable and a software delivery plan can use the same API.

All times are integer UTC minutes. Every interval is half-open: `[start, end)`. This means an event ending at minute `60` does not conflict with work beginning at minute `60`.

## Public API

- `window(start, end)` creates an available time window.
- `fixed_event(id, start, end)` creates occupied time.
- `task(id, duration_minutes, deadline, dependencies)` creates a task.
- `schedule(availability, fixed_events, tasks)` validates the input and returns `Result[Schedule, ValidationError]`.

`Schedule.blocks` contains the placed continuous task blocks and `Schedule.unscheduled` records each task that could not be placed, as either `NoContinuousSlot` or `DependencyNotScheduled(dependency_id)`.

Validation rejects empty or inverted windows, non-positive task durations, duplicate task IDs, unknown dependencies, and dependency cycles.

## Behaviour

This is an initial deterministic greedy scheduler. Once all dependencies of a task are scheduled, it chooses the ready task with the earliest deadline (input order breaks equal deadlines) and places it in the earliest continuous feasible window. Fixed events and already scheduled work occupy time.

An unscheduled task **does not mean** that no feasible solution exists mathematically. A different ordering can produce a better outcome. This library does not parse iCalendar data, implement recurrence rules, or provide general resource reservation; those directions are already covered by Mooncakes projects.

## Two example outcomes

The public-API tests in `tests/scheduling_test.mbt` include both scenarios.

- Student example: `math-homework` is scheduled `[0, 45)`, `biology-exam-review` `[90, 130)`, and `history-essay` is unscheduled with `NoContinuousSlot`.
- Project delivery example: `draft` is `[0, 90)`, `review` `[90, 120)`, and `release-package` `[150, 210)`; all tasks are scheduled.

## Development

```sh
moon fmt
moon check
moon test
```
