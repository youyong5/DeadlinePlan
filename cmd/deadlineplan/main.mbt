///|
extern "js" fn read_text_file(path : String) -> String? =
  #| (path) => {
  #|   try { return require("node:fs").readFileSync(path, "utf8"); }
  #|   catch (_) { return undefined; }
  #| }

///|
extern "js" fn write_error(message : String) -> Unit =
  #| (message) => { process.stderr.write(message + "\n"); }

///|
extern "js" fn set_exit_code(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
/// Node's Date handles normal UTC dates. Expanded or negative years are kept
/// as raw minutes, rather than emitting a misleading human date.
extern "js" fn utc_date(minute : Int32) -> String? =
  #| (minute) => {
  #|   const milliseconds = minute * 60000;
  #|   const date = new Date(milliseconds);
  #|   const year = date.getUTCFullYear();
  #|   if (!Number.isSafeInteger(milliseconds) || !Number.isFinite(date.getTime()) || year < 0 || year > 9999) return undefined;
  #|   return date.toISOString().slice(0, 16) + "Z";
  #| }

///|
fn time_text(minute : Int32) -> String {
  match utc_date(minute) {
    Some(date) => date
    None => "minute \{minute}"
  }
}

///|
fn is_confirmed(
  block : @plan.ScheduledBlock,
  confirmed : Array[@plan.ScheduledBlock],
) -> Bool {
  for item in confirmed {
    if item.task_id == block.task_id &&
      item.window.start == block.window.start &&
      item.window.end == block.window.end {
      return true
    }
  }
  false
}

///|
fn chronological_blocks(
  schedule : @plan.Schedule,
) -> Array[@plan.ScheduledBlock] {
  let sorted : Array[@plan.ScheduledBlock] = []
  for block in schedule.blocks {
    sorted.push(block)
  }
  sorted.sort_by_key(block => block.window.start)
  sorted
}

///|
fn reason_text(reason : @plan.UnscheduledReason) -> String {
  match reason {
    NoContinuousSlot => "no continuous slot in the currently free time"
    SplitWorkIncomplete(minutes) =>
      "cannot allocate all \{minutes} unconfirmed work minutes in the currently free time"
    DependencyNotScheduled(id) => "dependency not scheduled: \{id}"
  }
}

///|
fn reason_json(reason : @plan.UnscheduledReason) -> Json {
  match reason {
    NoContinuousSlot => { "code": "no_continuous_slot" }
    SplitWorkIncomplete(minutes) =>
      { "code": "split_work_incomplete", "remaining_minutes": minutes }
    DependencyNotScheduled(id) =>
      { "code": "dependency_not_scheduled", "dependency_id": id }
  }
}

///|
fn render_text(
  schedule : @plan.Schedule,
  confirmed : Array[@plan.ScheduledBlock],
) -> Unit {
  let blocks = chronological_blocks(schedule)
  println("Scheduled blocks (\{blocks.length()}):")
  for block in blocks {
    let status = if is_confirmed(block, confirmed) {
      "confirmed"
    } else {
      "planned"
    }
    println(
      "  \{status} \{block.task_id}: [\{time_text(block.window.start)}, \{time_text(block.window.end)})",
    )
  }
  println("Unscheduled tasks (\{schedule.unscheduled.length()}):")
  for item in schedule.unscheduled {
    println("  \{item.task_id}: \{reason_text(item.reason)}")
  }
}

///|
fn render_json(
  schedule : @plan.Schedule,
  confirmed : Array[@plan.ScheduledBlock],
) -> String {
  let blocks : Array[Json] = []
  for block in chronological_blocks(schedule) {
    blocks.push({
      "task_id": block.task_id,
      "start": block.window.start,
      "end": block.window.end,
      "confirmed": is_confirmed(block, confirmed),
    })
  }
  let unscheduled : Array[Json] = []
  for item in schedule.unscheduled {
    unscheduled.push({
      "task_id": item.task_id,
      "reason": reason_json(item.reason),
    })
  }
  let output : Json = {
    "result_version": 1,
    "time_unit": "utc_minutes_since_unix_epoch",
    "blocks": @json.to_json(blocks),
    "unscheduled": @json.to_json(unscheduled),
  }
  output.stringify()
}

///|
fn validation_text(error : @plan.ValidationError) -> String {
  match error {
    InvalidWindow(kind, id, start, end) =>
      "invalid \{kind} interval \{id}: [\{start}, \{end})"
    InvalidTaskDuration(id, minutes) => "invalid duration for \{id}: \{minutes}"
    InvalidEarliestStart(id, start, deadline) =>
      "earliest start \{start} is not before deadline \{deadline} for \{id}"
    InvalidMinimumBlock(id, minimum, duration) =>
      "invalid minimum block \{minimum} for \{id} (duration \{duration})"
    DuplicateTaskId(id) => "duplicate task ID: \{id}"
    UnknownDependency(id, dependency) =>
      "unknown dependency \{dependency} for \{id}"
    DependencyCycle => "dependency cycle"
    UnknownCompletedTaskId(id) => "unknown completed task ID: \{id}"
    DuplicateCompletedTaskId(id) => "duplicate completion record: \{id}"
    UnknownConfirmedTaskId(id) => "unknown confirmed task ID: \{id}"
    CompletedAndConfirmedTaskId(id) =>
      "task is both completed and confirmed: \{id}"
    InvalidConfirmedWindow(id, start, end) =>
      "invalid confirmed interval for \{id}: [\{start}, \{end})"
    ConfirmedOutsideAvailability(id, start, end) =>
      "confirmed block for \{id} is outside availability: [\{start}, \{end})"
    ConfirmedBeforeEarliestStart(id, start, earliest) =>
      "confirmed block for \{id} starts at \{start} before \{earliest}"
    ConfirmedAfterDeadline(id, end, deadline) =>
      "confirmed block for \{id} ends at \{end} after \{deadline}"
    ConfirmedBlockTooShort(id, length, minimum) =>
      "confirmed block for \{id} is \{length} minutes, below minimum \{minimum}"
    InvalidConfirmedBlockCount(id, count) =>
      "invalid confirmed block count for \{id}: \{count}"
    ConfirmedDurationMismatch(id, total, duration) =>
      "confirmed duration for \{id} is \{total}, task duration is \{duration}"
    ConfirmedOverlapsFixedEvent(id, event) =>
      "confirmed block for \{id} overlaps fixed event \{event}"
    ConfirmedBlocksOverlap(id, other) =>
      "confirmed block for \{id} overlaps one for \{other}"
    UnresolvedPriorDependency(id, dependency) =>
      "prior dependency \{dependency} for \{id} is not complete"
    PriorDependencyFinishesLate(id, dependency, finished, actual) =>
      "prior dependency \{dependency} for \{id} ends at \{finished}, after \{actual}"
  }
}

///|
fn plan_error_text(error : @plan.PlanJsonError) -> String {
  match error {
    JsonSyntax(message) => "JSON syntax error: \{message}"
    MissingField(path) => "missing field at \{path}"
    WrongType(path, expected) => "wrong type at \{path}: expected \{expected}"
    UnexpectedField(path) => "unexpected field at \{path}"
    UnsupportedSchemaVersion(version) =>
      "unsupported schema_version: \{version} (expected 1)"
    InvalidPlanInput(path, validation) =>
      "invalid plan at \{path}: \{validation_text(validation)}"
  }
}

///|
fn usage() -> String {
  "Usage: moon run --target js cmd/deadlineplan -- [--json] <plan.json>\n       moon run --target js cmd/deadlineplan -- --help"
}

///|
fn main {
  let args = @env.args()
  // On the JS target @env.args() includes both Node and the script path.
  if args.length() == 3 && args[2] == "--help" {
    println(usage())
    return
  }
  let mut json_output = false
  let path = if args.length() == 3 && !args[2].has_prefix("-") {
    args[2]
  } else if args.length() == 4 &&
    args[2] == "--json" &&
    !args[3].has_prefix("-") {
    json_output = true
    args[3]
  } else {
    write_error(usage())
    set_exit_code(2)
    return
  }
  let source = match read_text_file(path) {
    Some(content) => content
    None => {
      write_error("cannot read plan file: \{path}")
      set_exit_code(1)
      return
    }
  }
  let document = match @plan.parse_plan_json(source) {
    Ok(document) => document
    Err(error) => {
      write_error(plan_error_text(error))
      set_exit_code(1)
      return
    }
  }
  match
    @plan.schedule_with_confirmed_blocks(
      document.availability,
      document.fixed_events,
      document.tasks,
      document.completed,
      document.confirmed_blocks,
    ) {
    Ok(schedule) =>
      if json_output {
        println(render_json(schedule, document.confirmed_blocks))
      } else {
        render_text(schedule, document.confirmed_blocks)
      }
    Err(error) => {
      // This should not occur: parse_plan_json already validates via this API.
      write_error("invalid plan: \{validation_text(error)}")
      set_exit_code(1)
    }
  }
}
