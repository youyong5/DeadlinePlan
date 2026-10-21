///|
/// A runnable public-API example, independent of the CLI's JSON input path.
fn main {
  let result = @plan.schedule(
    [@plan.window(0, 150)],
    [@plan.fixed_event("meeting", 30, 50)],
    [@plan.task("draft", 30, 100, []), @plan.task("review", 20, 120, ["draft"])],
  )
  match result {
    Ok(schedule) => {
      for block in schedule.blocks {
        println(
          "\{block.task_id}: [\{block.window.start}, \{block.window.end})",
        )
      }
      println("Unscheduled: \{schedule.unscheduled.length()}")
    }
    Err(_) => println("Invalid example plan")
  }
}
