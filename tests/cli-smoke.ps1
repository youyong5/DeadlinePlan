Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$moonExecutable = (Get-Command moon).Source

function Invoke-PlanCli {
  param([string[]] $CliArgs)
  $start = New-Object System.Diagnostics.ProcessStartInfo
  $start.FileName = $moonExecutable
  $start.Arguments = 'run --target js cmd/deadlineplan -- ' + (($CliArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
  $start.WorkingDirectory = $projectRoot
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::Start($start)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  [PSCustomObject]@{ Code = $process.ExitCode; Out = $stdout; Err = $stderr }
}

function Assert-Check {
  param([bool] $Condition, [string] $Message)
  if (-not $Condition) { throw $Message }
}

$helpResult = Invoke-PlanCli -CliArgs @('--help')
Assert-Check ($helpResult.Code -eq 0 -and $helpResult.Out.Contains('Usage:') -and $helpResult.Err -eq '') 'help must succeed on stdout'
Write-Output 'PASS --help (exit 0)'

$student = Invoke-PlanCli -CliArgs @('examples/student-plan.v1.json')
Assert-Check ($student.Code -eq 0 -and $student.Err -eq '') 'student plan must succeed quietly'
Assert-Check ($student.Out.Contains('Scheduled blocks (5)') -and $student.Out.Contains('confirmed biology-review') -and $student.Out.Contains('2026-10-21T07:30Z')) 'student text output must show dated chronological blocks'
Write-Output 'PASS student text (exit 0)'

$project = Invoke-PlanCli -CliArgs @('examples/project-plan.v1.json')
Assert-Check ($project.Code -eq 0 -and $project.Err -eq '') 'project plan must succeed quietly'
Assert-Check ($project.Out.Contains('Scheduled blocks (3)') -and $project.Out.Contains('confirmed design') -and $project.Out.Contains('planned release')) 'project text output must identify confirmed and planned blocks'
Write-Output 'PASS project text (exit 0)'

$machine = Invoke-PlanCli -CliArgs @('--json', 'examples/student-plan.v1.json')
Assert-Check ($machine.Code -eq 0 -and $machine.Err -eq '') 'JSON mode must succeed quietly'
$data = $machine.Out | ConvertFrom-Json
Assert-Check ($data.result_version -eq 1 -and $data.blocks.Count -eq 5 -and $data.unscheduled.Count -eq 0) 'JSON output must be parseable and complete'
Assert-Check ($data.blocks[0].confirmed -and $data.blocks[0].start -eq 29875680 -and $data.blocks[1].task_id -eq 'calculus-homework') 'JSON output must keep sorted blocks and confirmation status'
$machineAgain = Invoke-PlanCli -CliArgs @('--json', 'examples/student-plan.v1.json')
Assert-Check ($machineAgain.Code -eq 0 -and $machineAgain.Out -eq $machine.Out) 'JSON output must be byte-for-byte stable for identical input'
Write-Output 'PASS --json parse and order (exit 0)'

$invalid = Invoke-PlanCli -CliArgs @('tests/fixtures/invalid.json')
Assert-Check ($invalid.Code -eq 1 -and $invalid.Out -eq '' -and $invalid.Err.Contains('JSON syntax error')) 'invalid JSON must fail on stderr'
Write-Output 'PASS invalid JSON (exit 1)'

$version = Invoke-PlanCli -CliArgs @('tests/fixtures/unknown-version.json')
Assert-Check ($version.Code -eq 1 -and $version.Out -eq '' -and $version.Err.Contains('unsupported schema_version: 2')) 'unknown version must fail on stderr'
Write-Output 'PASS unknown schema version (exit 1)'

$badPlan = Invoke-PlanCli -CliArgs @('tests/fixtures/invalid-plan.json')
Assert-Check ($badPlan.Code -eq 1 -and $badPlan.Out -eq '' -and $badPlan.Err.Contains('/tasks/0/dependencies/0') -and $badPlan.Err.Contains('unknown dependency')) 'scheduler input validation must fail with its field path on stderr'
Write-Output 'PASS invalid plan input (exit 1)'

$missing = Invoke-PlanCli -CliArgs @('tests/fixtures/no-such-file.json')
Assert-Check ($missing.Code -eq 1 -and $missing.Out -eq '' -and $missing.Err.Contains('cannot read plan file')) 'missing file must fail on stderr'
Write-Output 'PASS missing file (exit 1)'

$arguments = Invoke-PlanCli -CliArgs @('--surprise')
Assert-Check ($arguments.Code -eq 2 -and $arguments.Out -eq '' -and $arguments.Err.Contains('Usage:')) 'unknown arguments must fail with usage on stderr'
Write-Output 'PASS unknown argument (exit 2)'

$unscheduled = Invoke-PlanCli -CliArgs @('tests/fixtures/unscheduled.json')
Assert-Check ($unscheduled.Code -eq 0 -and $unscheduled.Out.Contains('no continuous slot') -and $unscheduled.Out.Contains('dependency not scheduled: too-long') -and $unscheduled.Out.Contains('cannot allocate all 8 unconfirmed work minutes')) 'unscheduled work is a successful plan with concrete reasons'
$unscheduledJson = Invoke-PlanCli -CliArgs @('--json', 'tests/fixtures/unscheduled.json')
$unscheduledData = $unscheduledJson.Out | ConvertFrom-Json
Assert-Check ($unscheduledJson.Code -eq 0 -and $unscheduledData.unscheduled.Count -eq 3) 'unscheduled JSON must also be valid and successful'
Assert-Check (($unscheduledData.unscheduled.reason.code -contains 'no_continuous_slot') -and ($unscheduledData.unscheduled.reason.code -contains 'dependency_not_scheduled') -and ($unscheduledData.unscheduled.reason.code -contains 'split_work_incomplete')) 'unscheduled JSON must carry each concrete reason code'
Assert-Check (($unscheduledData.unscheduled | Where-Object { $_.task_id -eq 'split' }).reason.remaining_minutes -eq 8) 'split failure must preserve its precise remaining-minute field'
Write-Output 'PASS unscheduled text and JSON (exit 0)'

$extreme = Invoke-PlanCli -CliArgs @('tests/fixtures/extreme.json')
Assert-Check ($extreme.Code -eq 0 -and $extreme.Out.Contains('minute -2147483648')) 'extreme minute must fall back safely'
Write-Output 'PASS extreme-minute fallback (exit 0)'
