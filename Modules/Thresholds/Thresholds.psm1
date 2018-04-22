Function Get-Threshold 
{
  param(
        [parameter(ParameterSetName='Freespace',
        Mandatory=$false)]
        [switch]$FreeSpace,
        [parameter(ParameterSetName='Memory',
        Mandatory=$false)]
        [switch]$Memory,
        [parameter(ParameterSetName='CPU',
        Mandatory=$false)]
        [switch]$CPU,
        [parameter(ParameterSetName='TCP',
        Mandatory=$false)]
        [switch]$TCP,
        [string]$name,
        [string]$Computername,
        [string]$ThresholdsFile,
        [string]$logfile)

  $jsondata = get-content $ThresholdsFile | convertfrom-json
  
  if($jsondata.$Computername)
  {
      if($FreeSpace) 
      {
        if($jsondata.$computername.DiskThresholds -ne $null) #check disk thresholds are defined for machine
        {
          if($jsondata.$computername.DiskThresholds.name.Contains($name)) #check requested drive is defined
          {
            $DiskThreshold = $jsondata.$computername.DiskThresholds | Where-Object -Property name -match $name
            return $DiskThreshold.value
          }
          else
          {
            Write-Log -Logfile $logfile -Logstring "No Disk threshold defined for $name on $Computername setting to default"
            return 0
          }
        }
        else
        {
            Write-Log -Logfile $logfile -Logstring "No Disk thresholds are defined on $Computername setting to default"
            return 0
        }
      }#end freespace
      elseif($Memory) 
      {
        if($jsondata.$computername.MemoryThresholds -ne $null)
        {
          if($jsondata.$computername.MemoryThresholds.name.Contains($name))
          {
            $MemoryThreshold = $jsondata.$computername.MemoryThresholds | Where-Object -Property name -match $name
            return $MemoryThreshold.value
          }
          else
          {
            Write-Log -Logfile $logfile -Logstring "No Memory threshold defined for $name on $Computername setting to default"
            return 0
          }
        }
        else
        {
          Write-Log -Logfile $logfile -Logstring "No Memory threshold defined for $name on $Computername setting to default"
          return 0
        }
      }#end memory
      elseif($CPU)
      {
        if($jsondata.$computername.CPUThresholds -ne $null)
        {
          if($jsondata.$computername.CPUThresholds.name.Contains($name))
          {
            $CPUThreshold = $jsondata.$computername.CPUThresholds | Where-Object -Property name -match $name
            return $CPUThreshold.value
          }
          else
          {
            Write-Log -Logfile $logfile -Logstring "No CPU threshold defined for $name on $Computername setting to default"
            return 101
          }
        }
        else
        {
          Write-Log -Logfile $logfile -Logstring "No CPU thresholds defined on $Computername setting to default"
          return 101
        }
      }#end cpu
      elseif($TCP)
      {
        if($jsondata.$computername.TCPThresholds -ne $null)
        {
          if($jsondata.$computername.TCPThresholds.name.Contains($name))
          {
            $TCPThreshold = $jsondata.$computername.TCPThresholds | Where-Object -Property name -match $name
            return $TCPThreshold.value
          }
          else
          {
            Write-Log -Logfile $logfile -Logstring "No TCP threshold defined for $name on $Computername setting to default"
            return 1000000
          }
        }
        else
        {
          Write-Log -Logfile $logfile -Logstring "No TCP thresholds defined on $Computername setting to default"
          return 1000000
        }
    }#end tcp
  }
  else
  {
    Write-Log -Logfile $logfile -Logstring "$Computername has not been defined in the thresholds JSON - ALL THRESHOLDS SET TO DEFAULT"
    if($FreeSpace -or $Memory)
    {
      return 0
    }
    elseif($CPU)
    {
      return 101
    }
    elseif($TCP)
    {
      return 100000
    }
  }
}