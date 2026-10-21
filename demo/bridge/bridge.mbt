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
fn reason_json(reason : @plan.UnscheduledReason) -> Json {
  match reason {
    NoContinuousSlot => { "code": "NoContinuousSlot" }
    SplitWorkIncomplete(minutes) =>
      { "code": "SplitWorkIncomplete", "remaining_minutes": minutes }
    DependencyNotScheduled(id) =>
      { "code": "DependencyNotScheduled", "dependency_id": id }
  }
}

///|
fn validation_message(error : @plan.ValidationError) -> String {
  match error {
    InvalidWindow(kind, id, start, end) =>
      "InvalidWindow: \{kind} \{id} [\{start}, \{end})"
    InvalidTaskDuration(id, minutes) =>
      "InvalidTaskDuration: \{id}, \{minutes} minutes"
    InvalidEarliestStart(id, start, deadline) =>
      "InvalidEarliestStart: \{id}, \{start} >= \{deadline}"
    InvalidMinimumBlock(id, minimum, duration) =>
      "InvalidMinimumBlock: \{id}, \{minimum} of \{duration} minutes"
    DuplicateTaskId(id) => "DuplicateTaskId: \{id}"
    UnknownDependency(id, dependency) =>
      "UnknownDependency: \{id} needs \{dependency}"
    DependencyCycle => "DependencyCycle"
    UnknownCompletedTaskId(id) => "UnknownCompletedTaskId: \{id}"
    DuplicateCompletedTaskId(id) => "DuplicateCompletedTaskId: \{id}"
    UnknownConfirmedTaskId(id) => "UnknownConfirmedTaskId: \{id}"
    CompletedAndConfirmedTaskId(id) => "CompletedAndConfirmedTaskId: \{id}"
    InvalidConfirmedWindow(id, start, end) =>
      "InvalidConfirmedWindow: \{id} [\{start}, \{end})"
    ConfirmedOutsideAvailability(id, start, end) =>
      "ConfirmedOutsideAvailability: \{id} [\{start}, \{end})"
    ConfirmedBeforeEarliestStart(id, start, earliest) =>
      "ConfirmedBeforeEarliestStart: \{id}, \{start} < \{earliest}"
    ConfirmedAfterDeadline(id, end, deadline) =>
      "ConfirmedAfterDeadline: \{id}, \{end} > \{deadline}"
    ConfirmedBlockTooShort(id, length, minimum) =>
      "ConfirmedBlockTooShort: \{id}, \{length} < \{minimum} minutes"
    InvalidConfirmedBlockCount(id, count) =>
      "InvalidConfirmedBlockCount: \{id}, \{count} blocks"
    ConfirmedDurationMismatch(id, total, duration) =>
      "ConfirmedDurationMismatch: \{id}, \{total} of \{duration} minutes"
    ConfirmedOverlapsFixedEvent(id, event) =>
      "ConfirmedOverlapsFixedEvent: \{id} and \{event}"
    ConfirmedBlocksOverlap(id, other) =>
      "ConfirmedBlocksOverlap: \{id} and \{other}"
    UnresolvedPriorDependency(id, dependency) =>
      "UnresolvedPriorDependency: \{id} needs \{dependency}"
    PriorDependencyFinishesLate(id, dependency, finished, actual) =>
      "PriorDependencyFinishesLate: \{dependency} ends at \{finished}, after \{id} at \{actual}"
  }
}

///|
fn error_json(error : @plan.PlanJsonError) -> Json {
  match error {
    JsonSyntax(message) =>
      { "kind": "JsonSyntax", "path": "", "message": message }
    MissingField(path) =>
      {
        "kind": "MissingField",
        "path": path,
        "message": "Required field is missing",
      }
    WrongType(path, expected) =>
      { "kind": "WrongType", "path": path, "message": "Expected \{expected}" }
    UnexpectedField(path) =>
      {
        "kind": "UnexpectedField",
        "path": path,
        "message": "Unknown field in schema version 1",
      }
    UnsupportedSchemaVersion(version) =>
      {
        "kind": "UnsupportedSchemaVersion",
        "path": "/schema_version",
        "message": "Unsupported schema version \{version}",
      }
    InvalidPlanInput(path, validation) =>
      {
        "kind": "InvalidPlanInput",
        "path": path,
        "message": validation_message(validation),
      }
  }
}

///|
/// Browser-facing adapter: parsing and scheduling stay in the public library.
#export_name("run_plan_json")
pub fn run_plan_json(source : String) -> String {
  let document = match @plan.parse_plan_json(source) {
    Ok(document) => document
    Err(error) => {
      let response : Json = { "ok": false, "error": error_json(error) }
      return response.stringify()
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
    Err(error) => {
      let response : Json = {
        "ok": false,
        "error": {
          "kind": "InvalidPlanInput",
          "path": "",
          "message": validation_message(error),
        },
      }
      response.stringify()
    }
    Ok(schedule) => {
      let blocks : Array[Json] = []
      for block in schedule.blocks {
        blocks.push({
          "task_id": block.task_id,
          "start": block.window.start,
          "end": block.window.end,
          "confirmed": is_confirmed(block, document.confirmed_blocks),
        })
      }
      let unscheduled : Array[Json] = []
      for item in schedule.unscheduled {
        unscheduled.push({
          "task_id": item.task_id,
          "reason": reason_json(item.reason),
        })
      }
      let response : Json = {
        "ok": true,
        "blocks": @json.to_json(blocks),
        "unscheduled": @json.to_json(unscheduled),
      }
      response.stringify()
    }
  }
}
