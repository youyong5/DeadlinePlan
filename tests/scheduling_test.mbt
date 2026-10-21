///|
/// Public-API examples: this test package imports the publishable module path.
test "student coursework uses the public scheduling API" {
  let result = @deadlineplan.schedule(
    [@deadlineplan.window(0, 180)],
    [@deadlineplan.fixed_event("lecture", 60, 90)],
    [
      @deadlineplan.task("math-homework", 45, 120, []),
      @deadlineplan.task("history-essay", 60, 180, ["math-homework"]),
      @deadlineplan.task("biology-exam-review", 40, 140, []),
    ],
  )
  match result {
    Ok(schedule) => {
      assert_eq(schedule.blocks.length(), 2)
      assert_eq(schedule.blocks[0].task_id, "math-homework")
      assert_eq(schedule.blocks[0].window.start, 0)
      assert_eq(schedule.blocks[0].window.end, 45)
      assert_eq(schedule.blocks[1].task_id, "biology-exam-review")
      assert_eq(schedule.blocks[1].window.start, 90)
      assert_eq(schedule.blocks[1].window.end, 130)
      assert_eq(schedule.unscheduled.length(), 1)
      assert_eq(schedule.unscheduled[0].task_id, "history-essay")
      assert_true(schedule.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project delivery data uses the same public scheduling API" {
  let result = @deadlineplan.schedule(
    [@deadlineplan.window(0, 300)],
    [@deadlineplan.fixed_event("stakeholder-call", 120, 150)],
    [
      @deadlineplan.task("draft", 90, 160, []),
      @deadlineplan.task("review", 30, 220, ["draft"]),
      @deadlineplan.task("release-package", 60, 300, ["review"]),
    ],
  )
  match result {
    Ok(schedule) => {
      assert_eq(schedule.blocks.length(), 3)
      assert_eq(schedule.blocks[0].window.start, 0)
      assert_eq(schedule.blocks[0].window.end, 90)
      assert_eq(schedule.blocks[1].window.start, 90)
      assert_eq(schedule.blocks[1].window.end, 120)
      assert_eq(schedule.blocks[2].window.start, 150)
      assert_eq(schedule.blocks[2].window.end, 210)
      assert_eq(schedule.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "validation rejects malformed dependency graphs and windows" {
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(10, 10)], [], [])
    is Err(InvalidWindow(_, _, _, _)),
  )
  assert_true(
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 100)],
      [@deadlineplan.fixed_event("broken-event", 30, 30)],
      [],
    )
    is Err(InvalidWindow(_, _, _, _)),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task("zero-effort", 0, 40, []),
    ])
    is Err(InvalidTaskDuration("zero-effort", 0)),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task("same", 10, 40, []),
      @deadlineplan.task("same", 10, 50, []),
    ])
    is Err(DuplicateTaskId("same")),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task("deliver", 10, 40, ["missing"]),
    ])
    is Err(UnknownDependency("deliver", "missing")),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task("first", 10, 40, ["second"]),
      @deadlineplan.task("second", 10, 50, ["first"]),
    ])
    is Err(DependencyCycle),
  )
}
