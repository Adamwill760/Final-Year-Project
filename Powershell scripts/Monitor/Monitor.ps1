#import custom modules
Import-Module Logging 
Import-Module Credentials
Import-Module Thresholds
Import-Module Resource-Clearance
Import-Module Influx-Handler

#Define database IP address
$DbIP = '192.168.56.103'

#Define the location to write the log file
$Logfile = "D:\University work\Third Year\Final Year Project\Product\PerformanceMonitor.log"

#Location of the JSON rule files
$ThresholdsFile = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\Threshold.json"
$LogRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\LogDirs.json"
$ProcessesRulesJson = "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\JSON\ProcessRules.json"

#Check connection to DB is live 
if (Test-Connection $DbIP)
{
  write-log -logfile $logfile -logstring "CONNECTION TO $DbIP ESTABLISHED"

  $credentials = Get-PScredentials

  write-log -logfile $logfile -logstring "##### GATHERING HOSTNAMES #####"

  $Influxhosts = Get-Hostnames -DbIP $DbIP

  write-log -logfile $logfile -logstring "##### HOSTNAMES GATHERED #####"

  #### GATHER ALERT THRESHOLDS ####
  write-log -logfile $logfile -logstring "##### GATHERING ALERT THRESHOLDS #####"

  #set thresholds for each host in array from relative json
  foreach($Influxhost in $Influxhosts)
  {
    $Influxhost.CThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -FreeSpace -name "C" -Computername $Influxhost.hostname -logfile $logfile
    $Influxhost.DThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -FreeSpace -name "D" -Computername $Influxhost.hostname -logfile $logfile
    $Influxhost.CPUThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -CPU -name "Processor Time" -Computername $Influxhost.hostname -logfile $logfile
    $Influxhost.MemoryThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -Memory -name "Avaliable Bytes" -Computername $Influxhost.hostname -logfile $logfile
    $Influxhost.TCPThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -TCP -name "Connections Established" -Computername $Influxhost.hostname -logfile $logfile
  }

  write-log -logfile $logfile -logstring "##### ALERT THRESHOLDS SET #####"

  #### BEGINNING OF MAIN LOOP - FUNCTIONS LOADED - THRESHOLD CHECKS CARRIED OUT HERE ####
  
  While($true)
  {
    foreach($Influxhost in $Influxhosts)
    {
      #set hostname to query in influxDB
      $Name = $Influxhost.hostname

      write-log -logfile $logfile -logstring "##### BEGINNING $NAME ASSESSMENT #####"

      ##### QUERYING DATABASE
      write-log -logfile $logfile -logstring "##### RUNNING DATABASE QUERIES #####"
      
      #Initialize database entry point objects
      $CDrive = Query-Database -DbIP $DbIP -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'C:' AND host = '$name'" -ErrorAction SilentlyContinue
      
      $DDrive = Query-Database -DbIP $DbIP -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:' AND host = '$name'" -ErrorAction SilentlyContinue
      
      $MemoryUsage = Query-Database -DbIP $DbIP -Memory -SELECT "LAST(`"Available Bytes`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      $CPUusage = Query-Database -DbIP $DbIP -CPU -SELECT "LAST(`"% Processor Time`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      $TCPconnections = Query-Database -DbIP $DbIP -TCP -SELECT "LAST(`"Connections Established`"), `"Connections Active`", `"Connections Passive`"" -WHERE "host = '$name'" -ErrorAction SilentlyContinue
      
      write-log -logfile $logfile -logstring "##### DATABASE QUERIES RAN #####"
      
      ##### ASSESSING THRESHOLDS
      write-log -logfile $logfile -logstring "##### ASSESSING THRESHOLDS #####"
      
      if($CDrive)
      {
        #Check C against threshold values
        write-log -logfile $logfile -logstring "Assessing drive C..."
        if($CDrive.Value -lt $Influxhost.CThreshold)
        {
          write-log -logfile $logfile -logstring "C: Threshold exceeded at $($CDrive.Value)%"
          if($Influxhost.CdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
          {
            Invoke-Command $Name -Credential $credentials -Scriptblock{
            
            Import-Module Resource-clearance
            Import-Module Logging

            $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-CDrive.log" -force
            $Rules = "C:\Performance Monitor\Rules\LogDirs.json"

            Clear-Drive -RootDirectory "$($CDrive.Instance)\" -LogRulesJson $Rules -Logfile $Logfile
          }
          #move log file back to host PC
          Move-Item -Path "\\$name\C`$\Performance Monitor\Logs\$name-CDrive.log" -Destination "\\Adam-PC\D`$\University work\Third Year\Final Year Project\Product" -force

          $Influxhost.CdriveActionTaken = $true
        }
        else #if action already taken print to log
        {
          write-log -logfile $logfile -logstring "Action already taken no more space can be cleared"
        }
      }
        else
        {
        write-log -logfile $logfile -logstring "C: Under Threshold at $("{0:n2}" -f $CDrive.Value)%"
        if($Influxhost.CdriveActionTaken -eq $true) #once under threshold again reset automated action to false
        {
          $Influxhost.CdriveActionTaken = $false
          write-log -logfile $logfile -logstring "C drive action taken set to false"
        }
      }
      }

      if($DDrive)
      {
        #Check D against threshold
        write-log -logfile $logfile -logstring "Assessing drive D..."
        if($DDrive.Value -lt $Influxhost.DThreshold)
        {
        write-log -logfile $logfile -logstring "D: Threshold exceeded at $($DDrive.Value)"
        if($Influxhost.DdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
        {
            Invoke-Command $Name -Credential $credentials -Scriptblock{
            
            Import-Module Resource-clearance
            Import-Module Logging

            $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-Ddrive.log"
            $Rules = "C:\Performance Monitor\Rules\LogDirs.json"

            Clear-Drive -RootDirectory "$($DDrive.Instance)\" -LogRulesJson $Rules -Logfile $Logfile
            }

          #move log file back to host PC
          Move-Item -Path "\\$name\C`$\Performance Monitor\Logs\$name-Ddrive.log" -Destination "\\Adam-PC\D`$\University work\Third Year\Final Year Project\Product" -Force

          $Influxhost.DdriveActionTaken = $true
        }
        else #if action already taken print to log
        {
          write-log -logfile $logfile -logstring "Action already taken no more space can be cleared"
        }
      }
        else
        {
        write-log -logfile $logfile -logstring "D: Under Threshold at $("{0:n2}" -f $DDrive.Value)%"
        if($Influxhost.DdriveActionTaken -eq $true) #once under threshold again reset automated action to false
        {
          $Influxhost.DdriveActionTaken = $false
          write-log -logfile $logfile -logstring "D drive action taken set to false"
        }
      }
      }
      
      #Check Memory against threshold values
      write-log -logfile $logfile -logstring "Assessing Memory usage..."
      if($MemoryUsage.Mb -lt $influxhost.MemoryThreshold)
      {
        write-log -logfile $logfile -logstring "Avaliable bytes under threshold at $($MemoryUsage.Mb) MB"
        if($Influxhost.MemoryActionTaken -eq $false)
        {
          Invoke-Command $Name -Credential $credentials -Scriptblock{
          
          Import-Module Resource-clearance
          Import-Module Logging

          $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-Memory.log" -force
          $Rules = "C:\Performance Monitor\Rules\ProcessRules.json"

          Clear-Resource -Memory -ProcessesRulesJson $Rules -logfile $Logfile
          }

          #move log file back to host PC
          Move-Item -Path "\\$name\C`$\Performance Monitor\Logs\$name-Memory.log" -Destination "\\Adam-PC\D`$\University work\Third Year\Final Year Project\Product" -Force
          
          $Influxhost.MemoryActionTaken = $true
        }
        else
        {
          write-log -logfile $logfile -logstring "Action already taken no more memory can be cleared"
        }
      }
      else
      {
       write-log -logfile $logfile -logstring "Memory usage under threshold at $($MemoryUsage.Mb) MB"
       if($Influxhost.MemoryActionTaken -eq $true)
       {
         $Influxhost.MemoryActionTaken = $false
         write-log -logfile $logfile -logstring "Memory action taken reset to false"
       }
      }
      
      #Check CPU against threshold
      write-log -logfile $logfile -logstring "Assessing CPU usage..."
      if($CPUusage.ProcessorTime -gt $Influxhost.CPUThreshold)
      {
        write-log -logfile $logfile -logstring "CPU usage over threshold at $($CPUusage.ProcessorTime)"
        if($Influxhost.CPUActionTaken -eq $false)
        {
          Invoke-Command $Name -Credential $credentials -Scriptblock{
            
            Import-Module Resource-clearance
            Import-Module Logging

            $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-CPU.log" -force
            $Rules = "C:\Performance Monitor\Rules\ProcessRules.json"

            Clear-Resource -CPU -ProcessesRulesJson $Rules -logfile $Logfile
          }

          #move log file back to host PC
          Move-Item -Path "\\$name\C`$\Performance Monitor\Logs\$name-CPU.log" -Destination "\\Adam-PC\D`$\University work\Third Year\Final Year Project\Product" -force

          $Influxhost.CPUActionTaken = $true
        }
        else
        {
          write-log -logfile $logfile -logstring "Action already taken no more CPU can be cleared"
        }
      }
      else
      {
        write-log -logfile $logfile -logstring "CPU usage under threshold at $("{0:n2}" -f $CPUusage.ProcessorTime)%"
        if($Influxhost.CPUActionTaken -eq $true)
        {
          $Influxhost.CPUActionTaken = $false
          write-log -logfile $logfile -logstring "CPU action taken reset to false"
        }
      }
      
      #Check TCP connection threshold
      write-log -logfile $logfile -logstring "Assessing TCP connection "
      if($TCPconnections.ConnectionsEstablished -gt $Influxhost.TCPThreshold)
      {
       write-log -logfile $logfile -logstring "TCP connections over threshold at $($TCPconnections.ConnectionsEstablished)"
       if($Influxhost.TCPActionTaken -eq $false)
       {
         Invoke-Command $Name -Credential $credentials -Scriptblock{
            
            Import-Module Resource-clearance
            Import-Module Logging

            $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-TCP.log" -force

            Clear-TCPConnections -logfile $Logfile
          }

          #move log file back to host PC
          Move-Item -Path "\\$name\C`$\Performance Monitor\Logs\$name-TCP.log" -Destination "\\Adam-PC\D`$\University work\Third Year\Final Year Project\Product" -force

         $Influxhost.TCPActionTaken = $true
       }
       else
       {
         write-log -logfile $logfile -logstring "Report already produced please check logs"
       }
      }
      else
      {
        write-log -logfile $logfile -logstring "TCP connections established under threshold at $($TCPconnections.ConnectionsEstablished)"
        if($Influxhost.TCPActionTaken -eq $true)
        {
          $Influxhost.TCPActionTaken = $false
        }
      }
      
      ##### LOOP COMPLETE SLEEPING 30 UNTIL NEXT LOOP
      write-log -logfile $logfile -logstring "##### $($Influxhost.Hostname) ASSESED #####"
    }
  }
}
else
{
  write-log -logfile $logfile -logstring "Database not reachable please resolve connectivity issues"
}
