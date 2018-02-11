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
  [parameter(ParameterSetName='borg',ValueFromRemainingArguments=$True)]
    $BorgArguments,
  [Parameter(ParameterSetName='auto')]
    [switch] $Init,
  [Parameter(ParameterSetName='auto',Position=0,Mandatory=$True)] 
  [ValidateNotNullOrEmpty()]
    [string] $BackupPath
)

$SSHKeyFileName = Join-Path $PSScriptRoot 'qbackup.sshkey'
$QBSettingsFile = Join-Path $PSScriptRoot 'qbackup.json'

$borgbat = Join-Path $PSScriptRoot 'borg.bat'

$qbackup = 'QBACKUP: '

function Announce ([String] $msg) { 
  $stdout=[System.Console]::OpenStandardOutput()
  $buffer=[System.Text.Encoding]::ASCII.GetBytes($qbackup + $msg)
  $stdout.Write($buffer, 0, $msg.Length+$qbackup.Length)
}

function Info ([String] $msg) { 
  Write-Output ($qbackup + $msg)
}

function Quote([String] $msg) {
  return [string]::Format('"{0}"',$msg.Replace('"','\"'))
}

function CygPath([String] $p) {
  $item = Get-Item $p
  $r = (Split-Path $item.FullName -NoQualifier).Substring(1)
  $p = (Join-Path 'cygdrive' (Join-Path $item.PSDrive.Name $r))
  return ('/'+$p.Replace('\','/'))
}

function Borg([String] $command) {
  Info ('borg ' + $command)
  & $env:ComSpec /c ([string]::Format('"{0}" {1}', $borgbat, $command))
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

'remote', 'binary' | ForEach {
  if (-Not $stats.containsKey($_)) {
    $nv = Read-Host ('provide value for setting ' + $_)
    $stats.Add($_, $nv)
  } elseif ($Configure.IsPresent) {
    Write-Output    ('current value for setting ' + $_ + ': ' + $stats[$_])
    $nv = Read-Host ('enter a new value or leave blank')
    if (-Not [string]::IsNullOrWhiteSpace($nv)) {
      $stats[$_] = $nv 
    }
  }
}

$stats | ConvertTo-Json | Set-Content $QBSettingsFile

if ($IddQd.IsPresent) {
  $passwod = $stats.secret | ConvertTo-SecureString
  $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwod)
  $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  Write-Output $plaintext 
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
  Exit 0
}

$env:BORG_REPO = $stats.remote
$env:BORG_PASSCOMMAND = [string]::Format(
  'powershell -ExecutionPolicy Unrestricted "{0}" -IddQd',
  $PSCommandPath.Replace('\','/'))
$env:BORG_RSH = [string]::Format('ssh -i "{0}"', (CygPath $SSHKeyFileName))

if ($stats.containsKey('binary')) {
  $env:BORG_REMOTE_PATH = $stats.binary
}

if ($Init.IsPresent) {
  Borg 'init -e repokey'
} 

if ($Borg.IsPresent) {
  Borg $BorgArguments
} elseif (-Not [string]::IsNullOrWhiteSpace($BackupPath)) {
  $Backup = Get-Item $BackupPath
  $Drive = $Backup.PSDrive.Name
  $BackupNoDrivePath = (Split-Path $Backup.FullName -NoQualifier).Substring(1)
  Announce ('shadowing volume ' + $Drive + ' ... ')
  $ShadowCopyList = (Get-WmiObject -List Win32_Shadowcopy)
  $sc = $ShadowCopyList.Create($Drive + ':\','ClientAccessible');
  if ($sc.ReturnValue -eq 0) {
    Write-Output ('created copy ' + $sc.ShadowID)
    $query = 'SELECT * FROM Win32_ShadowCopy WHERE ID=' + (Quote $sc.ShadowID)
    $scobj = Get-WmiObject -Query $query
    if ($scobj.ID -Ne $sc.ShadowID) {
      Write-Error 'fatal: WMI query did not return correct shadow copy'
    } else {
      try {
        Write-Verbose ('root: ' + $scobj.DeviceObject)
        $tmpd = [System.IO.Path]::GetTempFileName();
        $link = Join-Path $tmpd $Drive
        Write-Verbose ('base: ' + $tmpd)
        Remove-Item $tmpd;
        New-Item -Type directory -Path $tmpd | Out-Null;
        Write-Verbose ('link: ' + $link)
        (&$env:ComSpec /c mklink /j (Quote $link) (Quote ($scobj.DeviceObject+'\'))) | Out-Null 
        if ($LASTEXITCODE -Ne 0) {
          Write-Error 'critical error: unable to link shadow.'
        } else {
          try {
            $relpath = Join-Path $Drive $BackupNoDrivePath
            $archive = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
            Push-Location $tmpd
            Info 'saving permissions to file .acls'
            & IcAcls (Quote (Join-Path $tmpd $relpath)) /save .acls /T /C /Q 2>&1 | Out-Null 
            Borg ([string]::Format('create -C zlib,9 --stats ::{0} .acls "{1}"',
                $archive, $relpath.Replace('\','/') ))
            Pop-Location
            Borg 'prune --keep-daily 30 --keep-weekly 52 --keep-monthly 12 --keep-yearly 20'
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