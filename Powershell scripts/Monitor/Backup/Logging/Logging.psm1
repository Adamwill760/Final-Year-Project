Function Write-Log
{
  Param([string]$logstring)

  $time = get-date
  Add-content $Logfile -value "<$time> $logstring" -ErrorAction SilentlyContinue
  write-host "<$time> $logstring"
}