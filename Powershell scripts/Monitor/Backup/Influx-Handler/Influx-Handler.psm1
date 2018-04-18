class InfluxHost
{
  [string]$Hostname
  [bool]$CdriveActionTaken
  [bool]$MemoryActionTaken
  [bool]$CPUActionTaken
  [bool]$TCPActionTaken
  [int]$CThreshold
  [int]$CPUThreshold
  [int]$MemoryThreshold
  [int]$TCPThreshold
  [int]$CValue
  [int]$CPUValue
  [int]$MemoryValue
  [int]$TCPValue
}

class InfluxDHost : Influxhost
{
  [int]$DThreshold
  [int]$DValue
  [bool]$DdriveActionTaken
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
        [string]$WHERE,
        [string]$DbIP
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
   ##create custom drive object
   #$Drive = New-Object PSObject -Property @{
   #  Time = $result[0][0]
   #  Value = $result[0][1]
   #  Instance = $result[0][2]
   #  }
     
     return $result[0][1]
 }
 elseif($Memory)
 { 
  #create custom memory object 
  #$MemoryObject = New-Object PSobject -Property @{
  #            Time = $result[0][0] 
  #            Kb =  [int](($result[0][1])/1KB)
  #            Mb = [int](($result[0][1])/1MB)
  #            Gb = "{0:n2}" -f (($result[0][1])/1GB)}
  #
 return [int](($result[0][1])/1MB)
 }
 elseif($CPU)
 {
   #create custom CPU object 
   #$CPUObject = New-Object PSobject -Property @{
   #            Time = $result[0][0] 
   #            ProcessorTime = $result[0][1]}
   
   return $result[0][1]
 }
 elseif($TCP)
 {
   #create custom CPU object 
   #$TCPObject = New-Object PSobject -Property @{
   #            Time = $result[0][0] 
   #            ConnectionsEstablished = $result[0][1]
   #            ConnectionsActive = $result[0][2]
   #            ConnectionsPassive= $result[0][3]
   #            }
   
   return $result[0][1]
 }
}


Function Get-Hostnames
{
  param([string]$DbIP)

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
    try
      {
        Query-Database -DbIP $DbIP -FreeSpace -SELECT "LAST(`"% Free Space`"), instance" -WHERE "instance = 'D:' AND host = '$trimmedname'"
        $influxhost = New-Object InfluxDHost
        $influxhost.hostname = $trimmedname
        $hostarray += $influxhost
      }
      catch
      {
        $influxhost = New-Object InfluxHost
        $influxhost.hostname = $trimmedname
        $hostarray += $influxhost
      } 
  }
  
  return $hostarray
}


