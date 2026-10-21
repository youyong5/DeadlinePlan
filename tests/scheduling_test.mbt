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
    @deadlineplan.schedule([@deadlineplan.window(11, 10)], [], [])
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

///|
test "half-open boundaries permit adjacent events and task blocks" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 20)],
      [
        @deadlineplan.fixed_event("opening", 0, 5),
        @deadlineplan.fixed_event("break", 10, 15),
      ],
      [
        @deadlineplan.task("first", 5, 10, []),
        @deadlineplan.task("second", 5, 20, []),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 5)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.start, 15)
      assert_eq(plan.blocks[1].window.end, 20)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "unordered overlapping and adjacent windows form one continuous availability" {
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(20, 40),
        @deadlineplan.window(0, 15),
        @deadlineplan.window(10, 25),
        @deadlineplan.window(0, 15),
        @deadlineplan.window(40, 50),
      ],
      [],
      [
        @deadlineplan.task("large", 18, 40, []),
        @deadlineplan.task("middle", 10, 40, []),
        @deadlineplan.task("last", 22, 50, []),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 18)
      assert_eq(plan.blocks[1].window.start, 18)
      assert_eq(plan.blocks[1].window.end, 28)
      assert_eq(plan.blocks[2].window.start, 28)
      assert_eq(plan.blocks[2].window.end, 50)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "a fixed event occupying the candidate block moves work after it" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 30)],
      [@deadlineplan.fixed_event("meeting", 5, 15)],
      [@deadlineplan.task("work", 10, 30, [])],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 15)
      assert_eq(plan.blocks[0].window.end, 25)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "a dependent task begins after all prerequisites finish" {
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 40)], [], [
      @deadlineplan.task("deliver", 5, 25, ["draft", "review"]),
      @deadlineplan.task("draft", 10, 40, []),
      @deadlineplan.task("review", 10, 40, []),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].task_id, "draft")
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].task_id, "review")
      assert_eq(plan.blocks[1].window.end, 20)
      assert_eq(plan.blocks[2].task_id, "deliver")
      assert_eq(plan.blocks[2].window.start, 20)
      assert_eq(plan.blocks[2].window.end, 25)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "an unscheduled prerequisite blocks its successor with its ID" {
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 10)], [], [
      @deadlineplan.task("parent", 11, 10, []),
      @deadlineplan.task("child", 1, 10, ["parent"]),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 2)
      assert_eq(plan.unscheduled[0].task_id, "parent")
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
      assert_eq(plan.unscheduled[1].task_id, "child")
      assert_true(
        plan.unscheduled[1].reason is DependencyNotScheduled("parent"),
      )
    }
    Err(_) => assert_true(false)
  }
}

///|
test "empty task input returns an empty plan" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 10)],
      [@deadlineplan.fixed_event("occupied", 0, 10)],
      [],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "identical input yields the same order, times, and reasons" {
  let availability = [@deadlineplan.window(20, 30), @deadlineplan.window(0, 10)]
  let tasks = [
    @deadlineplan.task("one", 10, 30, []),
    @deadlineplan.task("two", 10, 30, []),
    @deadlineplan.task("three", 10, 30, []),
  ]
  let first = @deadlineplan.schedule(availability, [], tasks)
  let second = @deadlineplan.schedule(availability, [], tasks)
  match (first, second) {
    (Ok(a), Ok(b)) => {
      assert_eq(a.blocks.length(), b.blocks.length())
      assert_eq(a.unscheduled.length(), b.unscheduled.length())
      for index = 0; index < a.blocks.length(); index = index + 1 {
        assert_eq(a.blocks[index].task_id, b.blocks[index].task_id)
        assert_eq(a.blocks[index].window.start, b.blocks[index].window.start)
        assert_eq(a.blocks[index].window.end, b.blocks[index].window.end)
      }
      assert_eq(a.unscheduled[0].task_id, b.unscheduled[0].task_id)
      assert_true(a.unscheduled[0].reason is NoContinuousSlot)
      assert_true(b.unscheduled[0].reason is NoContinuousSlot)
    }
    _ => assert_true(false)
  }
}

///|
test "extreme UTC minutes do not overflow slot calculations" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(-2147483648, 2147483647)],
      [],
      [@deadlineplan.task("earliest", 1, 2147483647, [])],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, -2147483648)
      assert_eq(plan.blocks[0].window.end, -2147483647)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule([@deadlineplan.window(2147483640, 2147483647)], [], [
      @deadlineplan.task("past-deadline", 1, -2147483648, []),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule([@deadlineplan.window(2147483640, 2147483647)], [], [
      @deadlineplan.task("latest", 7, 2147483647, []),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 2147483640)
      assert_eq(plan.blocks[0].window.end, 2147483647)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dependency scheduling also works before minute zero" {
  match
    @deadlineplan.schedule([@deadlineplan.window(-100, -50)], [], [
      @deadlineplan.task("parent", 10, -70, []),
      @deadlineplan.task("child", 10, -60, ["parent"]),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, -100)
      assert_eq(plan.blocks[0].window.end, -90)
      assert_eq(plan.blocks[1].window.start, -90)
      assert_eq(plan.blocks[1].window.end, -80)
    }
    Err(_) => assert_true(false)
  }
}
