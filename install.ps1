Param( [Switch] $x32 )

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
} catch [System.Management.Automation.PSArgumentException], [System.Management.Automation.ItemNotFoundException] {
  $cyg_root = 'c:\cygwin'
  Write-Output('-- nothing found, using: ' + $cyg_root)
} finally {
  $ErrorActionPreference = "continue"
}

try {
  $cyg_pkdb = Get-Content($cyg_root + '\etc\setup\installed.db')
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
} catch {
  $cyg_inst = $false
}

if ($cyg_inst) { 
  $cygwinsetup = './setup-x86'
  if (!$x32) { $cygwinsetup += '_64' }
  $cygwinsetup += '.exe'

  $carg  = ' --wait --no-shortcuts --delete-orphans --quiet-mode'
  $carg += [string]::Format(' --packages "{0}"', $cyg_pack)
  $carg += [string]::Format(' --site "{0}"', $cyg_repo)
  $carg += [string]::Format(' --root "{0}"', $cyg_root)
  $carg += [string]::Format(' --local-package-dir "{0}"', $cyg_temp)

  Write-Output('-- downloading cygwin setup executable.')
  $Web.DownloadFile('http://cygwin.com/' + $cygwinsetup, $cygwinsetup)

  Write-Output('-- starting cygwin installer process.')
  Start-Process -Wait -FilePath $cygwinsetup -ArgumentList $carg
} else {
  Write-Output('-- all required packages already installed.')
}

Write-Output('-- handing over to bash.')
& $env:ComSpec /c cygbash.bat --noprofile --norc --login install.sh $borg_env $borg_ver



