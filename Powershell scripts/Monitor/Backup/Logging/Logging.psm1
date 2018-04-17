Function Write-Log
{
  Param([string]$Logstring,
        [string]$Logfile)

  $time = get-date
  Add-content $Logfile -value "<$time> $Logstring" -ErrorAction SilentlyContinue
  write-host "<$time> $Logstring"
}