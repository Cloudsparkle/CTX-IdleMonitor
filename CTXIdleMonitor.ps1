<#
.SYNOPSIS
  Monitor and log off disconnected sessions of specific apps accross multiple sites
.DESCRIPTION
  For specific published applications, monitor for disconnected sessions and when found log off
.INPUTS
  Ini file containing DDC and application list
.OUTPUTS
  None
.NOTES
  Version:        1.0
  Author:         Bart Jacobs - @Cloudsparkle
  Creation Date:  15/03/2022
  Purpose/Change: Monitor disconnected sessions
 .EXAMPLE
  None
#>

# Try loading Citrix Powershell modules, exit when failed
If ((Get-PSSnapin "Citrix*" -EA silentlycontinue) -eq $null)
{
  try {Add-PSSnapin Citrix* -ErrorAction Stop }
  catch {Write-error "Error loading Citrix Powershell snapins"; Return }
}

# Get ready for the GUI stuff
Add-Type -AssemblyName PresentationFramework

Function Get-IniContent
{
    <#
    .Synopsis
        Gets the content of an INI file
    .Description
        Gets the content of an INI file and returns it as a hashtable
    .Notes
        Author        : Oliver Lipkau <oliver@lipkau.net>
        Blog        : http://oliver.lipkau.net/blog/
        Source        : https://github.com/lipkau/PsIni
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
        Version        : 1.0 - 2010/03/12 - Initial release
                      1.1 - 2014/12/11 - Typo (Thx SLDR)
                                         Typo (Thx Dave Stiff)
        #Requires -Version 2.0
    .Inputs
        System.String
    .Outputs
        System.Collections.Hashtable
    .Parameter FilePath
        Specifies the path to the input file.
    .Example
        $FileContent = Get-IniContent "C:\myinifile.ini"
        -----------
        Description
        Saves the content of the c:\myinifile.ini in a hashtable called $FileContent
    .Example
        $inifilepath | $FileContent = Get-IniContent
        -----------
        Description
        Gets the content of the ini file passed through the pipe into a hashtable called $FileContent
    .Example
        C:\PS>$FileContent = Get-IniContent "c:\settings.ini"
        C:\PS>$FileContent["Section"]["Key"]
        -----------
        Description
        Returns the key "Key" of the section "Section" from the C:\settings.ini file
    .Link
        Out-IniFile
    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [ValidateScript({(Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini")})]
        [Parameter(ValueFromPipeline=$True,Mandatory=$True)]
        [string]$FilePath
    )

    Begin
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}

    Process
    {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"

        $ini = @{}
        switch -regex -file $FilePath
        {
            "^\[(.+)\]$" # Section
            {
                $section = $matches[1]
                $ini[$section] = @{}
                $CommentCount = 0
            }
            "^(;.*)$" # Comment
            {
                if (!($section))
                {
                    $section = "No-Section"
                    $ini[$section] = @{}
                }
                $value = $matches[1]
                $CommentCount = $CommentCount + 1
                $name = "Comment" + $CommentCount
                $ini[$section][$name] = $value
            }
            "(.+?)\s*=\s*(.*)" # Key
            {
                if (!($section))
                {
                    $section = "No-Section"
                    $ini[$section] = @{}
                }
                $name,$value = $matches[1..2]
                $ini[$section][$name] = $value
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"
        Return $ini
    }

    End
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}
}

$currentDir = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
if ($currentDir -eq $PSHOME.TrimEnd('\'))
{
  $currentDir = $PSScriptRoot
}

$ConfigINI = $currentDir + "\config.ini"

while ($true)
{
  $IniFileExists = Test-Path $ConfigINI
  If ($IniFileExists -eq $true)
  {
    Write-Host "Reading config.ini..."
    $IniFile = Get-IniContent $ConfigINI
  }
  Else
  {
    $msgBoxInput = [System.Windows.MessageBox]::Show("Error reading config.ini.","Error","OK","Error")
    switch  ($msgBoxInput)
    {
      "OK"
      {
        Exit 1
      }
    }
  }

  $DDCList = $IniFile.Keys
  foreach ($DDC in $DDCList)
  {
    Write-Host "Getting all disconnected sessions from" $DDC"..."
    $DisconnectedSessions = Get-BrokerSession -MaxRecordCount 10000 -AdminAddress $DDC -SessionState Disconnected
    $CTXAppList = $IniFile[$DDC].Keys

    foreach ($DisconnectedSession in $DisconnectedSessions)
    {
      foreach ($CTXApp in $CTXAppList)
      {
        $CTXAppToLookFor = ($IniFile[$DDC][$CTXApp]).Trim()
        $PublishedApps = $DisconnectedSession.ApplicationsInUse
        foreach ($PublishedApp in $PublishedApps)
        {
          $PublishedAppSplit = $PublishedApp.Split("\")
          $PublishedAppName = $PublishedAppSplit[-1]

          if ($PublishedAppName -eq $CTXAppToLookFor)
          {
            Write-Host $IniFile[$DDC][$CTXApp] "has a disconnected session for" ($DisconnectedSession.UserFullName).trim()". Logging off." -ForegroundColor Green
            Stop-BrokerSession $disconnectedsession
          }
        }
      }
    }
  }

  Write-host "Waiting for next run..." -ForegroundColor Yellow
  [System.GC]::Collect()
  Sleep 10
}
