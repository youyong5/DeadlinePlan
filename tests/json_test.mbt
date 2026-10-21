///|
fn json_plan(tasks : String) -> String {
  "{\"schema_version\":1,\"availability\":[{\"start\":-2147483648,\"end\":2147483647}],\"fixed_events\":[],\"tasks\":" +
  tasks +
  ",\"completed\":[],\"confirmed_blocks\":[]}"
}

///|
test "JSON roundtrip keeps Int32 extremes, optional limits and task tie order" {
  let source = json_plan(
    (
      #|[{"id":"first","duration_minutes":1,"deadline":2147483647,"dependencies":[],"earliest_start":-2147483648,"minimum_block_minutes":null},{"id":"second","duration_minutes":1,"deadline":2147483647,"dependencies":[],"minimum_block_minutes":1}]
    ),
  )
  match @deadlineplan.parse_plan_json(source) {
    Ok(first) => {
      assert_eq(first.tasks[0].id, "first")
      assert_eq(first.tasks[0].earliest_start, Some(-2147483648))
      assert_eq(first.tasks[1].minimum_block_minutes, Some(1))
      match @deadlineplan.serialize_plan_json(first) {
        Ok(encoded) =>
          match @deadlineplan.parse_plan_json(encoded) {
            Ok(second) => {
              assert_eq(second.availability[0].start, -2147483648)
              assert_eq(second.availability[0].end, 2147483647)
              assert_eq(second.tasks[0].id, "first")
              assert_eq(second.tasks[1].id, "second")
              match
                @deadlineplan.schedule_with_confirmed_blocks(
                  second.availability,
                  second.fixed_events,
                  second.tasks,
                  second.completed,
                  second.confirmed_blocks,
                ) {
                Ok(plan) => {
                  assert_eq(plan.blocks[0].task_id, "first")
                  assert_eq(plan.blocks[0].window.start, -2147483648)
                  assert_eq(plan.blocks[1].task_id, "second")
                  assert_eq(plan.blocks[1].window.start, -2147483647)
                }
                Err(_) => assert_true(false)
              }
            }
            Err(_) => assert_true(false)
          }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "JSON errors distinguish syntax, absent fields, types and versions" {
  assert_true(@deadlineplan.parse_plan_json("{") is Err(JsonSyntax(_)))
  assert_true(
    @deadlineplan.parse_plan_json("{}") is Err(MissingField("/schema_version")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":2,"availability":[],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(UnsupportedSchemaVersion(2)),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":0,"availability":[],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(UnsupportedSchemaVersion(0)),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[]}
      ),
    )
    is Err(MissingField("/completed")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":"wrong","fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/availability", "array")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1.5,"availability":[],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/schema_version", "signed 32-bit integer")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[],"location":"lab"}
      ),
    )
    is Err(UnexpectedField("/location")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[{"id":"work","duration_minutes":1,"deadline":10,"dependencies":[],"room/a~b":"A1"}],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(UnexpectedField("/tasks/0/room~1a~0b")),
  )
}

///|
test "JSON numeric fields reject fractional, overflow and wrong types at paths" {
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[{"start":0.5,"end":10}],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/availability/0/start", "signed 32-bit integer")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[{"start":-2147483649,"end":10}],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/availability/0/start", "signed 32-bit integer")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[{"id":"work","duration_minutes":1,"deadline":"tomorrow","dependencies":[]}],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/tasks/0/deadline", "signed 32-bit integer")),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[{"id":"work","duration_minutes":1,"deadline":10,"dependencies":[7]}],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(WrongType("/tasks/0/dependencies/0", "string")),
  )
}

///|
test "JSON semantic errors come from scheduler with useful field paths" {
  assert_true(
    @deadlineplan.parse_plan_json(
      json_plan(
        (
          #|[{"id":"work","duration_minutes":1,"deadline":10,"dependencies":["missing"]}]
        ),
      ),
    )
    is Err(
      InvalidPlanInput(
        "/tasks/0/dependencies/0",
        UnknownDependency("work", "missing")
      )
    ),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      json_plan(
        (
          #|[{"id":"work","duration_minutes":0,"deadline":10,"dependencies":[]}]
        ),
      ),
    )
    is Err(
      InvalidPlanInput(
        "/tasks/0/duration_minutes",
        InvalidTaskDuration("work", 0)
      )
    ),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      json_plan(
        (
          #|[{"id":"a","duration_minutes":1,"deadline":10,"dependencies":["b"]},{"id":"b","duration_minutes":1,"deadline":10,"dependencies":["a"]}]
        ),
      ),
    )
    is Err(InvalidPlanInput("/tasks", DependencyCycle)),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[{"start":4,"end":4}],"fixed_events":[],"tasks":[],"completed":[],"confirmed_blocks":[]}
      ),
    )
    is Err(InvalidPlanInput("/availability/0", InvalidWindow(_, _, 4, 4))),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[],"fixed_events":[],"tasks":[{"id":"work","duration_minutes":1,"deadline":10,"dependencies":[]}],"completed":[{"id":"missing","completed_at":0}],"confirmed_blocks":[]}
      ),
    )
    is Err(
      InvalidPlanInput("/completed/0/id", UnknownCompletedTaskId("missing"))
    ),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      json_plan(
        (
          #|[{"id":"same","duration_minutes":1,"deadline":10,"dependencies":[]},{"id":"same","duration_minutes":1,"deadline":20,"dependencies":[]}]
        ),
      ),
    )
    is Err(InvalidPlanInput("/tasks/1/id", DuplicateTaskId("same"))),
  )
  assert_true(
    @deadlineplan.parse_plan_json(
      (
        #|{"schema_version":1,"availability":[{"start":0,"end":10}],"fixed_events":[],"tasks":[{"id":"work","duration_minutes":5,"deadline":10,"dependencies":[]}],"completed":[],"confirmed_blocks":[{"task_id":"work","start":0,"end":3}]}
      ),
    )
    is Err(
      InvalidPlanInput(
        "/confirmed_blocks/0",
        ConfirmedDurationMismatch("work", 3L, 5)
      )
    ),
  )
}

///|
test "serializer refuses a manually constructed unsupported or invalid plan" {
  let valid : @deadlineplan.PlanDocument = {
    schema_version: 1,
    availability: [@deadlineplan.window(0, 10)],
    fixed_events: [],
    tasks: [@deadlineplan.task("work", 5, 10, [])],
    completed: [],
    confirmed_blocks: [],
  }
  assert_true(@deadlineplan.serialize_plan_json(valid) is Ok(_))
  let old : @deadlineplan.PlanDocument = {
    schema_version: 0,
    availability: valid.availability,
    fixed_events: valid.fixed_events,
    tasks: valid.tasks,
    completed: valid.completed,
    confirmed_blocks: valid.confirmed_blocks,
  }
  assert_true(
    @deadlineplan.serialize_plan_json(old) is Err(UnsupportedSchemaVersion(0)),
  )
  let bad : @deadlineplan.PlanDocument = {
    schema_version: 1,
    availability: [@deadlineplan.window(10, 10)],
    fixed_events: valid.fixed_events,
    tasks: valid.tasks,
    completed: valid.completed,
    confirmed_blocks: valid.confirmed_blocks,
  }
  assert_true(
    @deadlineplan.serialize_plan_json(bad)
    is Err(InvalidPlanInput("/availability/0", InvalidWindow(_, _, 10, 10))),
  )
}
