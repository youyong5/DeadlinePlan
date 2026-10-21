///|
fn partial_block(
  task_id : String,
  start : Int32,
  end : Int32,
) -> @deadlineplan.ScheduledBlock {
  { task_id, window: @deadlineplan.window(start, end), }
}

///|
test "student revision resumes around lectures before the exam" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 120)],
      [
        @deadlineplan.fixed_event("lecture-one", 20, 40),
        @deadlineplan.fixed_event("lecture-two", 60, 80),
      ],
      [
        @deadlineplan.splittable_task("biology-review", 60, 100, [], 20),
        @deadlineplan.task("exam-setup", 10, 120, ["biology-review"]),
      ],
      [],
      [partial_block("biology-review", 0, 20)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 4)
      assert_eq(plan.blocks[0].task_id, "biology-review")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 20)
      assert_eq(plan.blocks[1].window.start, 40)
      assert_eq(plan.blocks[1].window.end, 60)
      assert_eq(plan.blocks[2].window.start, 80)
      assert_eq(plan.blocks[2].window.end, 100)
      assert_eq(plan.blocks[3].task_id, "exam-setup")
      assert_eq(plan.blocks[3].window.start, 100)
      assert_eq(plan.blocks[3].window.end, 110)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project design resumes after a call and waits for completed approval" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 120)],
      [@deadlineplan.fixed_event("vendor-call", 30, 50)],
      [
        @deadlineplan.splittable_task("design", 70, 90, [], 20),
        @deadlineplan.task("approval", 1, 110, []),
        @deadlineplan.task("release", 10, 120, ["design", "approval"]),
      ],
      [@deadlineplan.completed_task("approval", 100)],
      [partial_block("design", 0, 30)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].task_id, "design")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 30)
      assert_eq(plan.blocks[1].task_id, "design")
      assert_eq(plan.blocks[1].window.start, 50)
      assert_eq(plan.blocks[1].window.end, 90)
      assert_eq(plan.blocks[2].task_id, "release")
      assert_eq(plan.blocks[2].window.start, 100)
      assert_eq(plan.blocks[2].window.end, 110)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dependent waits for the latest block even if confirmation lies later" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 110)],
      [],
      [
        @deadlineplan.splittable_task("parent", 60, 100, [], 20),
        @deadlineplan.task("child", 5, 110, ["parent"]),
      ],
      [],
      [partial_block("parent", 80, 100)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 80)
      assert_eq(plan.blocks[0].window.end, 100)
      assert_eq(plan.blocks[1].task_id, "parent")
      assert_eq(plan.blocks[1].window.start, 0)
      assert_eq(plan.blocks[1].window.end, 40)
      assert_eq(plan.blocks[2].task_id, "child")
      assert_eq(plan.blocks[2].window.start, 100)
      assert_eq(plan.blocks[2].window.end, 105)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "remaining split work waits for a completed prerequisite" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [
        @deadlineplan.task("brief", 1, 40, []),
        @deadlineplan.splittable_task("work", 40, 90, ["brief"], 20),
        @deadlineplan.task("delivery", 5, 100, ["work"]),
      ],
      [@deadlineplan.completed_task("brief", 35)],
      [partial_block("work", 40, 60)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 40)
      assert_eq(plan.blocks[0].window.end, 60)
      assert_eq(plan.blocks[1].task_id, "work")
      assert_eq(plan.blocks[1].window.start, 60)
      assert_eq(plan.blocks[1].window.end, 80)
      assert_eq(plan.blocks[2].window.start, 80)
      assert_eq(plan.blocks[2].window.end, 85)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "failed remainder keeps confirmed work but no tentative work or successor" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [
        @deadlineplan.window(0, 40),
        @deadlineplan.window(50, 80),
        @deadlineplan.window(90, 110),
      ],
      [],
      [
        @deadlineplan.splittable_task("partial", 100, 110, [], 20),
        @deadlineplan.task("child", 1, 130, ["partial"]),
        @deadlineplan.task("independent", 30, 140, []),
      ],
      [],
      [partial_block("partial", 0, 40)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].task_id, "partial")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 40)
      assert_eq(plan.blocks[1].task_id, "independent")
      assert_eq(plan.blocks[1].window.start, 50)
      assert_eq(plan.blocks[1].window.end, 80)
      assert_eq(plan.unscheduled.length(), 2)
      assert_eq(plan.unscheduled[0].task_id, "partial")
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(60))
      assert_eq(plan.unscheduled[1].task_id, "child")
      assert_true(
        plan.unscheduled[1].reason is DependencyNotScheduled("partial"),
      )
    }
    Err(_) => assert_true(false)
  }
}

///|
test "one short final block may finish confirmed progress" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 50), @deadlineplan.window(60, 80)],
      [],
      [
        @deadlineplan.splittable_task("work", 60, 70, [], 40),
        @deadlineplan.task("successor", 1, 80, ["work"]),
      ],
      [],
      [partial_block("work", 0, 50)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 50)
      assert_eq(plan.blocks[1].task_id, "work")
      assert_eq(plan.blocks[1].window.start, 60)
      assert_eq(plan.blocks[1].window.end, 70)
      assert_eq(plan.blocks[2].task_id, "successor")
      assert_eq(plan.blocks[2].window.start, 70)
      assert_eq(plan.blocks[2].window.end, 71)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [
        @deadlineplan.window(0, 50),
        @deadlineplan.window(60, 100),
        @deadlineplan.window(110, 120),
      ],
      [],
      [@deadlineplan.splittable_task("work", 100, 120, [], 40)],
      [],
      [partial_block("work", 0, 50)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[1].window.start, 60)
      assert_eq(plan.blocks[1].window.end, 100)
      assert_eq(plan.blocks[2].window.start, 110)
      assert_eq(plan.blocks[2].window.end, 120)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 40), @deadlineplan.window(50, 60)],
      [],
      [@deadlineplan.splittable_task("fresh", 50, 60, [], 40)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(50))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "remaining work respects opening time and deadline" {
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 130)],
      [
        @deadlineplan.fixed_event("break-one", 70, 80),
        @deadlineplan.fixed_event("break-two", 100, 110),
      ],
      [
        @deadlineplan.splittable_task_with_earliest_start(
          "work",
          60,
          130,
          [],
          50,
          20,
        ),
      ],
      [],
      [partial_block("work", 50, 70)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[1].window.start, 80)
      assert_eq(plan.blocks[1].window.end, 100)
      assert_eq(plan.blocks[2].window.start, 110)
      assert_eq(plan.blocks[2].window.end, 130)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [@deadlineplan.splittable_task("work", 60, 55, [], 20)],
      [],
      [partial_block("work", 0, 40)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.end, 40)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(20))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "excess confirmed work is rejected and continuous partial work stays invalid" {
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [@deadlineplan.splittable_task("over", 50, 100, [], 20)],
      [],
      [partial_block("over", 0, 30), partial_block("over", 40, 70)],
    )
    is Err(ConfirmedDurationMismatch("over", 60L, 50)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [@deadlineplan.task("continuous", 30, 100, [])],
      [],
      [partial_block("continuous", 0, 20)],
    )
    is Err(ConfirmedDurationMismatch("continuous", 20L, 30)),
  )
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [@deadlineplan.splittable_task("work", 60, 100, [], 20)],
      [@deadlineplan.completed_task("work", 50)],
      [partial_block("work", 0, 20)],
    )
    is Err(CompletedAndConfirmedTaskId("work")),
  )
}

///|
test "partial confirmation is not a finished prerequisite of completed work" {
  assert_true(
    @deadlineplan.schedule_with_confirmed_blocks(
      [@deadlineplan.window(0, 100)],
      [],
      [
        @deadlineplan.splittable_task("parent", 60, 100, [], 20),
        @deadlineplan.task("child", 1, 100, ["parent"]),
      ],
      [@deadlineplan.completed_task("child", 50)],
      [partial_block("parent", 0, 20)],
    )
    is Err(UnresolvedPriorDependency("child", "parent")),
  )
}

///|
fn small_partial_exists(
  capacities : Array[Int32],
  index : Int32,
  remaining : Int32,
  minimum : Int32,
) -> Bool {
  if remaining == 0 {
    return true
  }
  if index == capacities.length() {
    return false
  }
  if small_partial_exists(capacities, index + 1, remaining, minimum) {
    return true
  }
  if remaining < minimum && capacities[index] >= remaining {
    return true
  }
  let mut take = minimum
  while take <= capacities[index] && take <= remaining {
    if small_partial_exists(capacities, index + 1, remaining - take, minimum) {
      return true
    }
    take = take + 1
  }
  false
}

///|
test "small partial allocations agree with exhaustive short-tail search" {
  let mut encoded = 0
  while encoded < 625 {
    let capacities : Array[Int32] = []
    let mut digits = encoded
    let mut index = 0
    while index < 4 {
      capacities.push(digits % 5)
      digits = digits / 5
      index = index + 1
    }
    let mut minimum = 2
    while minimum <= 4 {
      let mut remaining = 1
      while remaining <= 12 {
        let windows : Array[@deadlineplan.TimeWindow] = [
          @deadlineplan.window(0, minimum),
        ]
        index = 0
        while index < 4 {
          if capacities[index] > 0 {
            windows.push(
              @deadlineplan.window(
                10 + index * 10,
                10 + index * 10 + capacities[index],
              ),
            )
          }
          index = index + 1
        }
        let expected = small_partial_exists(capacities, 0, remaining, minimum)
        match
          @deadlineplan.schedule_with_confirmed_blocks(
            windows,
            [],
            [
              @deadlineplan.splittable_task(
                "work",
                minimum + remaining,
                50,
                [],
                minimum,
              ),
            ],
            [],
            [partial_block("work", 0, minimum)],
          ) {
          Ok(plan) => {
            let actual = plan.unscheduled.length() == 0
            assert_eq(actual, expected)
            if actual {
              let mut total = minimum
              let mut block_index = 1
              while block_index < plan.blocks.length() {
                let block = plan.blocks[block_index].window
                let length = block.end - block.start
                if length < minimum {
                  assert_eq(block_index, plan.blocks.length() - 1)
                }
                total = total + length
                block_index = block_index + 1
              }
              assert_eq(total, minimum + remaining)
            } else {
              assert_eq(plan.blocks.length(), 1)
              match plan.unscheduled[0].reason {
                SplitWorkIncomplete(minutes) => assert_eq(minutes, remaining)
                _ => assert_true(false)
              }
            }
          }
          Err(_) => assert_true(false)
        }
        remaining = remaining + 1
      }
      minimum = minimum + 1
    }
    encoded = encoded + 1
  }
}
