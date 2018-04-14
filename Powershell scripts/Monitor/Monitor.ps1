#Define database IP address
$DbIP = '192.168.56.101'

#Define the location to write the log file
$Logfile = "D:\University work\Third Year\Final Year Project\Product\$(gc env:computername).log"

#Location of the JSON rule files
$ThresholdsFile = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\Threshold.json"
$LogRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\LogDirs.json"
$ProcessesRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\ProcessRules.json"

Function Write-Log
{
  Param([string]$logstring)

  $time = get-date
  Add-content $Logfile -value "<$time> $logstring" -ErrorAction SilentlyContinue
  write-host "<$time> $logstring"
}

class InfluxHost
{
  [string]$Hostname
  [bool]$DdriveActionTaken
  [bool]$CdriveActionTaken
  [bool]$MemoryActionTaken
  [bool]$CPUActionTaken
  [bool]$TCPActionTaken
  [int]$CThreshold
  [int]$DThreshold
  [int]$CPUThreshold
  [int]$MemoryThreshold
  [int]$TCPThreshold
}

Function Get-Hostnames
{
  $hostarray = @()
  
  $DBquery = "SHOW TAG VALUES FROM win_cpu WITH KEY=`"host`""

  #Create API request
  $request = "http://$DbIP`:8086/query?&db=telegraf&q=$DBquery"
  
  #query for response
  $response = Invoke-RestMethod -Uri $request -Method Get
  
  #select results array
  $results = $response.results.series.values

  $trimmedarray = @()

  foreach($result in $results)
  {
    $trimmedarray += $result[1]
  }

  foreach($trimmedname in $trimmedarray)
  { 
    $influxhost = New-Object InfluxHost
    $influxhost.hostname = $trimmedname
    $hostarray += $influxhost
  }
  
  return $hostarray
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
        [string]$name,
        [string]$Computername)

  $jsondata = get-content $ThresholdsFile | convertfrom-json

  if($jsondata.$Computername)
  {
    if($FreeSpace) 
      {
        if($jsondata.$computername.DiskThresholds.name.Contains($name))
        {
          $DiskThreshold = $jsondata.$computername.DiskThresholds | Where-Object -Property name -match $name
          return $DiskThreshold.value
        }
        else
        {
          Write-Log "No Disk threshold defined for $name on $Computername setting to default"
          return 100
        }
      }
      elseif($Memory) 
      {
        if($jsondata.$computername.MemoryThresholds.name.Contains($name))
        {
          $MemoryThreshold = $jsondata.$computername.MemoryThresholds | Where-Object -Property name -match $name
          return $MemoryThreshold.value
        }
        else
        {
          Write-Log "No Memory threshold defined for $name on $Computername setting to default"
          return 100000
        }
      }
      elseif($CPU)
      {
        if($jsondata.$computername.CPUThresholds.name.Contains($name))
        {
          $CPUThreshold = $jsondata.$computername.CPUThresholds | Where-Object -Property name -match $name
          return $CPUThreshold.value
        }
        else
        {
          Write-Log "No CPU threshold defined for $name on $Computername setting to default"
          return 101
        }
      }
      elseif($TCP)
      {
        if($jsondata.$computername.TCPThresholds.name.Contains($name))
        {
          $TCPThreshold = $jsondata.$computername.TCPThresholds | Where-Object -Property name -match $name
          return $TCPThreshold.value
        }
        else
        {
          Write-Log "No TCP threshold defined for $name on $Computername setting to default"
          return 1000000
        }
      }
  }
  else
  {
    Write-Log "$computername not defined in thresholds JSON"
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
  Param ([String]$RootDirectory)

  Write-Log "##### BEGINNING DRIVE CLEAR #####"

  #load file retention rules from json
  $jsonrules = get-content $LogRulesJson | ConvertFrom-Json

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
  write-log "##### BEGINNING TCP CONNECTION TROUBLESHOOT #####"
  
  $Connections = Get-NetTCPConnection -State Established

  $ownedconnections = @()
  $unowndedconnections = @()

  $oldconnections = @()

  $externalconnections = @()
  $internalconnections = @()

  #Ensure every connection has attached responding owning process
  foreach($Connection in $Connections)
  {
    $owningprocess = $Connection.OwningProcess
    if(get-process -ID $owningprocess)
    {
      if((get-process -ID $owningprocess).Responding -eq $true)
      {
        $ownedconnections += $connection
      }
      else 
      {
        $unowndedconnections += $connection
      }
    }
    else
    {
      Write-Log "No process could be found for $Connection"
    }
  }

  #Check for connections established created over a week ago
  foreach($ownedconnection in $ownedconnections)
  {
    if($ownedconnection.creationtime -lt ((Get-Date).Subtract((New-TimeSpan -days 7))))
    {
      $oldconnections += $ownedconnection
    }
  }

  #group connections by their remote address
  $Groupedconnections = $ownedconnections | Group-Object -Property remoteaddress
  
  #filter into internal and external address'
  foreach($Groupedconnection in $Groupedconnections)
  {
    if($Groupedconnection.name -eq '::' -or $Groupedconnection.name -eq '0.0.0.0' -or $Groupedconnection.name -eq '127.0.0.1')
    {
     $internalconnections += $Groupedconnection
    }
    else
    {
      $externalconnections += $Groupedconnection
    }
  }

  #check each group for more than 100 connections to each remote machine
  foreach($internalconnection in $internalconnections)
  {
    if($internalconnection.count -gt 20)
    {
      $exceedinginternalconnections += $internalconnection
    }
  }

  #check each group for more than 100 connectiuons to each remote machine
  foreach($externalconnection in $externalconnections)
  {
    if($externalconnection.count -gt 20)
    {
      $exceedingexternalconnections += $externalconnection
    }
  }

  Write-Log "##### REPORT OF POTENTIALLY UNWANTED CONNECTIONS ##### "

  Write-Log "##### CONNECTIONS WITH A NON RESPONSIVE OWNING PROCESS #####"
  if($unowndedconnections.count -ne 0)
  {
    Write-Log "$($unowndedconnections.name)"
  }

  Write-Log "##### CONNECTIONS CREATED OVER 7 DAYS AGO #####"
  if($oldconnections.count -ne 0)
  {
    Write-Log "$($oldconnections.name)"
  }

  Write-Log "##### INTERNAL ADDRESS' WITH OVER 100 CONNECTIONS #####"
  if($exceedinginternalconnections.count -ne 0)
  {
    Write-Log "$($exceedinginternalconnections.name)"
  }

  Write-Log "##### EXTERNAL REMOTE ADDRESS' WITH OVER 100 CONNECTIONS #####"
  if($exceedingexternalconnections.count -ne 0)
  {
    Write-Log "$($exceedingexternalconnections.name)"
  }

  Write-Log "##### ENDING TCP CONNECTION TROUBLESHOOT #####"
}

#Check connection to DB is live 
if (Test-Connection $DbIP)
{
  Write-Log "CONNECTION TO $DbIP ESTABLISHED"

  Write-Log "##### GATHERING HOSTNAMES #####"

  $Influxhosts = Get-Hostnames

  Write-Log "##### HOSTNAMES GATHERED #####"

  #### GATHER ALERT THRESHOLDS ####
  Write-Log "##### GATHERING ALERT THRESHOLDS #####"

  #set thresholds for each host in array from relative json
  foreach($Influxhost in $Influxhosts)
  {
    $Influxhost.CThreshold = Get-Threshold -FreeSpace -name "C" -Computername $Influxhost.hostname
    $Influxhost.DThreshold = Get-Threshold -FreeSpace -name "D" -Computername $Influxhost.hostname
    $Influxhost.CPUThreshold = Get-Threshold -CPU -name "Processor Time" -Computername $Influxhost.hostname
    $Influxhost.MemoryThreshold = Get-Threshold -Memory -name "Avaliable Bytes" -Computername $Influxhost.hostname
    $Influxhost.TCPThreshold = Get-Threshold -TCP -name "Connections Established" -Computername $Influxhost.hostname
  }

  Write-Log "##### ALERT THRESHOLDS SET #####"

  #### BEGINNING OF MAIN LOOP - FUNCTIONS LOADED - THRESHOLD CHECKS CARRIED OUT HERE ####
  
  While($true)
  {
    foreach($Influxhost in $Influxhosts)
    {
      #set hostname to query in influxDB
      $Name = $Influxhost.hostname

      Write-Log "##### BEGINNING $NAME ASSESSMENT #####"

      ##### QUERYING DATABASE
      Write-Log "##### RUNNING DATABASE QUERIES #####"
      
      #Initialize database entry point objects
      $CDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'C:' AND host = '$name'" -ErrorAction SilentlyContinue
      
      $DDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:' AND host = '$name'" -ErrorAction SilentlyContinue
      
      $MemoryUsage = Query-Database -Memory -SELECT "LAST(`"Available Bytes`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      $CPUusage = Query-Database -CPU -SELECT "LAST(`"% Processor Time`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      $TCPconnections = Query-Database -TCP -SELECT "LAST(`"Connections Established`"), `"Connections Active`", `"Connections Passive`"" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      Write-Log "##### DATABASE QUERIES RAN #####"
      
      ##### ASSESSING THRESHOLDS
      Write-Log "##### ASSESSING THRESHOLDS #####"
      
      if($CDrive)
      {
        #Check C against threshold values
        Write-Log "Assessing drive C..."
        if($CDrive.Value -lt $Influxhost.CThreshold)
        {
        Write-Log "C: Threshold exceeded at $($CDrive.Value)"
        if($Influxhost.CdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
        {
          Clear-drive -RootDirectory $CDrive.Instance
          $Influxhost.CdriveActionTaken = $true
        }
        else #if action already taken print to log
        {
          Write-Log "Action already taken no more space can be cleared"
        }
      }
        else
        {
        Write-Log "C: Under Threshold at $("{0:n2}" -f $CDrive.Value)%"
        if($Influxhost.CdriveActionTaken -eq $true) #once under threshold again reset automated action to false
        {
          $Influxhost.CdriveActionTaken = $false
          Write-Log "C drive action taken set to false"
        }
      }
      }

      if($DDrive)
      {
        #Check D against threshold
        Write-Log "Assessing drive D..."
        if($DDrive.Value -lt $Influxhost.DThreshold)
        {
        Write-Log "D: Threshold exceeded at $($DDrive.Value)"
        if($Influxhost.DdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
        {
          Clear-Drive -RootDirectory $DDrive.Instance
          $Influxhost.DdriveActionTaken = $true
        }
        else #if action already taken print to log
        {
          Write-Log "Action already taken no more space can be cleared"
        }
      }
        else
        {
        Write-Log "D: Under Threshold at $("{0:n2}" -f $DDrive.Value)%"
        if($Influxhost.DdriveActionTaken -eq $true) #once under threshold again reset automated action to false
        {
          $Influxhost.DdriveActionTaken = $false
          Write-Log "D drive action taken set to false"
        }
      }
      }
      
      #Check Memory against threshold values
      Write-Log "Assessing Memory usage..."
      if($MemoryUsage.Mb -lt $influxhost.MemoryThreshold)
      {
        Write-Log "Avaliable bytes under threshold at $($MemoryUsage.Mb) MB"
        if($Influxhost.MemoryActionTaken -eq $false)
        {
          Clear-Resource -Memory
          $Influxhost.MemoryActionTaken = $true
        }
        else
        {
          Write-Log "Action already taken no more memory can be cleared"
        }
      }
      else
      {
       Write-Log "Memory usage under threshold at $($MemoryUsage.Mb) MB"
       if($Influxhost.MemoryActionTaken -eq $true)
       {
         $Influxhost.MemoryActionTaken = $false
         Write-Log "Memory action taken reset to false"
       }
      }
      
      #Check CPU against threshold
      Write-Log "Assessing CPU usage..."
      if($CPUusage.ProcessorTime -gt $Influxhost.CPUThreshold)
      {
        Write-Log "CPU usage over threshold at $($CPUusage.ProcessorTime)"
        if($Influxhost.CPUActionTaken -eq $false)
        {
          Clear-Resource -CPU
          $Influxhost.CPUActionTaken = $true
        }
        else
        {
          Write-Log "Action already taken no more CPU can be cleared"
        }
      }
      else
      {
        Write-Log "CPU usage under threshold at $("{0:n2}" -f $CPUusage.ProcessorTime)%"
        if($Influxhost.CPUActionTaken -eq $true)
        {
          $Influxhost.CPUActionTaken = $false
          Write-Log "CPU action taken reset to false"
        }
      }
      
      #Check TCP connection threshold
      Write-Log "Assessing TCP connection "
      if($TCPconnections.ConnectionsEstablished -gt $Influxhost.TCPThreshold)
      {
       Write-Log "TCP connections over threshold at $($TCPconnections.ConnectionsEstablished)"
       if($Influxhost.TCPActionTaken -eq $false)
       {
         Clear-TCPConnections
         $Influxhost.TCPActionTaken = $true
       }
       else
       {
         Write-Log "Report already produced please check logs"
       }
      }
      else
      {
        Write-Log "TCP connections established under threshold at $($TCPconnections.ConnectionsEstablished)"
        if($Influxhost.TCPActionTaken -eq $true)
        {
          $Influxhost.TCPActionTaken = $false
        }
      }
      
      ##### LOOP COMPLETE SLEEPING 30 UNTIL NEXT LOOP
      Write-Log "##### $($Influxhost.Hostname) ASSESED #####"
    }
  }
}
else
{
  Write-Log "Database not reachable please resolve connectivity issues"
}
