Function Get-PScredentials
{
  $Username = 'AdamNMP@outlook.com'

  $Password = 'Project1'

  #convert password to secure string to be passed over network
  $pass = ConvertTo-SecureString -AsPlainText $Password -Force

  $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pass

  return $Credentials
}