# qBackup

qBackup is a set of scripts to help use [borgbackup] for regular backups on a Windows machine. Y'know. Because [Q] introduces Star Fleet to the Borg? ... Moving on. qBackup has two main components: the installer [`install.ps1`](install.ps1) and the actual backup script [`qbackup.ps1`](qbackup.ps1). The process is designed so that the backup script can be run as e.g. a scheduled task.

## Installation
**Warning.** If you do not have [Cygwin] already installed on your machine, the installer will setup [Cygwin] at the location `c:\cygwin`. Please install [Cygwin] manually beforehand if you wish it to be setup elsewhere: If an existing [Cygwin] installation is found, the installer will use that one. The only other changes to your system made by the installer are limited to the directory in which qBackup resides.

To install qBackup, simply run [`install.ps1`](install.ps1). It will download the [Cygwin] setup executable and use it to install the following [Cygwin] packages:

  - `python3`
  - `python3-devel`
  - `git,openssh`
  - `gcc-g++`
  - `openssl-devel`
  - `liblz4-devel`

It will then hand over to [Cygwin]'s bash to do the following:

  1. generate an SSH keypair in `qbackup.sshkey` and `qbackup.sshkey.pub`, no passphrase.
  2. setup a python3 virtual environment in the folder `venv` and activate it.
  3. clone the borgbackup repository into `venv\borg` and (currently) check out version `1.1.2`.
  4. install cython from the Python package index.
  5. install borgbackup from the local directory `venv\borg`.

*Note:* Currently, it also manually installs the package `msgpack-python` version `0.5.1` as a temporary workaround for [this problem I had](https://github.com/borgbackup/borg/issues/3597).

## The Backup Script

The Syntax of qBackup is as follows:
```
./qbackup.ps1 [-IDDQD] [-Verbose] [-Init] [DIRECTORY]
              [-SetSecret] [-Configure]
```

Here is a brief explanation:
- `-IDDQD` outputs the backup encryption passphrase to stdout. It exists so qBackup can set the `BORG_PASSCOMMAND` environment variable to `qBackup.ps1 -IDDQD`. 
- `-Verbose` will yield more verbose output, it's mostly for debugging.
- `-Init` has to be specified the first time you run qBackup against a remote, it will initialize the borg backup repository.
- `-SetSecret` instructs qBackup to prompt for a new backup encryption passphrase when `-Configure` is specified.
- `-Configure` allows you to configure the borg backend. Example:

```
.\qbackup.ps1 -Configure
provide value for setting remote: ssh://user@backup.server/home/user/backups/
provide value for setting binary: /usr/local/bin/borg
```

All settings are stored in the file `qbackup.json` and except for the DPAPI-encrypted passphrase, all can be edited manually there.

When run, qBackup will create a shadow copy of the disk where `DIRECTORY` is located, then mount this shadow copy in a temporary folder. It will then backup the NTFS permissions of all files in the shadow copy of `DIRECTORY` to a file called `.acls`. Finally, it will run borg against this file and the shadow-copy of `DIRECTORY`, using a timestamp in the format `::YYYY-MM-DD_HH-MM-SS` as the name for this backup in borg.


[borgbackup]: https://github.com/borgbackup
[Cygwin]: https://www.cygwin.com/
[Q]: https://en.wikipedia.org/wiki/Q_(Star_Trek)