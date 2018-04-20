Add-Type -AssemblyName presentationframework, presentationcore

$WPF = [hashtable]::Synchronized(@{})
$newRunspace =[runspacefactory]::CreateRunspace()
$newRunspace.ApartmentState = "STA"
$newRunspace.ThreadOptions = "ReuseThread"         
$newRunspace.Open()
$newRunspace.SessionStateProxy.SetVariable("WPF",$WPF)

$psCmd = [PowerShell]::Create().AddScript({
$inputxml = get-content "D:\University work\Third Year\Final Year Project\Product\Powershell scripts\Monitor\PerformanceMonitor.xaml" 
$CleanXml = $inputxml -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace 'x:Class=".*?"','' -replace 'd:DesignHeight="\d*?"','' -replace 'd:DesignWidth="\d*?"',''
[xml]$Xaml = $CleanXml

$reader = New-Object System.Xml.XmlNodeReader $Xaml 
$tempform = [windows.markup.xamlreader]::load($reader) 

$namednodes = $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]")
$namedNodes | ForEach-Object {$wpf.Add($_.Name, $tempform.FindName($_.Name))} 

$wpf.PerformanceMonitorWindow.ShowDialog()
})

$psCmd.runspace = $newRunspace

$data = $psCmd.Invoke()

$influxhost = New-Object PSobject -Property @{
    Name = "windows-vm-01"
}
