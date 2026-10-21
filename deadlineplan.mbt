///|
/// A half-open UTC-minute interval: `[start, end)`.
pub(all) struct TimeWindow {
  start : Int32
  end : Int32
}

///|
/// A period that cannot be used for task work.
pub(all) struct FixedEvent {
  id : String
  window : TimeWindow
}

///|
/// A unit of work to be scheduled after its dependencies have finished.
pub(all) struct Task {
  id : String
  duration_minutes : Int32
  deadline : Int32
  dependencies : Array[String]
  earliest_start : Int32?
}

///|
/// A continuous interval reserved for a task by the scheduler.
pub(all) struct ScheduledBlock {
  task_id : String
  window : TimeWindow
}

///|
/// Why a task could not be put on the greedy schedule.
pub(all) enum UnscheduledReason {
  NoContinuousSlot
  DependencyNotScheduled(String)
}

///|
/// A task that was not scheduled, with the reason recorded explicitly.
pub(all) struct UnscheduledTask {
  task_id : String
  reason : UnscheduledReason
}

///|
/// The output of a successful scheduling run.
pub(all) struct Schedule {
  blocks : Array[ScheduledBlock]
  unscheduled : Array[UnscheduledTask]
}

///|
/// Input errors detected before scheduling starts.
pub(all) enum ValidationError {
  InvalidWindow(String, String, Int32, Int32)
  InvalidTaskDuration(String, Int32)
  InvalidEarliestStart(String, Int32, Int32)
  DuplicateTaskId(String)
  UnknownDependency(String, String)
  DependencyCycle
}

///|
/// Construct a time window. Validation happens in `schedule`.
pub fn window(start : Int32, end : Int32) -> TimeWindow {
  { start, end, }
}

///|
/// Construct a fixed event. Validation happens in `schedule`.
pub fn fixed_event(id : String, start : Int32, end : Int32) -> FixedEvent {
  { id, window: { start, end, }, }
}

///|
/// Construct a task. Validation happens in `schedule`.
pub fn task(
  id : String,
  duration_minutes : Int32,
  deadline : Int32,
  dependencies : Array[String],
) -> Task {
  { id, duration_minutes, deadline, dependencies, earliest_start: None, }
}

///|
/// Construct a task that cannot begin before `earliest_start`.
/// Validation happens in `schedule`.
pub fn task_with_earliest_start(
  id : String,
  duration_minutes : Int32,
  deadline : Int32,
  dependencies : Array[String],
  earliest_start : Int32,
) -> Task {
  {
    id,
    duration_minutes,
    deadline,
    dependencies,
    earliest_start: Some(earliest_start),
  }
}

///|
/// Schedule tasks greedily by deadline once their dependencies are complete.
///
/// Ties are resolved by the input order. Each selected task is placed in the
/// earliest continuous feasible window. A returned `Ok` may still contain
/// unscheduled tasks; input validation failures are returned as `Err`.
pub fn schedule(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
) -> Result[Schedule, ValidationError] {
  match validate(availability, fixed_events, tasks) {
    Err(error) => Err(error)
    Ok(_) => Ok(build_schedule(availability, fixed_events, tasks))
  }
}

///|
fn validate(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
) -> Result[Unit, ValidationError] {
  let mut index = 0
  while index < availability.length() {
    let item = availability[index]
    if item.start >= item.end {
      return Err(InvalidWindow("availability", "", item.start, item.end))
    }
    index = index + 1
  }
  index = 0
  while index < fixed_events.length() {
    let item = fixed_events[index]
    if item.window.start >= item.window.end {
      return Err(
        InvalidWindow(
          "fixed_event",
          item.id,
          item.window.start,
          item.window.end,
        ),
      )
    }
    index = index + 1
  }
  index = 0
  while index < tasks.length() {
    let item = tasks[index]
    if item.duration_minutes <= 0 {
      return Err(InvalidTaskDuration(item.id, item.duration_minutes))
    }
    match item.earliest_start {
      Some(start) =>
        if start >= item.deadline {
          return Err(InvalidEarliestStart(item.id, start, item.deadline))
        }
      None => ()
    }
    let mut earlier = 0
    while earlier < index {
      if tasks[earlier].id == item.id {
        return Err(DuplicateTaskId(item.id))
      }
      earlier = earlier + 1
    }
    let mut dependency_index = 0
    while dependency_index < item.dependencies.length() {
      let dependency = item.dependencies[dependency_index]
      if task_index(tasks, dependency) == -1 {
        return Err(UnknownDependency(item.id, dependency))
      }
      dependency_index = dependency_index + 1
    }
    index = index + 1
  }
  if has_dependency_cycle(tasks) {
    Err(DependencyCycle)
  } else {
    Ok(())
  }
}

///|
fn build_schedule(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
) -> Schedule {
  let available_windows = normalize_availability(availability)
  let status = Array::make(tasks.length(), 0)
  let blocks : Array[ScheduledBlock] = []
  let unscheduled : Array[UnscheduledTask] = []
  let mut handled = 0
  while handled < tasks.length() {
    let next = next_ready_task(tasks, status)
    if next != -1 {
      let item = tasks[next]
      let earliest_start = later_limit(
        item.earliest_start,
        dependencies_end(item, blocks),
      )
      match
        find_slot(
          available_windows,
          fixed_events,
          blocks,
          earliest_start,
          item.duration_minutes,
          item.deadline,
        ) {
        Some(work_window) => {
          blocks.push({ task_id: item.id, window: work_window, })
          status[next] = 1
        }
        None => {
          unscheduled.push({ task_id: item.id, reason: NoContinuousSlot, })
          status[next] = 2
        }
      }
      handled = handled + 1
    } else {
      let blocked = first_pending_task(status)
      let item = tasks[blocked]
      let dependency = first_unfinished_dependency(item, tasks, status)
      unscheduled.push({
        task_id: item.id,
        reason: DependencyNotScheduled(dependency),
      })
      status[blocked] = 2
      handled = handled + 1
    }
  }
  { blocks, unscheduled, }
}

///|
fn normalize_availability(
  availability : Array[TimeWindow],
) -> Array[TimeWindow] {
  let sorted : Array[TimeWindow] = []
  let mut index = 0
  while index < availability.length() {
    sorted.push(availability[index])
    index = index + 1
  }
  sorted.sort_by_key(item => item.start)
  let merged : Array[TimeWindow] = []
  index = 0
  while index < sorted.length() {
    let current = sorted[index]
    if merged.length() > 0 && current.start <= merged[merged.length() - 1].end {
      let last = merged.length() - 1
      merged[last] = {
        start: merged[last].start,
        end: max_int(merged[last].end, current.end),
      }
    } else {
      merged.push(current)
    }
    index = index + 1
  }
  merged
}

///|
fn next_ready_task(tasks : Array[Task], status : Array[Int32]) -> Int32 {
  let mut index = 0
  let mut best = -1
  while index < tasks.length() {
    if status[index] == 0 &&
      dependencies_are_scheduled(tasks[index], tasks, status) {
      if best == -1 || tasks[index].deadline < tasks[best].deadline {
        best = index
      }
    }
    index = index + 1
  }
  best
}

///|
fn dependencies_are_scheduled(
  item : Task,
  tasks : Array[Task],
  status : Array[Int32],
) -> Bool {
  let mut index = 0
  while index < item.dependencies.length() {
    let dependency_index = task_index(tasks, item.dependencies[index])
    if status[dependency_index] != 1 {
      return false
    }
    index = index + 1
  }
  true
}

///|
fn first_unfinished_dependency(
  item : Task,
  tasks : Array[Task],
  status : Array[Int32],
) -> String {
  let mut index = 0
  while index < item.dependencies.length() {
    let dependency = item.dependencies[index]
    if status[task_index(tasks, dependency)] != 1 {
      return dependency
    }
    index = index + 1
  }
  ""
}

///|
fn dependencies_end(item : Task, blocks : Array[ScheduledBlock]) -> Int32? {
  let mut result : Int32? = None
  let mut index = 0
  while index < item.dependencies.length() {
    let block = block_for_task(blocks, item.dependencies[index])
    match result {
      Some(previous) =>
        if block.window.end > previous {
          result = Some(block.window.end)
        }
      None => result = Some(block.window.end)
    }
    index = index + 1
  }
  result
}

///|
fn later_limit(left : Int32?, right : Int32?) -> Int32? {
  match (left, right) {
    (Some(a), Some(b)) => Some(max_int(a, b))
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
}

///|
fn find_slot(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  blocks : Array[ScheduledBlock],
  earliest_start : Int32?,
  duration : Int32,
  deadline : Int32,
) -> TimeWindow? {
  let mut availability_index = 0
  while availability_index < availability.length() {
    let available = availability[availability_index]
    let latest_end = min_int(available.end, deadline)
    let mut candidate = match earliest_start {
      Some(start) => max_int(available.start, start)
      None => available.start
    }
    let mut candidate_end = candidate.to_int64() + duration.to_int64()
    while candidate_end <= latest_end.to_int64() {
      // The bound above makes narrowing safe, including at both Int32 extremes.
      let end = candidate_end.to_int()
      let blocker_end = conflicting_end(candidate, end, fixed_events, blocks)
      if blocker_end == candidate {
        return Some({ start: candidate, end, })
      }
      candidate = blocker_end
      candidate_end = candidate.to_int64() + duration.to_int64()
    }
    availability_index = availability_index + 1
  }
  None
}

///|
fn conflicting_end(
  start : Int32,
  end : Int32,
  fixed_events : Array[FixedEvent],
  blocks : Array[ScheduledBlock],
) -> Int32 {
  let mut result = start
  let mut index = 0
  while index < fixed_events.length() {
    let blocker = fixed_events[index].window
    if blocker.start < end && start < blocker.end && blocker.end > result {
      result = blocker.end
    }
    index = index + 1
  }
  index = 0
  while index < blocks.length() {
    let blocker = blocks[index].window
    if blocker.start < end && start < blocker.end && blocker.end > result {
      result = blocker.end
    }
    index = index + 1
  }
  result
}

///|
fn has_dependency_cycle(tasks : Array[Task]) -> Bool {
  let states = Array::make(tasks.length(), 0)
  let mut index = 0
  while index < tasks.length() {
    if states[index] == 0 && visit_for_cycle(index, tasks, states) {
      return true
    }
    index = index + 1
  }
  false
}

///|
fn visit_for_cycle(
  index : Int32,
  tasks : Array[Task],
  states : Array[Int32],
) -> Bool {
  if states[index] == 1 {
    return true
  }
  if states[index] == 2 {
    return false
  }
  states[index] = 1
  let mut dependency_index = 0
  while dependency_index < tasks[index].dependencies.length() {
    let dependency = task_index(
      tasks,
      tasks[index].dependencies[dependency_index],
    )
    if visit_for_cycle(dependency, tasks, states) {
      return true
    }
    dependency_index = dependency_index + 1
  }
  states[index] = 2
  false
}

///|
fn task_index(tasks : Array[Task], id : String) -> Int32 {
  let mut index = 0
  while index < tasks.length() {
    if tasks[index].id == id {
      return index
    }
    index = index + 1
  }
  -1
}

///|
fn block_for_task(
  blocks : Array[ScheduledBlock],
  task_id : String,
) -> ScheduledBlock {
  let mut index = 0
  while index < blocks.length() {
    if blocks[index].task_id == task_id {
      return blocks[index]
    }
    index = index + 1
  }
  { task_id, window: { start: 0, end: 0, }, }
}

///|
fn first_pending_task(status : Array[Int32]) -> Int32 {
  let mut index = 0
  while index < status.length() {
    if status[index] == 0 {
      return index
    }
    index = index + 1
  }
  -1
}

///|
fn min_int(left : Int32, right : Int32) -> Int32 {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn max_int(left : Int32, right : Int32) -> Int32 {
  if left > right {
    left
  } else {
    right
  }
}
