#Define database IP address
$DbIP = '192.168.56.101'

#Define the location to write the log file
$Logfile = "D:\University work\Third Year\Final Year Project\Product\$(gc env:computername).log"

#Location of the JSON files
$ThresholdsFile = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\Threshold.json"
$LogRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\LogDirs.json"

#Action taken boolean declaration
$DdriveActionTaken = $false
$CdriveActionTaken = $false
$MemoryActionTaken = $false

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
    $FROM = "win_mem"

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

    $MemoryObject = New-Object PSobject -Property @{
                Time = $result[0][0] 
                Kb =  [int](($result[0][1])/1KB)
                Mb = [int](($result[0][1])/1MB)
                Gb = "{0:n2}" -f (($result[0][1])/1GB)}

    return $MemoryObject

  }
  elseif($CPU)
  {
    $FROM = "win_cpu"
  }
  elseif($TCP)
  {
    $FROM = "win_net"
  }
}

Function Clear-Drive
{
  Param ([String]$RootDirectory,
         [String]$JsonLocation)

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
}

Function Clear-Memory
{
  
}

#Check connection to DB is live 
if (Test-Connection $DbIP)
{
  #### GATHER ALERT THRESHOLDS ####
  $CThreshold = Get-Threshold -FreeSpace -name "C"
  Write-Log "C Threshold has been set to $CThreshold %"

  $DThreshold = Get-Threshold -FreeSpace -name "D"
  Write-Log "D Threshold has been set to $DThreshold %"

  $MemoryThreshold = Get-Threshold -Memory -name "Avaliable Bytes"
  Write-Log "Memory Threshold set to $MemoryThreshold MB"

  #### BEGINNING OF MAIN LOOP - FUNCTIONS LOADED - THRESHOLD CHECKS CARRIED OUT HERE ####
  While($true)
  {
    #Initialize database entry point objects
    $CDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'C:'"

    $DDrive = Query-Database -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:'"

    $MemoryUsage = Query-Database -Memory -SELECT "LAST(`"Available Bytes`")" 

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
      Write-Log "Avaliable bytes under threshold at $($MemoryUsage.Mb)"
      if($MemoryActionTaken -eq $false)
      {
        #### Memory clear action ####
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
    }

    Write-host "Query ran, sleeping"
    start-sleep 30 #sleep 30 until next query

  }
}
else
{
  Write-Log "Database not reachable please resolve connectivity issues"
}
