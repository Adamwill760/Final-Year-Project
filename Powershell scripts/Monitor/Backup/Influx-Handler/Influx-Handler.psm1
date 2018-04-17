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
    $influxhost = New-Object InfluxHost
    $influxhost.hostname = $trimmedname
    $hostarray += $influxhost
  }
  
  return $hostarray
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

