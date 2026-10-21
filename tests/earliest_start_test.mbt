///|
test "task constructors distinguish no release limit from an explicit one" {
  let unrestricted = @deadlineplan.task("unrestricted", 1, 30, [])
  let restricted = @deadlineplan.task_with_earliest_start(
    "restricted",
    10,
    30,
    [],
    20,
  )
  let at_zero = @deadlineplan.task_with_earliest_start("at-zero", 1, 5, [], 0)
  assert_true(unrestricted.earliest_start is None)
  assert_true(restricted.earliest_start is Some(20))
  assert_true(at_zero.earliest_start is Some(0))
  match
    @deadlineplan.schedule([@deadlineplan.window(20, 40)], [], [restricted]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 20)
      assert_eq(plan.blocks[0].window.end, 30)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  match @deadlineplan.schedule([@deadlineplan.window(-5, 5)], [], [at_zero]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "no continuous slot remains after release even though an earlier slot exists" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 20)],
      [@deadlineplan.fixed_event("meeting", 12, 16)],
      [@deadlineplan.task_with_earliest_start("work", 8, 20, [], 10)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_eq(plan.unscheduled[0].task_id, "work")
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "release time and dependency completion use the later bound" {
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 40)], [], [
      @deadlineplan.task("parent", 10, 40, []),
      @deadlineplan.task_with_earliest_start("child", 5, 40, ["parent"], 15),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.start, 15)
      assert_eq(plan.blocks[1].window.end, 20)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 40)], [], [
      @deadlineplan.task("first-parent", 10, 40, []),
      @deadlineplan.task("second-parent", 10, 40, []),
      @deadlineplan.task_with_earliest_start(
        "child",
        5,
        40,
        ["first-parent", "second-parent"],
        5,
      ),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.end, 20)
      assert_eq(plan.blocks[2].window.start, 20)
      assert_eq(plan.blocks[2].window.end, 25)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "release also respects fixed events and already scheduled work" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 40)],
      [@deadlineplan.fixed_event("meeting", 15, 20)],
      [
        @deadlineplan.task("first", 10, 10, []),
        @deadlineplan.task_with_earliest_start("gated", 10, 40, [], 5),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].window.start, 20)
      assert_eq(plan.blocks[1].window.end, 30)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "release at or after deadline is invalid but an insufficient span is unscheduled" {
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task_with_earliest_start("equal", 1, 10, [], 10),
    ])
    is Err(InvalidEarliestStart("equal", 10, 10)),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task_with_earliest_start("later", 1, 10, [], 11),
    ])
    is Err(InvalidEarliestStart("later", 11, 10)),
  )
  assert_true(
    @deadlineplan.schedule([@deadlineplan.window(-10, 10)], [], [
      @deadlineplan.task_with_earliest_start("negative", 1, -5, [], -5),
    ])
    is Err(InvalidEarliestStart("negative", -5, -5)),
  )
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 100)], [], [
      @deadlineplan.task_with_earliest_start("too-long", 2, 10, [], 9),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "negative and extreme release minutes never wrap time arithmetic" {
  match
    @deadlineplan.schedule([@deadlineplan.window(-100, -50)], [], [
      @deadlineplan.task_with_earliest_start("negative", 10, -70, [], -80),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, -80)
      assert_eq(plan.blocks[0].window.end, -70)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(-2147483648, -2147483646)],
      [],
      [
        @deadlineplan.task_with_earliest_start(
          "minimum",
          1,
          -2147483647,
          [],
          -2147483648,
        ),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, -2147483648)
      assert_eq(plan.blocks[0].window.end, -2147483647)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule([@deadlineplan.window(2147483645, 2147483647)], [], [
      @deadlineplan.task_with_earliest_start(
        "maximum",
        1,
        2147483647,
        [],
        2147483646,
      ),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 2147483646)
      assert_eq(plan.blocks[0].window.end, 2147483647)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule([@deadlineplan.window(2147483645, 2147483647)], [], [
      @deadlineplan.task_with_earliest_start(
        "overflow",
        2,
        2147483647,
        [],
        2147483646,
      ),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(2147483637, 2147483647)],
      [@deadlineplan.fixed_event("end", 2147483642, 2147483647)],
      [
        @deadlineplan.task_with_earliest_start(
          "blocked",
          2,
          2147483647,
          [],
          2147483641,
        ),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}
