///|
#module("node:fs")
extern "js" fn read_example(path : String, encoding : String) -> String = "readFileSync"

///|
test "student JSON file schedules completed and partly confirmed work" {
  let source = read_example("examples/student-plan.v1.json", "utf8")
  match @deadlineplan.parse_plan_json(source) {
    Ok(document) => {
      match @deadlineplan.serialize_plan_json(document) {
        Ok(encoded) =>
          match @deadlineplan.parse_plan_json(encoded) {
            Ok(again) => {
              assert_eq(again.tasks[0].id, "topic-announced")
              assert_eq(again.tasks[1].id, "calculus-homework")
              assert_eq(again.tasks[1].earliest_start, Some(29875830))
              assert_eq(again.tasks[2].id, "biology-review")
              assert_eq(again.tasks[2].minimum_block_minutes, Some(60))
              assert_eq(again.completed[0].completed_at, 29875680)
              assert_eq(again.confirmed_blocks[0].window.end, 29875740)
            }
            Err(_) => assert_true(false)
          }
        Err(_) => assert_true(false)
      }
      match
        @deadlineplan.schedule_with_confirmed_blocks(
          document.availability,
          document.fixed_events,
          document.tasks,
          document.completed,
          document.confirmed_blocks,
        ) {
        Ok(plan) => {
          assert_eq(plan.blocks.length(), 5)
          assert_eq(plan.blocks[0].task_id, "biology-review")
          assert_eq(plan.blocks[0].window.start, 29875680)
          assert_eq(plan.blocks[0].window.end, 29875740)
          assert_eq(plan.blocks[1].task_id, "calculus-homework")
          assert_eq(plan.blocks[1].window.start, 29875830)
          assert_eq(plan.blocks[1].window.end, 29875890)
          assert_eq(plan.blocks[2].window.start, 29875890)
          assert_eq(plan.blocks[2].window.end, 29875980)
          assert_eq(plan.blocks[3].window.start, 29876070)
          assert_eq(plan.blocks[3].window.end, 29876130)
          assert_eq(plan.blocks[4].task_id, "exam-setup")
          assert_eq(plan.blocks[4].window.start, 29876130)
          assert_eq(plan.blocks[4].window.end, 29876160)
          assert_eq(plan.unscheduled.length(), 0)
        }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "project JSON file schedules completed approval and partly confirmed design" {
  let source = read_example("examples/project-plan.v1.json", "utf8")
  match @deadlineplan.parse_plan_json(source) {
    Ok(document) => {
      match @deadlineplan.serialize_plan_json(document) {
        Ok(encoded) =>
          match @deadlineplan.parse_plan_json(encoded) {
            Ok(again) => {
              assert_eq(again.fixed_events[0].id, "vendor-call")
              assert_eq(again.fixed_events[0].window.start, 29877150)
              assert_eq(again.tasks[0].id, "design")
              assert_eq(again.tasks[0].minimum_block_minutes, Some(20))
              assert_eq(again.tasks[2].dependencies[1], "approval")
              assert_eq(again.completed[0].completed_at, 29877220)
              assert_eq(again.confirmed_blocks[0].window.end, 29877150)
            }
            Err(_) => assert_true(false)
          }
        Err(_) => assert_true(false)
      }
      match
        @deadlineplan.schedule_with_confirmed_blocks(
          document.availability,
          document.fixed_events,
          document.tasks,
          document.completed,
          document.confirmed_blocks,
        ) {
        Ok(plan) => {
          assert_eq(plan.blocks.length(), 3)
          assert_eq(plan.blocks[0].task_id, "design")
          assert_eq(plan.blocks[0].window.start, 29877120)
          assert_eq(plan.blocks[0].window.end, 29877150)
          assert_eq(plan.blocks[1].task_id, "design")
          assert_eq(plan.blocks[1].window.start, 29877170)
          assert_eq(plan.blocks[1].window.end, 29877210)
          assert_eq(plan.blocks[2].task_id, "release")
          assert_eq(plan.blocks[2].window.start, 29877220)
          assert_eq(plan.blocks[2].window.end, 29877230)
          assert_eq(plan.unscheduled.length(), 0)
        }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}
