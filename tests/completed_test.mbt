///|
test "student homework waits for the completed assignment briefing" {
  let briefing = @deadlineplan.completed_task("assignment-briefing", 30)
  assert_eq(briefing.id, "assignment-briefing")
  assert_eq(briefing.completed_at, 30)
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(0, 100)],
      [@deadlineplan.fixed_event("lecture", 40, 50)],
      [
        @deadlineplan.task("assignment-briefing", 5, 40, []),
        @deadlineplan.task_with_earliest_start(
          "homework",
          20,
          80,
          ["assignment-briefing"],
          20,
        ),
        @deadlineplan.task("quiz-preparation", 10, 100, ["homework"]),
      ],
      [briefing],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].task_id, "homework")
      assert_eq(plan.blocks[0].window.start, 50)
      assert_eq(plan.blocks[0].window.end, 70)
      assert_eq(plan.blocks[1].task_id, "quiz-preparation")
      assert_eq(plan.blocks[1].window.start, 70)
      assert_eq(plan.blocks[1].window.end, 80)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project handoff waits for completed approvals and scheduled split work" {
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(0, 100)],
      [@deadlineplan.fixed_event("client-call", 50, 60)],
      [
        @deadlineplan.task("materials-ready", 5, 25, []),
        @deadlineplan.task("approval", 1, 80, []),
        @deadlineplan.task("assembly", 15, 45, ["materials-ready"]),
        @deadlineplan.splittable_task("documentation", 20, 80, ["assembly"], 10),
        @deadlineplan.task("handoff", 5, 90, ["documentation", "approval"]),
      ],
      [
        @deadlineplan.completed_task("materials-ready", 25),
        @deadlineplan.completed_task("approval", 72),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 4)
      assert_eq(plan.blocks[0].task_id, "assembly")
      assert_eq(plan.blocks[0].window.start, 25)
      assert_eq(plan.blocks[0].window.end, 40)
      assert_eq(plan.blocks[1].task_id, "documentation")
      assert_eq(plan.blocks[1].window.start, 40)
      assert_eq(plan.blocks[1].window.end, 50)
      assert_eq(plan.blocks[2].task_id, "documentation")
      assert_eq(plan.blocks[2].window.start, 60)
      assert_eq(plan.blocks[2].window.end, 70)
      assert_eq(plan.blocks[3].task_id, "handoff")
      assert_eq(plan.blocks[3].window.start, 72)
      assert_eq(plan.blocks[3].window.end, 77)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "a completed splittable prerequisite contributes its actual finish only" {
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(0, 30)],
      [],
      [
        @deadlineplan.splittable_task("research", 20, 30, [], 10),
        @deadlineplan.task("summary", 5, 25, ["research"]),
      ],
      [@deadlineplan.completed_task("research", 15)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].task_id, "summary")
      assert_eq(plan.blocks[0].window.start, 15)
      assert_eq(plan.blocks[0].window.end, 20)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "a scheduled split predecessor can finish later than a completed one" {
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(0, 10), @deadlineplan.window(20, 40)],
      [],
      [
        @deadlineplan.task("approval", 1, 10, []),
        @deadlineplan.splittable_task("draft", 20, 30, [], 10),
        @deadlineplan.task("deliver", 5, 40, ["approval", "draft"]),
      ],
      [@deadlineplan.completed_task("approval", 5)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].task_id, "draft")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].task_id, "draft")
      assert_eq(plan.blocks[1].window.start, 20)
      assert_eq(plan.blocks[1].window.end, 30)
      assert_eq(plan.blocks[2].task_id, "deliver")
      assert_eq(plan.blocks[2].window.start, 30)
      assert_eq(plan.blocks[2].window.end, 35)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "completion at minute zero is a real dependency bound without reservation" {
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(-10, 20)],
      [],
      [
        @deadlineplan.task("done", 10, 5, []),
        @deadlineplan.task("independent", 10, 0, []),
        @deadlineplan.task("child", 5, 10, ["done"]),
      ],
      [@deadlineplan.completed_task("done", 0)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].task_id, "independent")
      assert_eq(plan.blocks[0].window.start, -10)
      assert_eq(plan.blocks[0].window.end, 0)
      assert_eq(plan.blocks[1].task_id, "child")
      assert_eq(plan.blocks[1].window.start, 0)
      assert_eq(plan.blocks[1].window.end, 5)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "a completed dependency past the deadline gives a slot failure" {
  match
    @deadlineplan.schedule_with_completed(
      [@deadlineplan.window(0, 20)],
      [],
      [
        @deadlineplan.task("done", 1, 5, []),
        @deadlineplan.task("continuous", 1, 10, ["done"]),
        @deadlineplan.splittable_task("split", 5, 10, ["done"], 2),
      ],
      [@deadlineplan.completed_task("done", 11)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 2)
      assert_eq(plan.unscheduled[0].task_id, "continuous")
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
      assert_eq(plan.unscheduled[1].task_id, "split")
      assert_true(plan.unscheduled[1].reason is SplitWorkIncomplete(5))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "completion records reject unknown and duplicate task IDs without dropping cycle checks" {
  let tasks = [@deadlineplan.task("known", 1, 10, [])]
  assert_true(
    @deadlineplan.schedule_with_completed([], [], tasks, [
      @deadlineplan.completed_task("missing", 0),
    ])
    is Err(UnknownCompletedTaskId("missing")),
  )
  assert_true(
    @deadlineplan.schedule_with_completed([], [], tasks, [
      @deadlineplan.completed_task("known", 0),
      @deadlineplan.completed_task("known", 1),
    ])
    is Err(DuplicateCompletedTaskId("known")),
  )
  assert_true(
    @deadlineplan.schedule_with_completed(
      [],
      [],
      [
        @deadlineplan.task("a", 1, 10, ["b"]),
        @deadlineplan.task("b", 1, 10, ["a"]),
      ],
      [@deadlineplan.completed_task("a", 0)],
    )
    is Err(DependencyCycle),
  )
}

///|
test "all completed tasks need no availability and make no plan entries" {
  match
    @deadlineplan.schedule_with_completed(
      [],
      [],
      [
        @deadlineplan.task("first", 5, 10, []),
        @deadlineplan.task("second", 5, 20, ["first"]),
      ],
      [
        @deadlineplan.completed_task("first", -5),
        @deadlineplan.completed_task("second", 0),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "the original schedule entry equals an empty completion-record call" {
  let available = [@deadlineplan.window(0, 30)]
  let events = [@deadlineplan.fixed_event("meeting", 10, 15)]
  let tasks = [
    @deadlineplan.task("parent", 10, 10, []),
    @deadlineplan.task("child", 5, 20, ["parent"]),
    @deadlineplan.task("too-long", 20, 30, []),
  ]
  match
    (
      @deadlineplan.schedule(available, events, tasks),
      @deadlineplan.schedule_with_completed(available, events, tasks, []),
    ) {
    (Ok(original), Ok(with_completed)) => {
      assert_eq(original.blocks.length(), with_completed.blocks.length())
      assert_eq(
        original.unscheduled.length(),
        with_completed.unscheduled.length(),
      )
      let mut index = 0
      while index < original.blocks.length() {
        assert_eq(
          original.blocks[index].task_id,
          with_completed.blocks[index].task_id,
        )
        assert_eq(
          original.blocks[index].window.start,
          with_completed.blocks[index].window.start,
        )
        assert_eq(
          original.blocks[index].window.end,
          with_completed.blocks[index].window.end,
        )
        index = index + 1
      }
      index = 0
      while index < original.unscheduled.length() {
        assert_eq(
          original.unscheduled[index].task_id,
          with_completed.unscheduled[index].task_id,
        )
        assert_true(original.unscheduled[index].reason is NoContinuousSlot)
        assert_true(
          with_completed.unscheduled[index].reason is NoContinuousSlot,
        )
        index = index + 1
      }
    }
    _ => assert_true(false)
  }
}
