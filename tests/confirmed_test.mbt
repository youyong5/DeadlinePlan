///|
fn confirmed(
  task_id : String,
  start : Int32,
  end : Int32,
) -> @deadlineplan.ScheduledBlock {
  { task_id, window: @deadlineplan.window(start, end), }
}

///|
test "student replan keeps confirmed homework when a new lecture moves review" {
  let tasks = [
    @deadlineplan.task("homework", 10, 30, []),
    @deadlineplan.task("exam-review", 15, 70, ["homework"]),
    @deadlineplan.task("summary", 10, 90, ["exam-review"]),
  ]
  let locked = [confirmed("homework", 0, 10)]
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      tasks,
      [],
      locked,
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.start, 10)
      assert_eq(plan.blocks[1].window.end, 25)
      assert_eq(plan.blocks[2].window.start, 25)
      assert_eq(plan.blocks[2].window.end, 35)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [@deadlineplan.fixed_event("new-lecture", 20, 35)],
      tasks,
      [],
      locked,
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].task_id, "homework")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].task_id, "exam-review")
      assert_eq(plan.blocks[1].window.start, 35)
      assert_eq(plan.blocks[1].window.end, 50)
      assert_eq(plan.blocks[2].task_id, "summary")
      assert_eq(plan.blocks[2].window.start, 50)
      assert_eq(plan.blocks[2].window.end, 60)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project replan keeps split design and waits for the latest prerequisite" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [
        @deadlineplan.fixed_event("standup", 10, 20),
        @deadlineplan.fixed_event("vendor-call", 30, 45),
      ],
      [
        @deadlineplan.task("approval", 1, 80, []),
        @deadlineplan.splittable_task("design", 20, 30, [], 10),
        @deadlineplan.task("build", 15, 70, ["design"]),
        @deadlineplan.task("handoff", 10, 100, ["build", "approval"]),
      ],
      [@deadlineplan.completed_task("approval", 65)],
      [confirmed("design", 0, 10), confirmed("design", 20, 30)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 4)
      assert_eq(plan.blocks[0].task_id, "design")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].task_id, "design")
      assert_eq(plan.blocks[1].window.start, 20)
      assert_eq(plan.blocks[1].window.end, 30)
      assert_eq(plan.blocks[2].task_id, "build")
      assert_eq(plan.blocks[2].window.start, 45)
      assert_eq(plan.blocks[2].window.end, 60)
      assert_eq(plan.blocks[3].task_id, "handoff")
      assert_eq(plan.blocks[3].window.start, 65)
      assert_eq(plan.blocks[3].window.end, 75)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "confirmed split blocks use their last end even when input is unordered" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 10), @deadlineplan.window(20, 40)],
      [],
      [
        @deadlineplan.splittable_task("split", 20, 30, [], 10),
        @deadlineplan.task("child", 5, 40, ["split"]),
      ],
      [],
      [confirmed("split", 20, 30), confirmed("split", 0, 10)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 20)
      assert_eq(plan.blocks[1].window.start, 0)
      assert_eq(plan.blocks[2].task_id, "child")
      assert_eq(plan.blocks[2].window.start, 30)
      assert_eq(plan.blocks[2].window.end, 35)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "confirmed time stays reserved when the remaining task cannot fit" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 10)],
      [],
      [
        @deadlineplan.task("locked", 5, 10, []),
        @deadlineplan.task("remaining", 6, 10, []),
      ],
      [],
      [confirmed("locked", 0, 5)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].task_id, "locked")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 5)
      assert_eq(plan.unscheduled.length(), 1)
      assert_eq(plan.unscheduled[0].task_id, "remaining")
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "confirmed blocks allow touching boundaries and merged availability" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(10, 20), @deadlineplan.window(0, 10)],
      [@deadlineplan.fixed_event("later", 20, 25)],
      [
        @deadlineplan.task("first", 10, 10, []),
        @deadlineplan.task("second", 10, 20, []),
      ],
      [],
      [confirmed("first", 0, 10), confirmed("second", 10, 20)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(10, 20), @deadlineplan.window(0, 10)],
      [],
      [@deadlineplan.task("spanning", 20, 20, [])],
      [],
      [confirmed("spanning", 0, 20)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.end, 20)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "confirmed block identity and time bounds are validated" {
  let availability = [@deadlineplan.window(0, 30)]
  let tasks = [@deadlineplan.task_with_earliest_start("work", 10, 20, [], 5)]
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("missing", 5, 15),
    ])
    is Err(UnknownConfirmedTaskId("missing")),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [@deadlineplan.completed_task("work", 10)],
      [confirmed("work", 5, 15)],
    )
    is Err(CompletedAndConfirmedTaskId("work")),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("work", 10, 10),
    ])
    is Err(InvalidConfirmedWindow("work", 10, 10)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("work", 15, 10),
    ])
    is Err(InvalidConfirmedWindow("work", 15, 10)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("work", 0, 10),
    ])
    is Err(ConfirmedBeforeEarliestStart("work", 0, 5)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("work", 15, 25),
    ])
    is Err(ConfirmedAfterDeadline("work", 25, 20)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("work", 25, 35),
    ])
    is Err(ConfirmedAfterDeadline("work", 35, 20)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 10)],
      [],
      [@deadlineplan.task("outside", 10, 30, [])],
      [],
      [confirmed("outside", 5, 15)],
    )
    is Err(ConfirmedOutsideAvailability("outside", 5, 15)),
  )
}

///|
test "continuous confirmations must be whole and split blocks must meet minimum" {
  let availability = [@deadlineplan.window(0, 50)]
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      [@deadlineplan.task("continuous", 20, 50, [])],
      [],
      [confirmed("continuous", 0, 10), confirmed("continuous", 20, 30)],
    )
    is Err(InvalidConfirmedBlockCount("continuous", 2)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      [@deadlineplan.task("continuous", 20, 50, [])],
      [],
      [confirmed("continuous", 0, 10)],
    )
    is Err(ConfirmedDurationMismatch("continuous", 10L, 20)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      [@deadlineplan.splittable_task("split", 20, 50, [], 8)],
      [],
      [confirmed("split", 0, 7), confirmed("split", 20, 33)],
    )
    is Err(ConfirmedBlockTooShort("split", 7L, 8)),
  )
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      [@deadlineplan.splittable_task("split", 20, 50, [], 8)],
      [],
      [confirmed("split", 0, 10)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.start, 10)
      assert_eq(plan.blocks[1].window.end, 20)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      [@deadlineplan.splittable_task("split", 20, 50, [], 8)],
      [],
      [confirmed("split", 0, 10), confirmed("split", 20, 35)],
    )
    is Err(ConfirmedDurationMismatch("split", 25L, 20)),
  )
}

///|
test "confirmed blocks cannot overlap events or one another" {
  let availability = [@deadlineplan.window(0, 30)]
  let tasks = [
    @deadlineplan.task("first", 10, 30, []),
    @deadlineplan.task("second", 10, 30, []),
  ]
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [@deadlineplan.fixed_event("meeting", 5, 15)],
      tasks,
      [],
      [confirmed("first", 0, 10)],
    )
    is Err(ConfirmedOverlapsFixedEvent("first", "meeting")),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("first", 0, 10),
      confirmed("second", 5, 15),
    ])
    is Err(ConfirmedBlocksOverlap("second", "first")),
  )
}

///|
test "confirmed and completed dependency timelines reject unresolved or late parents" {
  let tasks = [
    @deadlineplan.task("parent", 10, 30, []),
    @deadlineplan.task("child", 10, 50, ["parent"]),
  ]
  let availability = [@deadlineplan.window(0, 50)]
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("child", 20, 30),
    ])
    is Err(UnresolvedPriorDependency("child", "parent")),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [@deadlineplan.completed_task("child", 30)],
      [],
    )
    is Err(UnresolvedPriorDependency("child", "parent")),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [@deadlineplan.completed_task("parent", 25)],
      [confirmed("child", 20, 30)],
    )
    is Err(PriorDependencyFinishesLate("child", "parent", 25, 20)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [
        @deadlineplan.completed_task("parent", 35),
        @deadlineplan.completed_task("child", 30),
      ],
      [],
    )
    is Err(PriorDependencyFinishesLate("child", "parent", 35, 30)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [@deadlineplan.completed_task("child", 25)],
      [confirmed("parent", 20, 30)],
    )
    is Err(PriorDependencyFinishesLate("child", "parent", 30, 25)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(availability, [], tasks, [], [
      confirmed("parent", 20, 30),
      confirmed("child", 10, 20),
    ])
    is Err(PriorDependencyFinishesLate("child", "parent", 30, 10)),
  )
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      availability,
      [],
      tasks,
      [@deadlineplan.completed_task("child", 20)],
      [confirmed("parent", 10, 20)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].task_id, "parent")
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "confirmed duration calculations span both Int32 extremes safely" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(-2147483648, 2147483647)],
      [],
      [@deadlineplan.task("extreme", 2147483647, 2147483647, [])],
      [],
      [confirmed("extreme", -2147483648, -1)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, -2147483648)
      assert_eq(plan.blocks[0].window.end, -1)
    }
    Err(_) => assert_true(false)
  }
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(-2147483648, 2147483647)],
      [],
      [@deadlineplan.splittable_task("overlong", 1, 2147483647, [], 1)],
      [],
      [
        confirmed("overlong", -2147483648, -1),
        confirmed("overlong", 0, 2147483647),
      ],
    )
    is Err(ConfirmedDurationMismatch("overlong", 4294967294L, 1)),
  )
}

///|
test "older schedule entries match replanning with no confirmed blocks" {
  let availability = [@deadlineplan.window(0, 30)]
  let tasks = [
    @deadlineplan.task("done", 5, 10, []),
    @deadlineplan.task("child", 10, 30, ["done"]),
  ]
  let completed = [@deadlineplan.completed_task("done", 15)]
  match
    (
      @deadlineplan.schedule_with_completed(availability, [], tasks, completed),
      @deadlineplan.schedule_with_confirmed_blocks(
        availability,
        [],
        tasks,
        completed,
        [],
      ),
    ) {
    (Ok(older), Ok(replanned)) => {
      assert_eq(older.blocks.length(), 1)
      assert_eq(replanned.blocks.length(), 1)
      assert_eq(older.blocks[0].window.start, 15)
      assert_eq(replanned.blocks[0].window.start, 15)
      assert_eq(older.unscheduled.length(), 0)
      assert_eq(replanned.unscheduled.length(), 0)
    }
    _ => assert_true(false)
  }
  match
    (
      @deadlineplan.schedule(availability, [], tasks),
      @deadlineplan.schedule_with_confirmed_blocks(
        availability,
        [],
        tasks,
        [],
        [],
      ),
    ) {
    (Ok(older), Ok(replanned)) => {
      assert_eq(older.blocks.length(), replanned.blocks.length())
      assert_eq(older.blocks[0].window.start, replanned.blocks[0].window.start)
      assert_eq(older.blocks[1].window.start, replanned.blocks[1].window.start)
    }
    _ => assert_true(false)
  }
}
