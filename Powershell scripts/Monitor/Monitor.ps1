#Define database IP address
$DbIP = '192.168.56.101'

#Define the location to write the log file
$Logfile = "D:\University work\Third Year\Final Year Project\Product\$(gc env:computername).log"

#Location of the JSON rule files
$ThresholdsFile = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\Threshold.json"
$LogRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\LogDirs.json"
$ProcessesRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\ProcessRules.json"

#Action taken boolean declaration
$DdriveActionTaken = $false
$CdriveActionTaken = $false
$MemoryActionTaken = $false
$CPUActionTaken = $false
$TCPActionTaken = $false

Function Write-Log
{
  Param([string]$logstring)

  $time = get-date
  Add-content $Logfile -value "<$time> $logstring"
  write-host "<$time> $logstring"
}

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
        [string]$name)

  $jsondata = get-content $ThresholdsFile | convertfrom-json

  if($FreeSpace) 
    {
      if($jsondata.DiskThresholds.name.Contains($name))
      {
        $DiskThreshold = $jsondata.DiskThresholds | Where-Object -Property name -match $name
        return $DiskThreshold.value
      }
      else
      {
        Write-Log "No Disk threshold defined for $name"
      }
    }
    elseif($Memory) 
    {
      if($jsondata.MemoryThresholds.name.Contains($name))
      {
        $MemoryThreshold = $jsondata.MemoryThresholds | Where-Object -Property name -match $name
        return $MemoryThreshold.value
      }
      else
      {
        Write-Log "No Memory threshold defined for $name"
      }
    }
    elseif($CPU)
    {
      if($jsondata.CPUThresholds.name.Contains($name))
      {
        $CPUThreshold = $jsondata.CPUThresholds | Where-Object -Property name -match $name
        return $CPUThreshold.value
      }
      else
      {
        Write-Log "No CPU threshold defined for $name"
      }
    }
    elseif($TCP)
    {
      if($jsondata.TCPThresholds.name.Contains($name))
      {
        $TCPThreshold = $jsondata.TCPThresholds | Where-Object -Property name -match $name
        return $TCPThreshold.value
      }
      else
      {
        Write-Log "No TCP threshold defined for $name"
      }
    }
}

Function Query-Database #return relative database entry as PSobject
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
        [string]$SELECT,
        [string]$WHERE
        )
  
  if($FreeSpace)
  {
    #Set table to query
    $FROM = "win_disk"
  }
  elseif($Memory)
  {
    $FROM = "win_mem"
  }
  elseif($CPU)
  {
    $FROM = "win_cpu"
  }
  elseif($TCP)
  {
    $FROM = "win_tcp"
  }

  #Check for where clause
  if($WHERE)
  {
    $DBquery = "SELECT $SELECT FROM $FROM WHERE $WHERE"
  }
  else
  {
    $DBquery = "SELECT $SELECT FROM $FROM"
  }

  #Create API request
  $request = "http://$DbIP`:8086/query?&db=telegraf&q=$DBquery"
  
  #query for response
  $response = Invoke-RestMethod -Uri $request -Method Get
  
  #select results array
  $result = $response.results.series.values

 if($FreeSpace)
 {
   #create custom drive object
   $Drive = New-Object PSObject -Property @{
     Time = $result[0][0]
     Value = $result[0][1]
     Instance = $result[0][2]
     }
     
     return $Drive
 }
 elseif($Memory)
 { 
  #create custom memory object 
  $MemoryObject = New-Object PSobject -Property @{
              Time = $result[0][0] 
              Kb =  [int](($result[0][1])/1KB)
              Mb = [int](($result[0][1])/1MB)
              Gb = "{0:n2}" -f (($result[0][1])/1GB)}

 return $MemoryObject
 }
 elseif($CPU)
 {
   #create custom CPU object 
   $CPUObject = New-Object PSobject -Property @{
               Time = $result[0][0] 
               ProcessorTime = $result[0][1]}
   
   return $CPUObject
 }
 elseif($TCP)
 {
   #create custom CPU object 
   $TCPObject = New-Object PSobject -Property @{
               Time = $result[0][0] 
               ConnectionsEstablished = $result[0][1]
               ConnectionsActive = $result[0][2]
               ConnectionsPassive= $result[0][3]
               }
   
   return $TCPObject
 }
}

Function Clear-Drive
{
  Param ([String]$RootDirectory,
         [String]$JsonLocation)

  Write-Log "##### BEGINNING DRIVE CLEAR #####"

  #load file retention rules from json
  $jsonrules = get-content $JsonLocation | ConvertFrom-Json

  #initialise empty directory array
  $directoryarray = @()

  #gather list of directories on the drive
  $directorylist = Get-ChildItem $RootDirectory -Recurse | Where-Object{($_.PSIsContainer)}

  #if directory empty action should exit
  if($directorylist.Length -eq 0)
  {
    Write-Log "no directories contained in root directory please check assosiated threshold"
  }
  else
  {
    #foreach directory create new object (Name,Path,Total size) and append to array
    foreach($directory in $directorylist)
    {
      #must be directory full name to correctly access child directories
      $directorysize = Get-ChildItem $directory.FullName -Recurse | Measure-Object -Sum Length

      #create directory object containing the properties we need for custom array
      $directoryobject = New-Object PSObject -Property @{
                          Name = $directory.Name
                          Path = $directory.FullName
                          Size = $directorysize.sum
                          }
      #append to array
      $directoryarray += $directoryobject
    }

    #for each rule in json file
    foreach($jsonrule in $jsonrules.LogDirectories)
    {
      #Check if the directory array contains a directory assosiated with the rule
      if($directoryarray.path.Contains($jsonrule.location))
      {
          Write-Log "$($jsonrule.name) json rule found in root directory"

          #select the individual directory relating to the rule in the json file
          $directorytobecleared = $directoryarray | Where-Object -Property path -EQ $jsonrule.location

          #if the directory actual size exceeds json expected size check which files are over retention
          if($directorytobecleared.size -gt $jsonrule.expectedsize)
          {
            Write-Log "Actual size of $($directorytobecleared.Name) exceeds expected size"

            #initialize clearing array
            $clearedarray = @()

            #current/saved space metric definition
            $currentsize = $directorytobecleared.size
            $spacesaved = 0

            #calculate date/time span from retention
            $currentdate = Get-Date
            $timespan = New-TimeSpan -Days $jsonrule.retention

            #gather list of all items in directory
            $filestobecleared = get-childitem $directorytobecleared.Path -recurse

            #foreach file in violating directory
            foreach($filetobecleared in $filestobecleared)
            {
              #check if each file in directory exceeds json retention policy
              if($filetobecleared.LastWriteTime -lt ($currentdate.Subtract($timespan)))
              {
                ##ACTION FILE CLEAR##
                Remove-Item $filetobecleared.FullName -Force

                if(Test-Path $filetobecleared.FullName)
                {
                  #file still exsists
                  Write-Log "$filetobecleared Could not be removed"
                }
                else
                {
                  #file successfully removed append file to clearing array
                  $clearedarray += $filetobecleared.Name
                  $spacesaved = $spacesaved + $filetobecleared.length
                }
              }
            }

            if($clearedarray -ne 0)
            {
              #list files to be removed
              Write-Log "The following files exceeding retention of $($directorytobecleared.name) have been removed"
              $clearedarray | fl
              $spacesaved = $spacesaved/1000
              Write-Log "$spacesaved Kb recovered"
            }
            else
            {
              Write-Log "No files exceed the retention policy of $($directorytobecleared.Name)"
            }
          }
          else
          {
            Write-Log "$($directorytobecleared.name) does not exceed its expected size, no action taken"
          }

      }
      #no matching directory for json rule
      else
      {
        Write-Log "$($jsonrule.name) retention rule does not match any directory"
      }
    }
  }

  Write-Log "##### END OF DRIVE CLEAR ####"
}

Function Clear-Unresponsive
{
  param([parameter(parametersetname="Memory",
         Mandatory=$true)]
        [switch]$Memory,
        [parameter(parametersetname="CPU",
        Mandatory=$true)]
        [switch]$CPU,
        [array]$Processlist
        )
  
  Write-Log "##### BEGINNING UNRESPONSIVE TERMINATION #####"

  if($Memory)
  {
    $resource = "ws"
  }
  elseif($CPU)
  {
    $resource = "cpu"
  }

  #initialise empty clearing arrays
  $UnresponsiveKilledList = @()
  $UnresponsiveAliveList = @()
  
  #check each process responsive
  foreach($Process in $ProcessList)
  {
    #Check whether the process is responsive / close any that arent
    if($Process.responding -eq $false)
    {
     
     if($Memory)
     {
       Write-Log "$($Process.Name) Not responding, currently $($Process.$resource/1MB) MB  allocated to this "
     }

     if($CPU)
     {
       Write-Log "$($Process.Name) Not responding, currently $($Process.$resource) CPU allocated to this "
     }
     
     if(Stop-Process $Process -force -PassThru)
     {
       $UnresponsiveKilledList += $Process
     }
     else
     {
       $UnresponsiveAliveList += $Process
     }
    }
  }

  $ResourceRecovered = ($UnresponsiveKilledList | Measure-Object -Sum -Property $resource).sum
  
  if($UnresponsiveKilledList.count -ne 0)
  {
   Write-Log "$($UnresponsiveKilledList.name) have been terminated"
  }
  
  if($UnresponsiveAliveList.Count -ne 0)
  {
   Write-Log "$($UnresponsiveAliveList.name) could not be terminated"
 }
  
  if($UnresponsiveKilledList.Count -eq 0 -and $UnresponsiveAliveList.count -eq 0)
  {
   Write-Log "No processes were found unresponsive"
  }
  
  if($ResourceRecovered -ne $null -and $Memory)
  {
   Write-Log "$($ResourceRecovered/1MB) MB from unresponsive processes"
  }
  elseif($ResourceRecovered -ne $null -and $CPU)
  {
   Write-Log "$ResourceRecovered from unresponsive processes"
  }
  
  Write-Log "##### END OF UNRESPONSIVE TERMINATION #####"

  return $ResourceRecovered
}

Function Clear-Resource
{

 param([parameter(parametersetname="Memory", Mandatory=$true)]
       [switch]$Memory,
       [parameter(parametersetname="CPU", Mandatory=$true)]
       [switch]$CPU 
       )

 Write-Log "##### BEGINNING RESOURCE CLEARANCE #####"

 if($Memory)
 {
   $resource = "ws"
   $threshold = "MemoryThreshold"
   $measurement = "MB"
 }
 elseif($CPU)
 {
   $resource = "CPU"
   $threshold = "CPUThreshold"
   $measurement = "CPU"
 }

 $ProcessRules = Get-Content $ProcessesRulesJson | ConvertFrom-Json

 $ProcessList = get-process

 if($Memory)
 {
   $ResourceRecovered = Clear-Unresponsive -Processlist $ProcessList -Memory
 }
 elseif($CPU)
 {
   $ResourceRecovered = Clear-Unresponsive -Processlist $ProcessList -CPU
 }

 foreach($ProcessRule in $ProcessRules.Processes)
 {
   #If running process list contains any process rules
   if($ProcessList.name.Contains($ProcessRule.name))
   {
     Write-Log "$($ProcessRule.name) rule has a running process"

     #Select related process to rule
     $ComparingProcess = $ProcessList | Where-Object -Property name -Match $ProcessRule.name

     #check threshold exceeded and terminatable
     if($ComparingProcess.$resource -gt $ProcessRule.$threshold -and $ProcessRule.terminatable -eq "true")
     {
       Write-Log "$($ComparingProcess.name) $measurement exceeds expected and can be terminated"

       if(Stop-Process $ComparingProcess -force -PassThru)
       {
         Write-Log "$($ComparingProcess.name) terminated"
         $ResourceRecovered = $ResourceRecovered + $ComparingProcess.$resource
       }
       else
       {
         Write-Log "$($ComparingProcess.name) could not be terminated"
       }
     }
     elseif($ComparingProcess.$resource -gt $ProcessRule.$threshold -and $ProcessRule.terminatable -eq "false")
     {
      Write-Log "$($ComparingProcess.Name) $measurement exceeds expected size but can not be automatically terminated"
     }
     elseif($ComparingProcess.$resource -lt $ProcessRule.$threshold)
     {
       Write-Log "$($ComparingProcess.Name) $measurement is less than threshold"
     }
   }
   else
   {
    Write-Log "No $($ProcessRule.name) process running"
   }
 }

 if($Memory)
 {
   Write-Log "$($ResourceRecovered/1MB) total $measurement recovered"
 }
 elseif($CPU)
 {
   Write-Log "$([int]$ResourceRecovered) total $measurement recovered"
 }

 Write-Log "##### END OF RESOURCE CLEARANCE #####"

}

Function Clear-TCPConnections
{
  #Get connections

  #check all attached to running process

  #Group by remote address

  #more than normal highlight

  #check creation time 

  #older than X add to alert list

  #produce final report
}

#Check connection to DB is live 
if (Test-Connection $DbIP)
{
  Write-Log "CONNECTION TO $DbIP ESTABLISHED"

  #### GATHER ALERT THRESHOLDS ####
  Write-Log "##### GATHERING ALERT THRESHOLDS #####"

  $CThreshold = Get-Threshold -FreeSpace -name "C"
  Write-Log "C Threshold has been set to $CThreshold %"

  $DThreshold = Get-Threshold -FreeSpace -name "D"
  Write-Log "D Threshold has been set to $DThreshold %"

  $MemoryThreshold = Get-Threshold -Memory -name "Avaliable Bytes"
  Write-Log "Memory Threshold set to $MemoryThreshold MB"

  $CPUThreshold = Get-Threshold -CPU -name "Processor Time"
  Write-Log "CPU Threshold set to $CPUThreshold"

  $TCPThreshold = Get-Threshold -TCP -name "Connections Established"
  Write-Log "TCP Threshold set to $TCPThreshold"

  Write-Log "##### ALERT THRESHOLDS SET #####"

  #### BEGINNING OF MAIN LOOP - FUNCTIONS LOADED - THRESHOLD CHECKS CARRIED OUT HERE ####
  
  While($true)
  {
    ##### QUERYING DATABASE
    Write-Log "##### RUNNING DATABASE QUERIES #####"

    #Initialize database entry point objects
    $CDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'C:'"


    $DDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:'"


    $MemoryUsage = Query-Database -Memory -SELECT "LAST(`"Available Bytes`")"


    $CPUusage = Query-Database -CPU -SELECT "LAST(`"% Processor Time`")"


    $TCPconnections = Query-Database -TCP -SELECT "LAST(`"Connections Established`"), `"Connections Active`", `"Connections Passive`""


    Write-Log "##### DATABASE QUERIES RAN #####"

    ##### ASSESSING THRESHOLDS
    Write-Log "##### ASSESSING THRESHOLDS #####"

    #Check C against threshold values
    Write-Log "Assessing drive C..."
    if($CDrive.Value -lt $CThreshold)
    {
      Write-Log "C: Threshold exceeded at $($CDrive.Value)"
      if($CdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
      {
        Clear-drive -RootDirectory $CDrive.Instance -JsonLocation $LogRulesJson
        $CdriveActionTaken = $true
      }
      else #if action already taken print to log
      {
        Write-Log "Action already taken no more space can be cleared"
      }
    }
    else
    {
      Write-Log "C: Under Threshold"
      if($CdriveActionTaken -eq $true) #once under threshold again reset automated action to false
      {
        $CdriveActionTaken = $false
        Write-Log "C drive action taken set to false"
      }
    }

    #Check D against threshold
    Write-Log "Assessing drive D..."
    if($DDrive.Value -lt $DThreshold)
    {
      Write-Log "D: Threshold exceeded at $($DDrive.Value)"
      if($DdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
      {
        Clear-Drive -RootDirectory $DDrive.Instance -JsonLocation $LogRulesJson
        $DdriveActionTaken = $true
      }
      else #if action already taken print to log
      {
        Write-Log "Action already taken no more space can be cleared"
      }
    }
    else
    {
      Write-Log "D: Under Threshold"
      if($DdriveActionTaken -eq $true) #once under threshold again reset automated action to false
      {
        $DdriveActionTaken = $false
        Write-Log "D drive action taken set to false"
      }
    }

    #Check Memory against threshold values
    Write-Log "Assessing Memory usage..."
    if($MemoryUsage.Mb -lt $MemoryThreshold)
    {
      Write-Log "Avaliable bytes under threshold at $($MemoryUsage.Mb) MB"
      if($MemoryActionTaken -eq $false)
      {
        Clear-Resource -Memory
        $MemoryActionTaken = $true
      }
      else
      {
        Write-Log "Action already taken no more memory can be cleared"
      }
    }
    else
    {
     Write-Log "Memory usage under threshold"
     if($MemoryActionTaken -eq $true)
     {
       $MemoryActionTaken = $false
       Write-Log "Memory action taken reset to false"
     }
    }

    #Check CPU against threshold
    Write-Log "Assessing CPU usage..."
    if($CPUusage.ProcessorTime -gt $CPUThreshold)
    {
      Write-Log "CPU usage over threshold at $($CPUusage.ProcessorTime)"
      if($CPUActionTaken -eq $false)
      {
        Clear-Resource -CPU
        $CPUActionTaken = $true
      }
      else
      {
        Write-Log "Action already taken no more CPU can be cleared"
      }
    }
    else
    {
      Write-Log "CPU usage under threshold"
      if($CPUActionTaken -eq $true)
      {
        $CPUActionTaken = $false
      }
    }

    #Check TCP connection threshold
    Write-Log "Assessing TCP connection "
    if($TCPconnections.ConnectionsEstablished -gt $TCPThreshold)
    {

    }
    else
    {
      Write-Log "TCP connections established under threshold"
    }

    ##### LOOP COMPLETE SLEEPING 30 UNTIL NEXT LOOP
    Write-Log "##### THRESHOLDS ASSESSED SLEEPING UNTIL NEXT LOOP #####"
    start-sleep 30
  }
}
else
{
  Write-Log "Database not reachable please resolve connectivity issues"
}
