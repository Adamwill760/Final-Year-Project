Function Clear-Drive
{
  Param ([String]$RootDirectory,
         [String]$LogRulesJson,
         [String]$Logfile)

  write-log -logfile $logfile -logstring "##### BEGINNING DRIVE CLEAR #####"

  #load file retention/exclusion rules from json
  $jsonrules = get-content $LogRulesJson | ConvertFrom-Json


  write-log -logfile $logfile -logstring "##### LOADED LOG RULES #####"
  write-log -logfile $logfile -logstring "$($jsonrules.LogDirectories.location)"
  
  write-log -logfile $logfile -logstring "##### LOADED EXCLUSIONS #####"
  write-log -logfile $logfile -logstring "$($jsonrules.Exclusions.location)"

  #initialise empty directory array
  $directoryarray = @()

  #gather list of directories on the drive
  [System.Collections.ArrayList]$directorylist = Get-ChildItem -path "$RootDirectory" -Recurse -Directory -ErrorAction SilentlyContinue

  #remove list of excluded directories
  foreach($jsonexclusion in $jsonrules.Exclusions.location)
  {
    if($directorylist.fullname -contains $jsonexclusion)
    {
      $exclusions = $directorylist | Where-Object -property fullname -like $jsonexclusion*
      foreach($exclusion in $exclusions)
      {
        $directorylist.Remove($exclusion)
      }
    }
  }

  #if directory empty action should exit
  if($directorylist.Length -eq 0)
  {
    write-log -logfile $logfile -logstring "no directories contained in root directory please check assosiated threshold"
  }
  else
  {
    #foreach directory create new object (Name,Path,Total size) and append to array
    foreach($directory in $directorylist)
    {
      #must be directory full name to correctly access child directories
      $directorysize = Get-ChildItem $directory.FullName -Recurse | Measure-Object -Sum Length -ErrorAction SilentlyContinue

      #create directory object containing the properties we need for custom array
      $directoryobject = New-Object PSObject -Property @{
                          Name = $directory.Name
                          Path = $directory.FullName
                          Size = "{0:n2}" -f ($directorysize.sum/1MB)
                          }
      #append to array
      $directoryarray += $directoryobject
    }

    $strArray = $directoryarray | Sort-Object -Descending -Property size | Select-Object -First 5 | Foreach {"$($_.Name) - $($_.Size) MB"}

    Write-Log -logfile $logfile -logstring "##### Largest Directories on logical disk #####"
    Write-Log -logfile $logfile -logstring "$strArray"

    #for each rule in json file
    foreach($jsonrule in $jsonrules.LogDirectories)
    {
      #Check if the directory array contains a directory assosiated with the rule
      if($directoryarray.path.Contains($jsonrule.location))
      {
          write-log -logfile $logfile -logstring "$($jsonrule.name) json rule found in root directory"

          #select the individual directory relating to the rule in the json file
          $directorytobecleared = $directoryarray | Where-Object -Property path -EQ $jsonrule.location

          #if the directory actual size exceeds json expected size check which files are over retention
          if($directorytobecleared.size -gt $jsonrule.expectedsize)
          {
            write-log -logfile $logfile -logstring "Actual size of $($directorytobecleared.Name) exceeds expected size"

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
                  write-log -logfile $logfile -logstring "$filetobecleared Could not be removed"
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
              write-log -logfile $logfile -logstring "The following files exceeding retention of $($directorytobecleared.name) have been removed"
              $clearedarray | fl
              $spacesaved = $spacesaved/1000
              write-log -logfile $logfile -logstring "$spacesaved Kb recovered"
            }
            else
            {
              write-log -logfile $logfile -logstring "No files exceed the retention policy of $($directorytobecleared.Name)"
            }
          }
          else
          {
            write-log -logfile $logfile -logstring "$($directorytobecleared.name) does not exceed its expected size, no action taken"
          }

      }
      #no matching directory for json rule
      else
      {
        write-log -logfile $logfile -logstring "$($jsonrule.name) retention rule does not match any directory"
      }
    }
  }

  write-log -logfile $logfile -logstring "##### END OF DRIVE CLEAR ####"
}

Function Clear-Unresponsive
{
  param([parameter(parametersetname="Memory",
         Mandatory=$true)]
        [switch]$Memory,
        [parameter(parametersetname="CPU",
        Mandatory=$true)]
        [switch]$CPU,
        [array]$Processlist,
        [string]$logfile
        )
  
  write-log -logfile $logfile -logstring "##### BEGINNING UNRESPONSIVE TERMINATION #####"

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
       write-log -logfile $logfile -logstring "$($Process.Name) Not responding, currently $($Process.$resource/1MB) MB  allocated to this "
     }

     if($CPU)
     {
       write-log -logfile $logfile -logstring "$($Process.Name) Not responding, currently $($Process.$resource) CPU allocated to this "
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
   write-log -logfile $logfile -logstring "$($UnresponsiveKilledList.name) have been terminated"
  }
  
  if($UnresponsiveAliveList.Count -ne 0)
  {
   write-log -logfile $logfile -logstring "$($UnresponsiveAliveList.name) could not be terminated"
 }
  
  if($UnresponsiveKilledList.Count -eq 0 -and $UnresponsiveAliveList.count -eq 0)
  {
   write-log -logfile $logfile -logstring "No processes were found unresponsive"
  }
  
  if($ResourceRecovered -ne $null -and $Memory)
  {
   write-log -logfile $logfile -logstring "$($ResourceRecovered/1MB) MB from unresponsive processes"
  }
  elseif($ResourceRecovered -ne $null -and $CPU)
  {
   write-log -logfile $logfile -logstring "$ResourceRecovered from unresponsive processes"
  }
  
  write-log -logfile $logfile -logstring "##### END OF UNRESPONSIVE TERMINATION #####"

  return $ResourceRecovered
}

Function Clear-Resource
{

 param([parameter(parametersetname="Memory", Mandatory=$true)]
       [switch]$Memory,
       [parameter(parametersetname="CPU", Mandatory=$true)]
       [switch]$CPU, 
       [string]$ProcessesRulesJson,
       [string]$logfile
       )

 write-log -logfile $logfile -logstring "##### BEGINNING RESOURCE CLEARANCE #####"

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
     write-log -logfile $logfile -logstring "$($ProcessRule.name) rule has a running process"

     #Select related process to rule
     $ComparingProcess = $ProcessList | Where-Object -Property name -Match $ProcessRule.name

     #check threshold exceeded and terminatable
     if($ComparingProcess.$resource -gt $ProcessRule.$threshold -and $ProcessRule.terminatable -eq "true")
     {
       write-log -logfile $logfile -logstring "$($ComparingProcess.name) $measurement exceeds expected and can be terminated"

       if(Stop-Process $ComparingProcess -force -PassThru)
       {
         write-log -logfile $logfile -logstring "$($ComparingProcess.name) terminated"
         $ResourceRecovered = $ResourceRecovered + $ComparingProcess.$resource
       }
       else
       {
         write-log -logfile $logfile -logstring "$($ComparingProcess.name) could not be terminated"
       }
     }
     elseif($ComparingProcess.$resource -gt $ProcessRule.$threshold -and $ProcessRule.terminatable -eq "false")
     {
      write-log -logfile $logfile -logstring "$($ComparingProcess.Name) $measurement exceeds expected size but can not be automatically terminated"
     }
     elseif($ComparingProcess.$resource -lt $ProcessRule.$threshold)
     {
       write-log -logfile $logfile -logstring "$($ComparingProcess.Name) $measurement is less than threshold"
     }
   }
   else
   {
    write-log -logfile $logfile -logstring "No $($ProcessRule.name) process running"
   }
 }

 if($Memory)
 {
   write-log -logfile $logfile -logstring "$($ResourceRecovered/1MB) total $measurement recovered"
 }
 elseif($CPU)
 {
   write-log -logfile $logfile -logstring "$([int]$ResourceRecovered) total $measurement recovered"
 }

 write-log -logfile $logfile -logstring "##### END OF RESOURCE CLEARANCE #####"

}

Function Clear-TCPConnections
{
  param([string]$logfile)

  write-log -logfile $logfile -logstring "##### BEGINNING TCP CONNECTION TROUBLESHOOT #####"
  
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
      write-log -logfile $logfile -logstring "No process could be found for $Connection"
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

  write-log -logfile $logfile -logstring "##### REPORT OF POTENTIALLY UNWANTED CONNECTIONS ##### "

  write-log -logfile $logfile -logstring "##### CONNECTIONS WITH A NON RESPONSIVE OWNING PROCESS #####"
  if($unowndedconnections.count -ne 0)
  {
    write-log -logfile $logfile -logstring "$($unowndedconnections.name)"
  }

  write-log -logfile $logfile -logstring "##### CONNECTIONS CREATED OVER 7 DAYS AGO #####"
  if($oldconnections.count -ne 0)
  {
    write-log -logfile $logfile -logstring "$($oldconnections.name)"
  }

  write-log -logfile $logfile -logstring "##### INTERNAL ADDRESS' WITH OVER 100 CONNECTIONS #####"
  if($exceedinginternalconnections.count -ne 0)
  {
    write-log -logfile $logfile -logstring "$($exceedinginternalconnections.name)"
  }

  write-log -logfile $logfile -logstring "##### EXTERNAL REMOTE ADDRESS' WITH OVER 100 CONNECTIONS #####"
  if($exceedingexternalconnections.count -ne 0)
  {
    write-log -logfile $logfile -logstring "$($exceedingexternalconnections.name)"
  }

  write-log -logfile $logfile -logstring "##### ENDING TCP CONNECTION TROUBLESHOOT #####"
}