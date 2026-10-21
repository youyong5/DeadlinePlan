///|
/// Version 1 plan input. Times are signed Int32 UTC minutes since 1970-01-01T00:00:00Z.
pub(all) struct PlanDocument {
  schema_version : Int32
  availability : Array[TimeWindow]
  fixed_events : Array[FixedEvent]
  tasks : Array[Task]
  completed : Array[CompletedTask]
  confirmed_blocks : Array[ScheduledBlock]
}

///|
/// JSON syntax, shape, version, and scheduler validation are separate failures.
/// Field paths use JSON Pointer notation; the root is the empty string.
pub(all) suberror PlanJsonError {
  JsonSyntax(String)
  MissingField(String)
  WrongType(String, String)
  UnexpectedField(String)
  UnsupportedSchemaVersion(Int32)
  InvalidPlanInput(String, ValidationError)
}

///|
fn json_object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PlanJsonError {
  match value {
    Object(fields) => fields
    _ => raise WrongType(path, "object")
  }
}

///|
fn json_array(value : Json, path : String) -> Array[Json] raise PlanJsonError {
  match value {
    Array(items) => items
    _ => raise WrongType(path, "array")
  }
}

///|
fn json_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise PlanJsonError {
  match fields.get(key) {
    Some(value) => value
    None => raise MissingField("\{path}/\{key}")
  }
}

///|
fn reject_unknown_fields(
  fields : Map[String, Json],
  path : String,
  allowed : Array[String],
) -> Unit raise PlanJsonError {
  for key, _ in fields {
    let mut recognized = false
    for name in allowed {
      if key == name {
        recognized = true
      }
    }
    if !recognized {
      raise UnexpectedField("\{path}/\{pointer_token(key)}")
    }
  }
}

///|
fn pointer_token(key : String) -> String {
  let output = StringBuilder()
  for character in key.iter() {
    match character {
      '~' => output.write_string("~0")
      '/' => output.write_string("~1")
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn json_int(value : Json, path : String) -> Int32 raise PlanJsonError {
  match value {
    Number(number, ..) => {
      if number < -2147483648.0 || number > 2147483647.0 {
        raise WrongType(path, "signed 32-bit integer")
      }
      let minute = number.to_int()
      if minute.to_double() != number {
        raise WrongType(path, "signed 32-bit integer")
      }
      minute
    }
    _ => raise WrongType(path, "signed 32-bit integer")
  }
}

///|
fn json_string(value : Json, path : String) -> String raise PlanJsonError {
  match value {
    String(text) => text
    _ => raise WrongType(path, "string")
  }
}

///|
fn json_optional_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int32? raise PlanJsonError {
  match fields.get(key) {
    None | Some(Null) => None
    Some(value) => Some(json_int(value, "\{path}/\{key}"))
  }
}

///|
fn decode_window(value : Json, path : String) -> TimeWindow raise PlanJsonError {
  let fields = json_object(value, path)
  reject_unknown_fields(fields, path, ["start", "end"])
  {
    start: json_int(json_field(fields, "start", path), "\{path}/start"),
    end: json_int(json_field(fields, "end", path), "\{path}/end"),
  }
}

///|
fn decode_plan(value : Json) -> PlanDocument raise PlanJsonError {
  let root = json_object(value, "")
  let version = json_int(
    json_field(root, "schema_version", ""),
    "/schema_version",
  )
  if version != 1 {
    raise UnsupportedSchemaVersion(version)
  }
  reject_unknown_fields(root, "", [
    "schema_version", "availability", "fixed_events", "tasks", "completed", "confirmed_blocks",
  ])
  let availability : Array[TimeWindow] = []
  let windows = json_array(
    json_field(root, "availability", ""),
    "/availability",
  )
  for index, item in windows {
    availability.push(decode_window(item, "/availability/\{index}"))
  }
  let fixed_events : Array[FixedEvent] = []
  let events = json_array(json_field(root, "fixed_events", ""), "/fixed_events")
  for index, item in events {
    let path = "/fixed_events/\{index}"
    let fields = json_object(item, path)
    reject_unknown_fields(fields, path, ["id", "start", "end"])
    fixed_events.push({
      id: json_string(json_field(fields, "id", path), "\{path}/id"),
      window: {
        start: json_int(json_field(fields, "start", path), "\{path}/start"),
        end: json_int(json_field(fields, "end", path), "\{path}/end"),
      },
    })
  }
  let tasks : Array[Task] = []
  let task_items = json_array(json_field(root, "tasks", ""), "/tasks")
  for index, item in task_items {
    let path = "/tasks/\{index}"
    let fields = json_object(item, path)
    reject_unknown_fields(fields, path, [
      "id", "duration_minutes", "deadline", "dependencies", "earliest_start", "minimum_block_minutes",
    ])
    let dependencies : Array[String] = []
    let dependency_items = json_array(
      json_field(fields, "dependencies", path),
      "\{path}/dependencies",
    )
    for dep_index, dependency in dependency_items {
      dependencies.push(
        json_string(dependency, "\{path}/dependencies/\{dep_index}"),
      )
    }
    tasks.push({
      id: json_string(json_field(fields, "id", path), "\{path}/id"),
      duration_minutes: json_int(
        json_field(fields, "duration_minutes", path),
        "\{path}/duration_minutes",
      ),
      deadline: json_int(
        json_field(fields, "deadline", path),
        "\{path}/deadline",
      ),
      dependencies,
      earliest_start: json_optional_int(fields, "earliest_start", path),
      minimum_block_minutes: json_optional_int(
        fields, "minimum_block_minutes", path,
      ),
    })
  }
  let completed : Array[CompletedTask] = []
  let completions = json_array(json_field(root, "completed", ""), "/completed")
  for index, item in completions {
    let path = "/completed/\{index}"
    let fields = json_object(item, path)
    reject_unknown_fields(fields, path, ["id", "completed_at"])
    completed.push({
      id: json_string(json_field(fields, "id", path), "\{path}/id"),
      completed_at: json_int(
        json_field(fields, "completed_at", path),
        "\{path}/completed_at",
      ),
    })
  }
  let confirmed_blocks : Array[ScheduledBlock] = []
  let blocks = json_array(
    json_field(root, "confirmed_blocks", ""),
    "/confirmed_blocks",
  )
  for index, item in blocks {
    let path = "/confirmed_blocks/\{index}"
    let fields = json_object(item, path)
    reject_unknown_fields(fields, path, ["task_id", "start", "end"])
    confirmed_blocks.push({
      task_id: json_string(
        json_field(fields, "task_id", path),
        "\{path}/task_id",
      ),
      window: {
        start: json_int(json_field(fields, "start", path), "\{path}/start"),
        end: json_int(json_field(fields, "end", path), "\{path}/end"),
      },
    })
  }
  {
    schema_version: version,
    availability,
    fixed_events,
    tasks,
    completed,
    confirmed_blocks,
  }
}

///|
fn task_json_path(document : PlanDocument, id : String) -> String {
  for index, item in document.tasks {
    if item.id == id {
      return "/tasks/\{index}"
    }
  }
  "/tasks"
}

///|
fn duplicate_task_json_path(document : PlanDocument, id : String) -> String {
  let mut seen = false
  for index, item in document.tasks {
    if item.id == id {
      if seen {
        return "/tasks/\{index}/id"
      }
      seen = true
    }
  }
  task_json_path(document, id) + "/id"
}

///|
fn completed_json_path(document : PlanDocument, id : String) -> String {
  for index, item in document.completed {
    if item.id == id {
      return "/completed/\{index}"
    }
  }
  "/completed"
}

///|
fn duplicate_completed_json_path(
  document : PlanDocument,
  id : String,
) -> String {
  let mut seen = false
  for index, item in document.completed {
    if item.id == id {
      if seen {
        return "/completed/\{index}/id"
      }
      seen = true
    }
  }
  completed_json_path(document, id) + "/id"
}

///|
fn confirmed_json_path(document : PlanDocument, id : String) -> String {
  for index, item in document.confirmed_blocks {
    if item.task_id == id {
      return "/confirmed_blocks/\{index}"
    }
  }
  "/confirmed_blocks"
}

///|
fn validation_json_path(
  document : PlanDocument,
  error : ValidationError,
) -> String {
  match error {
    InvalidWindow("availability", _, start, end) => {
      for index, item in document.availability {
        if item.start == start && item.end == end {
          return "/availability/\{index}"
        }
      }
      "/availability"
    }
    InvalidWindow(_, id, start, end) => {
      for index, item in document.fixed_events {
        if item.id == id && item.window.start == start && item.window.end == end {
          return "/fixed_events/\{index}"
        }
      }
      "/fixed_events"
    }
    InvalidTaskDuration(id, _) =>
      task_json_path(document, id) + "/duration_minutes"
    InvalidEarliestStart(id, _, _) =>
      task_json_path(document, id) + "/earliest_start"
    InvalidMinimumBlock(id, _, _) =>
      task_json_path(document, id) + "/minimum_block_minutes"
    DuplicateTaskId(id) => duplicate_task_json_path(document, id)
    UnknownDependency(id, dependency) => {
      for index, item in document.tasks {
        if item.id == id {
          for dep_index, dep in item.dependencies {
            if dep == dependency {
              return "/tasks/\{index}/dependencies/\{dep_index}"
            }
          }
        }
      }
      task_json_path(document, id) + "/dependencies"
    }
    DependencyCycle => "/tasks"
    UnknownCompletedTaskId(id) => completed_json_path(document, id) + "/id"
    DuplicateCompletedTaskId(id) => duplicate_completed_json_path(document, id)
    UnknownConfirmedTaskId(id)
    | CompletedAndConfirmedTaskId(id)
    | InvalidConfirmedWindow(id, _, _)
    | ConfirmedOutsideAvailability(id, _, _)
    | ConfirmedBeforeEarliestStart(id, _, _)
    | ConfirmedAfterDeadline(id, _, _)
    | ConfirmedBlockTooShort(id, _, _)
    | InvalidConfirmedBlockCount(id, _)
    | ConfirmedDurationMismatch(id, _, _)
    | ConfirmedOverlapsFixedEvent(id, _)
    | ConfirmedBlocksOverlap(id, _) => confirmed_json_path(document, id)
    UnresolvedPriorDependency(id, _)
    | PriorDependencyFinishesLate(id, _, _, _) =>
      task_json_path(document, id) + "/dependencies"
  }
}

///|
fn validate_plan_document(document : PlanDocument) -> Unit raise PlanJsonError {
  if document.schema_version != 1 {
    raise UnsupportedSchemaVersion(document.schema_version)
  }
  match
    schedule_with_confirmed_blocks(
      document.availability,
      document.fixed_events,
      document.tasks,
      document.completed,
      document.confirmed_blocks,
    ) {
    Ok(_) => ()
    Err(error) =>
      raise InvalidPlanInput(validation_json_path(document, error), error)
  }
}

///|
/// Parse version 1 JSON and validate it with the existing replanning entry.
/// The Result shape is a stable public API; callers inspect parse failures as data.
#warnings("-result_error_return")
pub fn parse_plan_json(source : String) -> Result[PlanDocument, PlanJsonError] {
  let value = @json.parse(source) catch {
    error => return Err(JsonSyntax(error.to_string()))
  }
  let document = decode_plan(value) catch { error => return Err(error) }
  validate_plan_document(document) catch {
    error => return Err(error)
  }
  Ok(document)
}

///|
/// Emit a canonical version 1 JSON document after scheduler validation.
/// The Result shape is kept for compatibility with existing callers.
#warnings("-result_error_return")
pub fn serialize_plan_json(
  document : PlanDocument,
) -> Result[String, PlanJsonError] {
  validate_plan_document(document) catch {
    error => return Err(error)
  }
  let availability : Array[Json] = []
  for item in document.availability {
    availability.push({ "start": item.start, "end": item.end })
  }
  let fixed_events : Array[Json] = []
  for item in document.fixed_events {
    fixed_events.push({
      "id": item.id,
      "start": item.window.start,
      "end": item.window.end,
    })
  }
  let tasks : Array[Json] = []
  for item in document.tasks {
    let dependencies : Array[Json] = []
    for dependency in item.dependencies {
      dependencies.push(@json.to_json(dependency))
    }
    let earliest_start : Json = match item.earliest_start {
      Some(minute) => @json.to_json(minute)
      None => null
    }
    let minimum_block_minutes : Json = match item.minimum_block_minutes {
      Some(minutes) => @json.to_json(minutes)
      None => null
    }
    tasks.push({
      "id": item.id,
      "duration_minutes": item.duration_minutes,
      "deadline": item.deadline,
      "dependencies": @json.to_json(dependencies),
      "earliest_start": earliest_start,
      "minimum_block_minutes": minimum_block_minutes,
    })
  }
  let completed : Array[Json] = []
  for item in document.completed {
    completed.push({ "id": item.id, "completed_at": item.completed_at })
  }
  let confirmed_blocks : Array[Json] = []
  for item in document.confirmed_blocks {
    confirmed_blocks.push({
      "task_id": item.task_id,
      "start": item.window.start,
      "end": item.window.end,
    })
  }
  let json : Json = {
    "schema_version": 1,
    "availability": @json.to_json(availability),
    "fixed_events": @json.to_json(fixed_events),
    "tasks": @json.to_json(tasks),
    "completed": @json.to_json(completed),
    "confirmed_blocks": @json.to_json(confirmed_blocks),
  }
  Ok(json.stringify())
}
