///|
test "split allocation can shorten each of three equal gaps" {
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(0, 50),
        @deadlineplan.window(60, 110),
        @deadlineplan.window(120, 170),
      ],
      [],
      [@deadlineplan.splittable_task("work", 120, 170, [], 40)],
    ) {
    Ok(plan) => {
      assert_eq(plan.unscheduled.length(), 0)
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 40)
      assert_eq(plan.blocks[1].window.start, 60)
      assert_eq(plan.blocks[1].window.end, 100)
      assert_eq(plan.blocks[2].window.start, 120)
      assert_eq(plan.blocks[2].window.end, 160)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project handoff is split and its review waits for the final block" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 160)],
      [
        @deadlineplan.fixed_event("client-call", 40, 60),
        @deadlineplan.fixed_event("deployment", 100, 120),
      ],
      [
        @deadlineplan.task("draft", 30, 50, []),
        @deadlineplan.splittable_task_with_earliest_start(
          "handoff",
          60,
          150,
          ["draft"],
          30,
          20,
        ),
        @deadlineplan.task("delivery-review", 10, 160, ["handoff"]),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 4)
      assert_eq(plan.blocks[0].task_id, "draft")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 30)
      assert_eq(plan.blocks[1].task_id, "handoff")
      assert_eq(plan.blocks[1].window.start, 60)
      assert_eq(plan.blocks[1].window.end, 100)
      assert_eq(plan.blocks[2].task_id, "handoff")
      assert_eq(plan.blocks[2].window.start, 120)
      assert_eq(plan.blocks[2].window.end, 140)
      assert_eq(plan.blocks[3].task_id, "delivery-review")
      assert_eq(plan.blocks[3].window.start, 140)
      assert_eq(plan.blocks[3].window.end, 150)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "the final remainder is reserved as a full minimum-sized block" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(10, 13), @deadlineplan.window(0, 4)],
      [],
      [@deadlineplan.splittable_task("work", 6, 13, [], 3)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 3)
      assert_eq(plan.blocks[1].window.start, 10)
      assert_eq(plan.blocks[1].window.end, 13)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 4), @deadlineplan.window(10, 12)],
      [],
      [@deadlineplan.splittable_task("cannot-make-two-blocks", 5, 12, [], 3)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(5))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "split blocks may touch their opening time and final deadline" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(30, 40), @deadlineplan.window(10, 20)],
      [],
      [
        @deadlineplan.splittable_task_with_earliest_start(
          "exact-boundaries",
          20,
          40,
          [],
          10,
          10,
        ),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 10)
      assert_eq(plan.blocks[0].window.end, 20)
      assert_eq(plan.blocks[1].window.start, 30)
      assert_eq(plan.blocks[1].window.end, 40)
      assert_eq(plan.unscheduled.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "failed split work releases every tentative block and blocks its dependent" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 10), @deadlineplan.window(20, 25)],
      [],
      [
        @deadlineplan.splittable_task("incomplete", 18, 30, [], 5),
        @deadlineplan.task("dependent", 1, 35, ["incomplete"]),
        @deadlineplan.task("independent", 10, 40, []),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].task_id, "independent")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.unscheduled.length(), 2)
      assert_eq(plan.unscheduled[0].task_id, "incomplete")
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(18))
      assert_eq(plan.unscheduled[1].task_id, "dependent")
      assert_true(
        plan.unscheduled[1].reason is DependencyNotScheduled("incomplete"),
      )
    }
    Err(_) => assert_true(false)
  }
}

///|
test "existing constructors still require a continuous work block" {
  match
    @deadlineplan.schedule(
      [@deadlineplan.window(0, 10), @deadlineplan.window(20, 30)],
      [],
      [
        @deadlineplan.task("plain", 15, 30, []),
        @deadlineplan.task_with_earliest_start("released", 15, 30, [], 0),
        @deadlineplan.splittable_task("split", 15, 30, [], 5),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].task_id, "split")
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 10)
      assert_eq(plan.blocks[1].task_id, "split")
      assert_eq(plan.blocks[1].window.start, 20)
      assert_eq(plan.blocks[1].window.end, 25)
      assert_eq(plan.unscheduled.length(), 2)
      assert_eq(plan.unscheduled[0].task_id, "plain")
      assert_true(plan.unscheduled[0].reason is NoContinuousSlot)
      assert_eq(plan.unscheduled[1].task_id, "released")
      assert_true(plan.unscheduled[1].reason is NoContinuousSlot)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "minimum block duration is positive and cannot exceed total work" {
  assert_true(
    @deadlineplan.schedule([], [], [
      @deadlineplan.splittable_task("zero", 5, 20, [], 0),
    ])
    is Err(InvalidMinimumBlock("zero", 0, 5)),
  )
  assert_true(
    @deadlineplan.schedule([], [], [
      @deadlineplan.splittable_task("negative", 5, 20, [], -1),
    ])
    is Err(InvalidMinimumBlock("negative", -1, 5)),
  )
  assert_true(
    @deadlineplan.schedule([], [], [
      @deadlineplan.splittable_task("too-large", 5, 20, [], 6),
    ])
    is Err(InvalidMinimumBlock("too-large", 6, 5)),
  )
  match
    @deadlineplan.schedule([@deadlineplan.window(0, 5)], [], [
      @deadlineplan.splittable_task("equal", 5, 5, [], 5),
    ]) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 1)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 5)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "split calculations safely span both ends of the Int32 minute range" {
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(2147483637, 2147483647),
        @deadlineplan.window(-2147483648, -2147483638),
      ],
      [],
      [@deadlineplan.splittable_task("extreme", 20, 2147483647, [], 10)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, -2147483648)
      assert_eq(plan.blocks[0].window.end, -2147483638)
      assert_eq(plan.blocks[1].window.start, 2147483637)
      assert_eq(plan.blocks[1].window.end, 2147483647)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(-2147483648, -2147483600),
        @deadlineplan.window(0, 50),
        @deadlineplan.window(2147483600, 2147483647),
      ],
      [],
      [
        @deadlineplan.splittable_task(
          "extreme-rebalance",
          120,
          2147483647,
          [],
          40,
        ),
      ],
    ) {
    Ok(plan) => {
      assert_eq(plan.unscheduled.length(), 0)
      assert_eq(plan.blocks.length(), 3)
      assert_eq(plan.blocks[0].window.start, -2147483648)
      assert_eq(plan.blocks[0].window.end, -2147483608)
      assert_eq(plan.blocks[1].window.start, 0)
      assert_eq(plan.blocks[1].window.end, 40)
      assert_eq(plan.blocks[2].window.start, 2147483600)
      assert_eq(plan.blocks[2].window.end, 2147483640)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "different gap capacities may require skipping or shortening a gap" {
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(0, 5),
        @deadlineplan.window(10, 18),
        @deadlineplan.window(20, 28),
      ],
      [],
      [@deadlineplan.splittable_task("skip-short", 16, 28, [], 8)],
    ) {
    Ok(plan) => {
      assert_eq(plan.unscheduled.length(), 0)
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 10)
      assert_eq(plan.blocks[0].window.end, 18)
      assert_eq(plan.blocks[1].window.start, 20)
      assert_eq(plan.blocks[1].window.end, 28)
    }
    Err(_) => assert_true(false)
  }
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(0, 5),
        @deadlineplan.window(10, 17),
        @deadlineplan.window(20, 27),
      ],
      [],
      [@deadlineplan.splittable_task("use-earliest", 12, 27, [], 5)],
    ) {
    Ok(plan) => {
      assert_eq(plan.unscheduled.length(), 0)
      assert_eq(plan.blocks.length(), 2)
      assert_eq(plan.blocks[0].window.start, 0)
      assert_eq(plan.blocks[0].window.end, 5)
      assert_eq(plan.blocks[1].window.start, 10)
      assert_eq(plan.blocks[1].window.end, 17)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "sufficient raw capacity is not enough when every block has a minimum" {
  match
    @deadlineplan.schedule(
      [
        @deadlineplan.window(0, 5),
        @deadlineplan.window(10, 15),
        @deadlineplan.window(20, 25),
      ],
      [],
      [@deadlineplan.splittable_task("cannot-pack", 11, 25, [], 4)],
    ) {
    Ok(plan) => {
      assert_eq(plan.blocks.length(), 0)
      assert_eq(plan.unscheduled.length(), 1)
      assert_true(plan.unscheduled[0].reason is SplitWorkIncomplete(11))
    }
    Err(_) => assert_true(false)
  }
}

///|
fn exhaustive_split_exists(
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
  if exhaustive_split_exists(capacities, index + 1, remaining, minimum) {
    return true
  }
  let mut take = minimum
  while take <= capacities[index] && take <= remaining {
    if exhaustive_split_exists(capacities, index + 1, remaining - take, minimum) {
      return true
    }
    take = take + 1
  }
  false
}

///|
test "split feasibility agrees with exhaustive small-gap allocation" {
  let mut encoded = 0
  while encoded < 625 {
    let capacities : Array[Int32] = []
    let windows : Array[@deadlineplan.TimeWindow] = []
    let mut digits = encoded
    let mut index = 0
    while index < 4 {
      let capacity = digits % 5
      capacities.push(capacity)
      if capacity > 0 {
        windows.push(@deadlineplan.window(index * 10, index * 10 + capacity))
      }
      digits = digits / 5
      index = index + 1
    }
    let mut minimum = 1
    while minimum <= 4 {
      let mut duration = minimum
      while duration <= 12 {
        let expected = exhaustive_split_exists(capacities, 0, duration, minimum)
        match
          @deadlineplan.schedule(windows, [], [
            @deadlineplan.splittable_task("work", duration, 40, [], minimum),
          ]) {
          Ok(plan) => {
            let actual = plan.unscheduled.length() == 0
            assert_eq(actual, expected)
            if actual {
              let mut total = 0
              let mut block_index = 0
              while block_index < plan.blocks.length() {
                let block = plan.blocks[block_index].window
                let mut contained = false
                let mut window_index = 0
                while window_index < windows.length() {
                  if block.start >= windows[window_index].start &&
                    block.end <= windows[window_index].end {
                    contained = true
                  }
                  window_index = window_index + 1
                }
                assert_true(contained)
                assert_true(block.end - block.start >= minimum)
                if block_index > 0 {
                  assert_true(
                    plan.blocks[block_index - 1].window.end <= block.start,
                  )
                }
                total = total + block.end - block.start
                block_index = block_index + 1
              }
              assert_eq(total, duration)
            } else {
              assert_eq(plan.blocks.length(), 0)
              match plan.unscheduled[0].reason {
                SplitWorkIncomplete(remaining) => assert_eq(remaining, duration)
                _ => assert_true(false)
              }
            }
          }
          Err(_) => assert_true(false)
        }
        duration = duration + 1
      }
      minimum = minimum + 1
    }
    encoded = encoded + 1
  }
}
