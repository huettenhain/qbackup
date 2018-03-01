[CmdletBinding(DefaultParameterSetName='auto')]
Param(
  [Parameter(ParameterSetName='config')]
    [switch] $SetSecret,
  [Parameter(ParameterSetName='config')]
    [switch] $Configure,
  [Parameter(ParameterSetName='show',Mandatory=$True)]
    [switch] $IddQd,
  [Parameter(ParameterSetName='borg',Mandatory=$True)]
    [switch] $Borg,
  [Parameter(ParameterSetName='auto')]
    [switch] $Init,
  [Parameter(ParameterSetName='auto')]
    [switch] $ACLs,
  [Parameter(ParameterSetName='auto')]
    [switch] $Pruned,
  [Parameter(ParameterSetName='auto')]
    [switch] $Log,
  [Parameter(ParameterSetName='auto',Position=0,Mandatory=$True)] 
  [ValidateNotNullOrEmpty()]
    [string] $BackupPath,
  [parameter(ParameterSetName='borg',ValueFromRemainingArguments=$True)]
  [parameter(ParameterSetName='auto',ValueFromRemainingArguments=$True)]
      $brgs
)

$env:Path = [string]::Format("{0};{1}", $PSScriptRoot, $env:Path)
$SSHKeyFileName = Join-Path $PSScriptRoot 'qbackup.sshkey'
$QBSettingsFile = Join-Path $PSScriptRoot 'qbackup.json'

if (-not (Test-Path env:QPREFX)) { $env:QPREFIX = '-- ' }

function Announce ([String] $Prompt) { 
  $final = [string]::Format("{0}{1}", $env:QPREFIX, $Prompt)
  $stdout=[System.Console]::OpenStandardOutput()
  $buffer=[System.Text.Encoding]::ASCII.GetBytes($final)
  $stdout.Write($buffer, 0, $final.Length)
}

function Info ([string] $InputObject) { 
  Write-Output ($env:QPREFIX + $InputObject)
}

function CygPath([String] $WindowsPath) {
  $PathItem = Get-Item $WindowsPath
  $RelativePath = (Split-Path $PathItem.FullName -NoQualifier).Substring(1)
  $CygPath = (Join-Path 'cygdrive' (Join-Path $PathItem.PSDrive.Name $RelativePath))
  return ('/'+$CygPath.Replace('\','/'))
}


###########################################################################

# PARSE CONFIGURATION

$defaults = @{  
  binary = 'borg'
; bflags = '--compression zlib,9 --stats --list --filter=ME'
; remote = $null
; format = 'yyyy-MM-dd_HH-mm-ss'
; pruned = '--keep-daily 30 --keep-weekly 52 --keep-monthly 12 --keep-yearly 20'
}

$stats = @{}
if (Test-Path $QBSettingsFile) {
  $_json = (Get-Content $QBSettingsFile) -join '' | ConvertFrom-Json 
  $_json.PSObject.Properties | ForEach { $stats[$_.Name] = $_.Value }
} else { 
  Info 'No settings found.'  
}

if (-Not $stats.containsKey('secret') -Or $SetSecret.IsPresent) {
  Announce 'Enter Secret: '
  $s = Read-Host -AsSecureString | ConvertFrom-SecureString
  if ($stats.containsKey('secret')) {
    $stats.secret = $s 
  } else {
    $stats.Add('secret', $s)
  }
}

$defaults.GetEnumerator() | ForEach {
  if (-Not $stats.containsKey($_.Name)) {
    if ($_.Value -Eq $null) {
      $v = Read-Host ('provide value for setting ' + $_.Name)
    } else {
      $v = $_.Value
    }
    $stats.Add($_.Name, $v)
  }
}

if ($Configure.IsPresent) {
  Info 'Configuration: Enter new value or nothing to leave unchanged'
  $defaults.GetEnumerator() | ForEach {
    $v = Read-Host ($_.Name + ' [' + $stats[$_.Name] + ']')  
    if (-Not [string]::IsNullOrWhiteSpace($v)) { $stats[$_.Name] = $v }
  }
}

$stats | ConvertTo-Json | Set-Content $QBSettingsFile

###########################################################################

# OUTPUT PASSPHRASE MODE

if ($IddQd.IsPresent) {
  $passwod = $stats.secret | ConvertTo-SecureString
  $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwod)
  $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  Write-Output $plaintext 
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
  Exit 0
}

###########################################################################

# SETUP ENVIRONMENT FOR BORG

$env:BORG_REPO = $stats.remote
$env:BORG_PASSCOMMAND = [string]::Format(
  'powershell -ExecutionPolicy Unrestricted "{0}" -IddQd',
  $PSCommandPath.Replace('\','/'))
$env:BORG_RSH = [string]::Format('ssh -i "{0}"', (CygPath $SSHKeyFileName))

if ($stats.containsKey('binary')) {
  $env:BORG_REMOTE_PATH = $stats.binary
}

if ($Init.IsPresent) {
  borg.bat init -e repokey
} 

###########################################################################

# MAIN BACKUP SCRIPT

if ($Borg.IsPresent) {
  borg.bat $brgs
} elseif (-Not [string]::IsNullOrWhiteSpace($BackupPath)) {
  $Backup = Get-Item $BackupPath
  $Drive = $Backup.PSDrive.Name
  $BackupNoDrivePath = (Split-Path $Backup.FullName -NoQualifier).Substring(1)
  Announce ('shadowing volume ' + $Drive + ' ... ')
  $ShadowCopyList = (Get-WmiObject -List Win32_Shadowcopy)
  $sc = $ShadowCopyList.Create($Drive + ':\','ClientAccessible');
  if ($sc.ReturnValue -eq 0) {
    Write-Output ('created copy ' + $sc.ShadowID)
    $query = 'SELECT * FROM Win32_ShadowCopy WHERE ID="'+$sc.ShadowID+'"'
    $scobj = Get-WmiObject -Query $query
    if ($scobj.ID -Ne $sc.ShadowID) {
      Write-Error 'fatal: WMI query did not return correct shadow copy'
    } else {
      try {
        $tmpd = [System.IO.Path]::GetTempFileName();
        $link = Join-Path $tmpd $Drive
        Remove-Item $tmpd;
        New-Item -Type directory -Path $tmpd | Out-Null;
        & $env:ComSpec /c mklink /j $link ($scobj.DeviceObject+'\') | Write-Verbose
        if ($LASTEXITCODE -Ne 0) {
          Write-Error 'critical error: unable to link shadow.'
        } else {
          try {
            $relpath = Join-Path $Drive $BackupNoDrivePath
            $logname = (Get-Date).ToString($stats.format)
            $aclfile = ''
            $archive = '::'+$logname
            $logname = $logname+'.log'

            Push-Location $tmpd
            if ($ACLs.IsPresent) {
              Info 'saving permissions to file .acls'
              $aclfile = '.acls'
              IcAcls (Join-Path $tmpd $relpath) /save $aclfile /T /C /Q | Write-Verbose 
            }

            $crgs = ($stats.bflags.split() + $brgs) | Select-Object -Unique 
            borg.bat create $crgs $archive $aclfile $relpath.Replace('\','/') | Tee-Object -Variable l
            if ($Log.IsPresent) {
              Out-File -Append -FilePath (Join-Path $PSScriptRoot $logname) -InputObject $l
            }
            Pop-Location

            if ($Pruned.IsPresent) {
              borg.bat prune $stats.pruned.split()
            }
          } finally {
            Pop-Location
            Info 'deleting linked directory'
            $linkitem=Get-Item $link
            $linkitem.Delete()
            Remove-Item $tmpd -Recurse -Force
          }
        }
      } finally {
        Info 'deleting shadow copy.'
        $scobj.Delete()
      }
    }
  }
}