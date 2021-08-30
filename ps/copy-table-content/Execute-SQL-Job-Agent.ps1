# Determine current script location
$CurrentDir = $PSScriptRoot
$config_file = 'config.yml'

# ============== MAIN BLOCK ==========================
# Set-Config-Vars
# Read yAML config file
$cf = "$CurrentDir\$config_file"

# Write-Host "config file is $cf"
$config_conent = Get-Content $cf 
$content = ''


FOREACH ($line in $config_conent) {$content = $content + "`n" + $line }

# Let us assign yaml value into variables
$yaml = ConvertFrom-Yaml $content
$ServerName = $yaml.job_agent_server_name
$JobName    = $yaml.job_name
$StepName   = $yaml.step_name

$date = Get-Date

Write-Host "============================================================================================= "
Write-Host "Starting SQL Agent Job $($JobName) on Server $($ServerName)"
Write-Host "It is now: $($date)"

# Load SqlServer libraries
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$srv  = New-Object Microsoft.SqlServer.Management.SMO.Server("$ServerName")
$job  = $srv.jobserver.jobs["$JobName"] 
# $step = $job.JobSteps["$StepName"]

$jobstart = $false
if (($job))
{	
   $job.Start()
   $jobstart = $true
   Start-Sleep -s 5  # Pause for 5 seconds (optional) - was 30 seconds (v1); v2=5
}
else { 
    $jobstart="Not found"   
} # Check if $job exists in target SQL server 

# Lets kick-off the SQL Job Agent if found
if ($jobstart) { 
   
    Write-Host "Job $($JobName) on Server $($ServerName) started"
   
    # ---- start of DO WHILE loop 
    # Loop through Task Steps if any found
    $i = 0
    do { 
        $job.Refresh();   
        $iRem = $i % 5;
        $job_status  = $job.CurrentRunStatus.ToString();
        if ($iRem -eq 0) {
            $date = Get-Date
            Write-Host "Job $($JobName) Processing -- Run Step:$($job.CurrentRunStep) Status:$($job_status)... at $($date)"
        } 
        Start-Sleep -s 5;	# Pause for 5 seconds  - was 60 seconds, taking to long and hangs sometimes. 
        $i++;
    } while ($job_status -ne "Idle") 
    # ---- end of DO WHILE loop 

    if ($job.LastRunOutcome -ne "Cancelled") { 
       Write-Host "Job Processing done"    
    }
    else { 
       Write-Host "Job Processing cancelled/aborted" 
    }

    $job_last_run_dt = $job.LastRunDate
    $job_status = $job.LastRunOutcome
    $job_history = $job.EnumHistory()
    
    Write-Host "$($srv.name) $($job.name)"
    Write-Host "Last job outcome status: $($job_status)"
    Write-Host "Last job outcome date:   $($job_last_run_dt)"
    
    if ( $null -ne $job_history.Rows[0]){
        Write-Host "SQL Job Agent Message: $($job.EnumHistory().Rows[0].Message)"
    }
    if ( $null -ne $job.EnumHistory().Rows[1] ){
        Write-Host "SQL Job Agent Message 2: $($job.EnumHistory().Rows[1].Message)"
    }
    
    $job_step_count = $job.JobSteps.Count - 1
    for ($i=0; $i -le $job_step_count; $i++) {

        $steps_name = $job.JobSteps[$i].Name
        $steps_last_run_dt = $job.JobSteps[$i].LastRunDate
        $steps_status = $job.JobSteps[$i].LastRunOutCome
        
        Write-Host "Name: $($steps_name) RunDate: $($steps_last_run_dt) Status: $($steps_status)"
        
        if ($job_last_run_dt -gt $steps_last_run_dt) {
            $msg ="FailedOrAborted"
        }
    }
  if ($msg -eq "Failed"){
      Write-Host "Job returned with Failed status"
	  exit 2
    }
  if ($msg -ne "FailedOrAborted") {
	if ($msg -ne "Cancelled") { exit 0 }
	else {
	  Write-Host "Job Cancelle..."
	  exit 3
	 }
	}
  else {
	 Write-Host "Job Failed or Aborted"
	 exit 2
	}
  } # JobStart is $true
  else  {
    Write-Host "Unable to Start Job $($JobName) on Server $($ServerName)"
    Write-Host "Reason: Job may not exist or not enabled."
    exit 1
  } 