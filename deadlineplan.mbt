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
  minimum_block_minutes : Int32?
}

///|
/// A task already finished outside this scheduling run.
pub(all) struct CompletedTask {
  id : String
  completed_at : Int32
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
  SplitWorkIncomplete(Int32)
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
  InvalidMinimumBlock(String, Int32, Int32)
  DuplicateTaskId(String)
  UnknownDependency(String, String)
  DependencyCycle
  UnknownCompletedTaskId(String)
  DuplicateCompletedTaskId(String)
  UnknownConfirmedTaskId(String)
  CompletedAndConfirmedTaskId(String)
  InvalidConfirmedWindow(String, Int32, Int32)
  ConfirmedOutsideAvailability(String, Int32, Int32)
  ConfirmedBeforeEarliestStart(String, Int32, Int32)
  ConfirmedAfterDeadline(String, Int32, Int32)
  ConfirmedBlockTooShort(String, Int64, Int32)
  InvalidConfirmedBlockCount(String, Int32)
  ConfirmedDurationMismatch(String, Int64, Int32)
  ConfirmedOverlapsFixedEvent(String, String)
  ConfirmedBlocksOverlap(String, String)
  UnresolvedPriorDependency(String, String)
  PriorDependencyFinishesLate(String, String, Int32, Int32)
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
  {
    id,
    duration_minutes,
    deadline,
    dependencies,
    earliest_start: None,
    minimum_block_minutes: None,
  }
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
    minimum_block_minutes: None,
  }
}

///|
/// Construct a task whose work may be split into blocks of at least
/// `minimum_block_minutes`. Validation happens in `schedule`.
pub fn splittable_task(
  id : String,
  duration_minutes : Int32,
  deadline : Int32,
  dependencies : Array[String],
  minimum_block_minutes : Int32,
) -> Task {
  {
    id,
    duration_minutes,
    deadline,
    dependencies,
    earliest_start: None,
    minimum_block_minutes: Some(minimum_block_minutes),
  }
}

///|
/// Construct a splittable task that cannot start before `earliest_start`.
/// Validation happens in `schedule`.
pub fn splittable_task_with_earliest_start(
  id : String,
  duration_minutes : Int32,
  deadline : Int32,
  dependencies : Array[String],
  earliest_start : Int32,
  minimum_block_minutes : Int32,
) -> Task {
  {
    id,
    duration_minutes,
    deadline,
    dependencies,
    earliest_start: Some(earliest_start),
    minimum_block_minutes: Some(minimum_block_minutes),
  }
}

///|
/// Record the actual completion minute of a task in the task list.
/// Validation happens in `schedule_with_completed`.
pub fn completed_task(id : String, completed_at : Int32) -> CompletedTask {
  { id, completed_at, }
}

///|
/// Schedule tasks greedily by deadline once their dependencies are complete.
///
/// Ties are resolved by the input order. Each selected task is placed in the
/// earliest feasible time blocks. A returned `Ok` may still contain
/// unscheduled tasks; input validation failures are returned as `Err`.
pub fn schedule(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
) -> Result[Schedule, ValidationError] {
  schedule_with_completed(availability, fixed_events, tasks, [])
}

///|
/// Like `schedule`, but pre-completed tasks are not scheduled again. Their
/// actual completion minutes still constrain their dependents.
pub fn schedule_with_completed(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
  completed : Array[CompletedTask],
) -> Result[Schedule, ValidationError] {
  match validate(availability, fixed_events, tasks, completed) {
    Err(error) => Err(error)
    Ok(_) =>
      Ok(build_schedule(availability, fixed_events, tasks, completed, []))
  }
}

///|
/// Replan remaining work while retaining confirmed task blocks.
/// Completed tasks have actual completion minutes and reserve no work time.
pub fn schedule_with_confirmed_blocks(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
  completed : Array[CompletedTask],
  confirmed_blocks : Array[ScheduledBlock],
) -> Result[Schedule, ValidationError] {
  match validate(availability, fixed_events, tasks, completed) {
    Err(error) => Err(error)
    Ok(_) =>
      match
        validate_confirmed(
          availability, fixed_events, tasks, completed, confirmed_blocks,
        ) {
        Err(error) => Err(error)
        Ok(_) =>
          Ok(
            build_schedule(
              availability, fixed_events, tasks, completed, confirmed_blocks,
            ),
          )
      }
  }
}

///|
fn validate(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
  completed : Array[CompletedTask],
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
    match item.minimum_block_minutes {
      Some(minimum) =>
        if minimum <= 0 || minimum > item.duration_minutes {
          return Err(
            InvalidMinimumBlock(item.id, minimum, item.duration_minutes),
          )
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
    return Err(DependencyCycle)
  }
  index = 0
  while index < completed.length() {
    let record = completed[index]
    if task_index(tasks, record.id) == -1 {
      return Err(UnknownCompletedTaskId(record.id))
    }
    let mut earlier = 0
    while earlier < index {
      if completed[earlier].id == record.id {
        return Err(DuplicateCompletedTaskId(record.id))
      }
      earlier = earlier + 1
    }
    index = index + 1
  }
  Ok(())
}

///|
fn validate_confirmed(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
  completed : Array[CompletedTask],
  confirmed_blocks : Array[ScheduledBlock],
) -> Result[Unit, ValidationError] {
  let available = normalize_availability(availability)
  let mut index = 0
  while index < confirmed_blocks.length() {
    let block = confirmed_blocks[index]
    let task_position = task_index(tasks, block.task_id)
    if task_position == -1 {
      return Err(UnknownConfirmedTaskId(block.task_id))
    }
    let mut completed_index = 0
    while completed_index < completed.length() {
      if completed[completed_index].id == block.task_id {
        return Err(CompletedAndConfirmedTaskId(block.task_id))
      }
      completed_index = completed_index + 1
    }
    if block.window.start >= block.window.end {
      return Err(
        InvalidConfirmedWindow(
          block.task_id,
          block.window.start,
          block.window.end,
        ),
      )
    }
    let item = tasks[task_position]
    match item.earliest_start {
      Some(start) =>
        if block.window.start < start {
          return Err(
            ConfirmedBeforeEarliestStart(
              block.task_id,
              block.window.start,
              start,
            ),
          )
        }
      None => ()
    }
    if block.window.end > item.deadline {
      return Err(
        ConfirmedAfterDeadline(block.task_id, block.window.end, item.deadline),
      )
    }
    let length = block.window.end.to_int64() - block.window.start.to_int64()
    match item.minimum_block_minutes {
      Some(minimum) =>
        if length < minimum.to_int64() {
          return Err(ConfirmedBlockTooShort(block.task_id, length, minimum))
        }
      None => ()
    }
    let mut covered = false
    let mut available_index = 0
    while available_index < available.length() {
      if block.window.start >= available[available_index].start &&
        block.window.end <= available[available_index].end {
        covered = true
      }
      available_index = available_index + 1
    }
    if !covered {
      return Err(
        ConfirmedOutsideAvailability(
          block.task_id,
          block.window.start,
          block.window.end,
        ),
      )
    }
    let mut event_index = 0
    while event_index < fixed_events.length() {
      if windows_overlap(block.window, fixed_events[event_index].window) {
        return Err(
          ConfirmedOverlapsFixedEvent(
            block.task_id,
            fixed_events[event_index].id,
          ),
        )
      }
      event_index = event_index + 1
    }
    let mut earlier = 0
    while earlier < index {
      if windows_overlap(block.window, confirmed_blocks[earlier].window) {
        return Err(
          ConfirmedBlocksOverlap(
            block.task_id,
            confirmed_blocks[earlier].task_id,
          ),
        )
      }
      earlier = earlier + 1
    }
    index = index + 1
  }
  index = 0
  while index < tasks.length() {
    let item = tasks[index]
    let mut count = 0
    let mut total = 0L
    let mut first_start : Int32? = None
    let mut block_index = 0
    while block_index < confirmed_blocks.length() {
      let block = confirmed_blocks[block_index]
      if block.task_id == item.id {
        count = count + 1
        let length = block.window.end.to_int64() - block.window.start.to_int64()
        total = total + length
        first_start = match first_start {
          Some(start) => Some(min_int(start, block.window.start))
          None => Some(block.window.start)
        }
      }
      block_index = block_index + 1
    }
    if count > 0 {
      if item.minimum_block_minutes is None && count != 1 {
        return Err(InvalidConfirmedBlockCount(item.id, count))
      }
      if total > item.duration_minutes.to_int64() ||
        (
          item.minimum_block_minutes is None &&
          total != item.duration_minutes.to_int64()
        ) {
        return Err(
          ConfirmedDurationMismatch(item.id, total, item.duration_minutes),
        )
      }
      match first_start {
        Some(start) =>
          match
            validate_prior_dependencies(
              item, start, tasks, completed, confirmed_blocks,
            ) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        None => ()
      }
    }
    index = index + 1
  }
  index = 0
  while index < completed.length() {
    let record = completed[index]
    let item = tasks[task_index(tasks, record.id)]
    match
      validate_prior_dependencies(
        item,
        record.completed_at,
        tasks,
        completed,
        confirmed_blocks,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    index = index + 1
  }
  Ok(())
}

///|
fn windows_overlap(left : TimeWindow, right : TimeWindow) -> Bool {
  left.start < right.end && right.start < left.end
}

///|
fn validate_prior_dependencies(
  item : Task,
  actual_time : Int32,
  tasks : Array[Task],
  completed : Array[CompletedTask],
  confirmed_blocks : Array[ScheduledBlock],
) -> Result[Unit, ValidationError] {
  let mut dependency_index = 0
  while dependency_index < item.dependencies.length() {
    let dependency = item.dependencies[dependency_index]
    let mut is_completed = false
    let mut completed_index = 0
    while completed_index < completed.length() {
      if completed[completed_index].id == dependency {
        is_completed = true
      }
      completed_index = completed_index + 1
    }
    if !is_completed &&
      confirmed_minutes(dependency, confirmed_blocks) !=
      tasks[task_index(tasks, dependency)].duration_minutes.to_int64() {
      return Err(UnresolvedPriorDependency(item.id, dependency))
    }
    match recorded_finish(dependency, completed, confirmed_blocks) {
      None => return Err(UnresolvedPriorDependency(item.id, dependency))
      Some(finished_at) =>
        if finished_at > actual_time {
          return Err(
            PriorDependencyFinishesLate(
              item.id,
              dependency,
              finished_at,
              actual_time,
            ),
          )
        }
    }
    dependency_index = dependency_index + 1
  }
  Ok(())
}

///|
fn confirmed_minutes(
  task_id : String,
  confirmed_blocks : Array[ScheduledBlock],
) -> Int64 {
  let mut total = 0L
  let mut index = 0
  while index < confirmed_blocks.length() {
    let block = confirmed_blocks[index]
    if block.task_id == task_id {
      let length = block.window.end.to_int64() - block.window.start.to_int64()
      total = total + length
    }
    index = index + 1
  }
  total
}

///|
/// Return an actual completion minute or the last end among task blocks.
/// `blocks` may be only confirmed blocks or the full schedule built so far.
fn recorded_finish(
  task_id : String,
  completed : Array[CompletedTask],
  confirmed_blocks : Array[ScheduledBlock],
) -> Int32? {
  let mut result : Int32? = None
  let mut index = 0
  while index < completed.length() {
    if completed[index].id == task_id {
      result = later_limit(result, Some(completed[index].completed_at))
    }
    index = index + 1
  }
  index = 0
  while index < confirmed_blocks.length() {
    if confirmed_blocks[index].task_id == task_id {
      result = later_limit(result, Some(confirmed_blocks[index].window.end))
    }
    index = index + 1
  }
  result
}

///|
fn build_schedule(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  tasks : Array[Task],
  completed : Array[CompletedTask],
  confirmed_blocks : Array[ScheduledBlock],
) -> Schedule {
  let available_windows = normalize_availability(availability)
  let status = Array::make(tasks.length(), 0)
  let blocks : Array[ScheduledBlock] = []
  let unscheduled : Array[UnscheduledTask] = []
  let mut handled = 0
  let mut completed_index = 0
  while completed_index < completed.length() {
    status[task_index(tasks, completed[completed_index].id)] = 1
    handled = handled + 1
    completed_index = completed_index + 1
  }
  let mut confirmed_index = 0
  while confirmed_index < confirmed_blocks.length() {
    let block = confirmed_blocks[confirmed_index]
    blocks.push(block)
    confirmed_index = confirmed_index + 1
  }
  let mut task_position = 0
  while task_position < tasks.length() {
    if confirmed_minutes(tasks[task_position].id, confirmed_blocks) ==
      tasks[task_position].duration_minutes.to_int64() {
      status[task_position] = 1
      handled = handled + 1
    }
    task_position = task_position + 1
  }
  while handled < tasks.length() {
    let next = next_ready_task(tasks, status)
    if next != -1 {
      let item = tasks[next]
      let earliest_start = later_limit(
        item.earliest_start,
        dependencies_end(item, blocks, completed),
      )
      let confirmed_work = confirmed_minutes(item.id, confirmed_blocks)
      let remaining_work = (item.duration_minutes.to_int64() - confirmed_work).to_int()
      match
        plan_task(
          item,
          available_windows,
          fixed_events,
          blocks,
          earliest_start,
          remaining_work,
          confirmed_work > 0L,
        ) {
        Ok(work_windows) => {
          let mut block_index = 0
          while block_index < work_windows.length() {
            blocks.push({ task_id: item.id, window: work_windows[block_index], })
            block_index = block_index + 1
          }
          status[next] = 1
        }
        Err(reason) => {
          unscheduled.push({ task_id: item.id, reason, })
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
fn plan_task(
  item : Task,
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  blocks : Array[ScheduledBlock],
  earliest_start : Int32?,
  remaining_work : Int32,
  has_confirmed_work : Bool,
) -> Result[Array[TimeWindow], UnscheduledReason] {
  match item.minimum_block_minutes {
    None =>
      match
        find_slot(
          availability,
          fixed_events,
          blocks,
          earliest_start,
          remaining_work,
          item.deadline,
        ) {
        Some(work_window) => Ok([work_window])
        None => Err(NoContinuousSlot)
      }
    Some(minimum) =>
      find_split_blocks(
        availability,
        fixed_events,
        blocks,
        earliest_start,
        remaining_work,
        minimum,
        item.deadline,
        has_confirmed_work,
      )
  }
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
fn dependencies_end(
  item : Task,
  blocks : Array[ScheduledBlock],
  completed : Array[CompletedTask],
) -> Int32? {
  let mut result : Int32? = None
  let mut dependency_index = 0
  while dependency_index < item.dependencies.length() {
    result = later_limit(
      result,
      recorded_finish(item.dependencies[dependency_index], completed, blocks),
    )
    dependency_index = dependency_index + 1
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
fn find_split_blocks(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  blocks : Array[ScheduledBlock],
  earliest_start : Int32?,
  duration : Int32,
  minimum : Int32,
  deadline : Int32,
  allow_short_final : Bool,
) -> Result[Array[TimeWindow], UnscheduledReason] {
  let gaps = free_intervals(
    availability, fixed_events, blocks, earliest_start, deadline,
  )
  let proposed : Array[TimeWindow] = []
  let mut remaining = duration
  let mut index = 0
  while index < gaps.length() && remaining > 0 {
    let gap = gaps[index]
    match
      earliest_feasible_take(gaps, index, remaining, minimum, allow_short_final) {
      Some(take) => {
        // The selected amount fits this gap, so narrowing to Int32 is safe.
        let end = (gap.start.to_int64() + take.to_int64()).to_int()
        proposed.push({ start: gap.start, end, })
        remaining = remaining - take
      }
      None => ()
    }
    index = index + 1
  }
  if remaining == 0 {
    Ok(proposed)
  } else {
    // No tentative block is committed; the pre-existing confirmation remains.
    Err(SplitWorkIncomplete(duration))
  }
}

///|
/// Find the largest regular block for this gap that leaves a feasible suffix.
/// With confirmed progress, the suffix may end in one short final block.
fn earliest_feasible_take(
  gaps : Array[TimeWindow],
  index : Int32,
  remaining : Int32,
  minimum : Int32,
  allow_short_final : Bool,
) -> Int32? {
  let capacity = gaps[index].end.to_int64() - gaps[index].start.to_int64()
  let minimum_long = minimum.to_int64()
  let remaining_long = remaining.to_int64()
  if allow_short_final && remaining_long < minimum_long {
    if capacity >= remaining_long {
      return Some(remaining)
    }
    return None
  }
  if capacity < minimum_long {
    return None
  }
  let future_capacities : Array[Int64] = []
  let mut next = index + 1
  while next < gaps.length() {
    let future = gaps[next].end.to_int64() - gaps[next].start.to_int64()
    future_capacities.push(future)
    next = next + 1
  }
  future_capacities.sort_by_key(value => value)
  let mut suffix_capacity = 0L
  let mut suffix_count = 0
  let mut best = 0L
  let mut searching = true
  while searching &&
        suffix_count <= future_capacities.length() &&
        suffix_count.to_int64() * minimum_long <= remaining_long {
    let minimum_regular = suffix_count.to_int64() * minimum_long
    let lower = max_long(minimum_long, remaining_long - suffix_capacity)
    let upper = min_long(capacity, remaining_long - minimum_regular)
    if lower <= upper && upper > best {
      best = upper
    }
    if suffix_count < future_capacities.length() {
      let largest = future_capacities[future_capacities.length() -
        1 -
        suffix_count]
      if allow_short_final && minimum_long > 1L {
        let short_capacity = min_long(minimum_long - 1L, largest)
        let maximum_suffix = min_long(
          remaining_long,
          suffix_capacity + short_capacity,
        )
        let lower_with_short = max_long(
          minimum_long,
          remaining_long - maximum_suffix,
        )
        let upper_with_short = min_long(
          capacity,
          remaining_long - minimum_regular - 1L,
        )
        if lower_with_short <= upper_with_short && upper_with_short > best {
          best = upper_with_short
        }
      }
      if largest >= minimum_long {
        suffix_capacity = min_long(remaining_long, suffix_capacity + largest)
      } else {
        searching = false
      }
    }
    suffix_count = suffix_count + 1
  }
  if best >= minimum_long {
    Some(best.to_int())
  } else {
    None
  }
}

///|
fn free_intervals(
  availability : Array[TimeWindow],
  fixed_events : Array[FixedEvent],
  blocks : Array[ScheduledBlock],
  earliest_start : Int32?,
  deadline : Int32,
) -> Array[TimeWindow] {
  let occupied : Array[TimeWindow] = []
  let mut index = 0
  while index < fixed_events.length() {
    occupied.push(fixed_events[index].window)
    index = index + 1
  }
  index = 0
  while index < blocks.length() {
    occupied.push(blocks[index].window)
    index = index + 1
  }
  let merged_occupied = normalize_availability(occupied)
  let gaps : Array[TimeWindow] = []
  let mut available_index = 0
  while available_index < availability.length() {
    let available = availability[available_index]
    let mut cursor = match earliest_start {
      Some(start) => max_int(available.start, start)
      None => available.start
    }
    let limit = min_int(available.end, deadline)
    let mut occupied_index = 0
    while occupied_index < merged_occupied.length() && cursor < limit {
      let blocker = merged_occupied[occupied_index]
      if blocker.start < limit && blocker.end > cursor {
        if blocker.start > cursor {
          gaps.push({ start: cursor, end: blocker.start, })
        }
        cursor = max_int(cursor, blocker.end)
      }
      occupied_index = occupied_index + 1
    }
    if cursor < limit {
      gaps.push({ start: cursor, end: limit, })
    }
    available_index = available_index + 1
  }
  gaps
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
fn min_long(left : Int64, right : Int64) -> Int64 {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn max_long(left : Int64, right : Int64) -> Int64 {
  if left > right {
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
