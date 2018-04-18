#import custom modules
Import-Module Logging 
Import-Module Credentials
Import-Module Thresholds
Import-Module Resource-Clearance
Import-Module Influx-Handler -Force

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
  Write-Log -Logfile $Logfile -Logstring "##### LOADING GUI #####"

  ### DEFINE GUI OBJECTS ##
  #
  #Add-Type -AssemblyName presentationframework, presentationcore
  #$wpf = @{} 
  #$inputxml = get-content "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\PerformanceMonitor.xaml" 
  #$CleanXml = $inputxml -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace 'x:Class=".*?"','' -replace 'd:DesignHeight="\d*?"','' -replace 'd:DesignWidth="\d*?"',''
  #[xml]$Xaml = $CleanXml
  #$reader = New-Object System.Xml.XmlNodeReader $Xaml 
  #$tempform = [windows.markup.xamlreader]::load($reader) 
  #$namednodes = $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]")
  #$namedNodes | ForEach-Object {$wpf.Add($_.Name, $tempform.FindName($_.Name))}
  #
  ### END GUI DEFINITION ##

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
    
    if($Influxhost.DThreshold)
    {
      $Influxhost.DThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -FreeSpace -name "D" -Computername $Influxhost.hostname -logfile $logfile
    }
    
    $Influxhost.CPUThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -CPU -name "Processor Time" -Computername $Influxhost.hostname -logfile $logfile
    
    $Influxhost.MemoryThreshold = Get-Threshold -ThresholdsFile $ThresholdsFile -Memory -name "Available Bytes" -Computername $Influxhost.hostname -logfile $logfile
    
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
      
      #Set database values for influxhost instance
      try{$influxhost.CValue = Query-Database -DbIP $DbIP -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'C:' AND host = '$name'" -ErrorAction SilentlyContinue}
      catch
      {
        write-log -logfile $logfile -logstring "Database could not be queried C drive value not attained for $name"
        $Influxhost.CValue = 0
      }

      if($Influxhost.DValue)
      {
        try{$influxhost.DValue = Query-Database -DbIP $DbIP -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:' AND host = '$name'" -ErrorAction SilentlyContinue}
        catch
        {
       write-log -logfile $logfile -logstring "Database could not be queried D drive value not attained for $name"
       $influxhost.Dvalue = 0
      }
      }

      try{$influxhost.MemoryValue = Query-Database -DbIP $DbIP -Memory -SELECT "LAST(`"Available Bytes`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue}
      catch
      {
        write-log -logfile $logfile -logstring "Database could not be queried memory usage value not attained for $name"
        $influxhost.MemoryValue = 0
      }

      try{$influxhost.CPUValue = Query-Database -DbIP $DbIP -CPU -SELECT "LAST(`"% Processor Time`")" -WHERE "host = '$name'" -ErrorAction SilentlyContinue}
      catch
      {
        write-log -logfile $logfile -logstring "Database could not be queried CPU usage value not attained for $name"
        $influxhost.CPUValue = 0
      }

      try{$influxhost.TCPvalue = Query-Database -DbIP $DbIP -TCP -SELECT "LAST(`"Connections Established`"), `"Connections Active`", `"Connections Passive`"" -WHERE "host = '$name'" -ErrorAction SilentlyContinue}
      catch
      {
        write-log -logfile $logfile -logstring "Database could not be queried TCP connection value not attained for $name"
        $influxhost.TCPvalue = 0
      }
    
      write-log -logfile $logfile -logstring "##### DATABASE QUERIES RAN #####"
      
      ##### ASSESSING THRESHOLDS
      write-log -logfile $logfile -logstring "##### ASSESSING THRESHOLDS #####"

      #Check C against threshold values
      write-log -logfile $logfile -logstring "Assessing drive C..."
      if($Influxhost.CValue -lt $Influxhost.CThreshold)
      {
        write-log -logfile $logfile -logstring "C: Threshold exceeded at $($Influxhost.CValue)%"
        if($Influxhost.CdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
        {
          Invoke-Command $Name -Credential $credentials -Scriptblock{
          
          Import-Module Resource-clearance
          Import-Module Logging

          $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-CDrive.log" -force
          $Rules = "C:\Performance Monitor\Rules\LogDirs.json"

          Clear-Drive -RootDirectory "C:\" -LogRulesJson $Rules -Logfile $Logfile
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
        write-log -logfile $logfile -logstring "C: Under Threshold at $("{0:n2}" -f $Influxhost.CValue)%"

        if($Influxhost.CdriveActionTaken -eq $true) #once under threshold again reset automated action to false
        {
          $Influxhost.CdriveActionTaken = $false
          write-log -logfile $logfile -logstring "C drive action taken set to false"
        }
      }
      
      #Check D against threshold
      if($Influxhost.DValue)
      {
        write-log -logfile $logfile -logstring "Assessing drive D..."
        if($Influxhost.DValue -lt $Influxhost.DThreshold)
        {
          write-log -logfile $logfile -logstring "D: Threshold exceeded at $($DDrive.Value)"
          if($Influxhost.DdriveActionTaken -eq $false) #if automated action not already taken, run clear-drive
          {
              Invoke-Command $Name -Credential $credentials -Scriptblock{
              
              Import-Module Resource-clearance
              Import-Module Logging
          
              $Logfile = New-Item "C:\Performance Monitor\logs\$(gc env:computername)-Ddrive.log"
              $Rules = "C:\Performance Monitor\Rules\LogDirs.json"
          
              Clear-Drive -RootDirectory "D:\" -LogRulesJson $Rules -Logfile $Logfile
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
          write-log -logfile $logfile -logstring "D: Under Threshold at $("{0:n2}" -f $Influxhost.DValue)%"

          if($Influxhost.DdriveActionTaken -eq $true) #once under threshold again reset automated action to false
          {
            $Influxhost.DdriveActionTaken = $false
            write-log -logfile $logfile -logstring "D drive action taken set to false"
          }
        }
      }

      #Check Memory against threshold values
      write-log -logfile $logfile -logstring "Assessing Memory usage..."
      if($influxhost.MemoryValue -lt $influxhost.MemoryThreshold)
      {
        write-log -logfile $logfile -logstring "Available bytes under threshold at $($influxhost.MemoryValue) MB"
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
        write-log -logfile $logfile -logstring "Memory usage under threshold at $($influxhost.MemoryValue) MB"
        
        if($Influxhost.MemoryActionTaken -eq $true)
        {
          $Influxhost.MemoryActionTaken = $false
          write-log -logfile $logfile -logstring "Memory action taken reset to false"
        }
      }
      
      #Check CPU against threshold
      write-log -logfile $logfile -logstring "Assessing CPU usage..."
      if($Influxhost.CPUValue -gt $Influxhost.CPUThreshold)
      {
        write-log -logfile $logfile -logstring "CPU usage over threshold at $($Influxhost.CPUValue)"
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
        write-log -logfile $logfile -logstring "CPU usage under threshold at $("{0:n2}" -f $Influxhost.CPUValue)%"

        if($Influxhost.CPUActionTaken -eq $true)
        {
          $Influxhost.CPUActionTaken = $false
          write-log -logfile $logfile -logstring "CPU action taken reset to false"
        }
      }
      
      #Check TCP connection threshold
      write-log -logfile $logfile -logstring "Assessing TCP connection "
      if($Influxhost.TCPValue -gt $Influxhost.TCPThreshold)
      {
       write-log -logfile $logfile -logstring "TCP connections over threshold at $($Influxhost.TCPValue)"
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
        write-log -logfile $logfile -logstring "TCP connections established under threshold at $($Influxhost.TCPValue)"
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
