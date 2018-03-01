Param( [string] $CygwinPath )

$borg_env = 'venv'
$borg_ver = '1.1.2'

$Web = New-Object System.Net.WebClient

$cyg_inst = $true
$cyg_pack = 'python3,python3-devel,git,openssh,gcc-g++,openssl-devel,liblz4-devel'
$cyg_repo = 'https://linux.rz.ruhr-uni-bochum.de/download/cygwin/'
$cyg_temp = $env:TEMP + '\q.cygpkg'

try {
  $ErrorActionPreference = "stop"
  Write-Output '-- looking for existing cygwin path in registry.'
  $cyg_root = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Cygwin\Setup' -Name rootdir).rootdir
  Write-Output('-- found cygwin install here: ' + $cyg_root)
  if ($PSBoundParameters.ContainsKey('CygwinPath')) {
    $replacePath = $null
    while ($replacePath -Eq $null) {
      $yq = Read-Host '-- would you like to use this one rather than the one you specified? [Yn]'
      if ($yq) { $yq = $yq.ToUpper() } else { $yq = 'Y' }
      if ($yq[0] -Eq 'Y') {
        $replacePath = $false
      } elseif ($yq[0] -Eq 'N') {
        $replacePath = $true
      }
    }
    if ($replacePath) {
      $cyg_root = $CygwinPath
    }
  } 
} catch [System.Management.Automation.PSArgumentException], [System.Management.Automation.ItemNotFoundException] {
  if ($PSBoundParameters.ContainsKey('CygwinPath')) {
    $cyg_root = $CygwinPath
    Write-Output('-- nothing found, using: ' + $cyg_root)
  } else {
    $cyg_root = Read-Host('-- please specify a cygwin location [enter nothing to abort]')
    if ($cyg_root -Eq $null) { Exit 0 }
  }
} finally {
  $ErrorActionPreference = "continue"
}

try {
  $cyg_pkg_path = Join-Path $cyg_root 'etc\setup\installed.db'
  if (Test-Path $cyg_pkg_path) {
    $cyg_pkdb = Get-Content($cyg_pkg_path)
    $cyg_inst = $false 
    $cyg_pack.Split(",") | ForEach-Object {
      $package = $_    
      $package_found = $false    
      ($cyg_pkdb).split([Environment]::NewLine) | ForEach-Object { 
        $info=($_).split(' ')
        if ($info[0] -eq $package) {
          $package_found = $true 
        }
      }
      if (-Not ($package_found)) {
        Write-Output('-- package missing: ' + $package)
        $cyg_inst = $true
      }
    }
  } else {
    Write-Output('-- installing fresh cygwin 64 to ' + $cyg_root)
  }
} catch {
  $cyg_inst = $true
}


if ($cyg_inst) { 
  $cygwinsetup = 'setup-x86_64.exe'
  $cygwinsetuppath = (Join-Path $PSScriptRoot $cygwinsetup)

  $carg  = ' --wait --no-shortcuts --delete-orphans --quiet-mode'
  $carg += [string]::Format(' --packages "{0}"', $cyg_pack)
  $carg += [string]::Format(' --site "{0}"', $cyg_repo)
  $carg += [string]::Format(' --root "{0}"', $cyg_root)
  $carg += [string]::Format(' --local-package-dir "{0}"', $cyg_temp)

  Write-Output('-- downloading cygwin setup executable.')
  $Web.DownloadFile('http://cygwin.com/' + $cygwinsetup, $cygwinsetuppath)

  Write-Output('-- starting cygwin installer process.')
  Start-Process -Wait -FilePath $cygwinsetuppath -ArgumentList $carg
} else {
  Write-Output('-- all required packages already installed.')
}

Write-Output('-- handing over to bash.')
& $env:ComSpec /c cygbash.bat --noprofile --norc --login install.sh $borg_env $borg_ver



