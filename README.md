# qBackup

qBackup is a set of scripts to help use [borgbackup] for regular backups on a Windows machine. Y'know. Because [Q] introduces Star Fleet to the Borg? ... Moving on. qBackup has two main components: the installer [`install.ps1`](install.ps1) and the actual backup script [`qbackup.ps1`](qbackup.ps1). The process is designed so that the backup script can be run as e.g. a scheduled task.

## Installation

### Important Warning 
**qBackup requires a native Cygwin to be installed, i.e. a 64bit Cygwin on 64bit machines. Whenever I refer to Cygwin in this document, I refer to the native version. Currently, qBackup supports only 64bit systems. Feel free to fix this in a PR if you have a 32bit system.**

If you do not have [Cygwin] already installed on your machine, the installer will setup [Cygwin] at a location of your choice. You can also pass the option `-CygwinPath C:\cygwin` to the installer to request installation to `C:\cygwin`. If an existing [Cygwin] installation is found, the installer will still detect it and prompt whether to use it. 

The only other changes to your system made by the installer are limited to the directory in which qBackup resides.

### How to Install
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

You can call qBackup in one of the following ways:

#### `qbackup.ps1 -IDDQD` 
This command outputs the backup encryption passphrase to stdout. It exists so qBackup can set the `BORG_PASSCOMMAND` environment variable to `qBackup.ps1 -IDDQD`. 

#### `qbackup.ps1 [-SetSecret] -Configure` 
The qBackup configuration is stored in a JSON file called `qbackup.json`. If the file does not exist or values are missing from it, the following default values are used:
```json
{
    "binary":  "borg",
    "bflags":  "--compression zlib,9 --stats --list --filter=ME",
    "format":  "yyyy-MM-dd_HH-mm-ss",
    "pruned":  "--keep-daily 30 --keep-weekly 52 --keep-monthly 12 --keep-yearly 20"
}
```
It also contains the value `remote`, which stores the URL to your remote backup location, i.e. a value similar to
```
ssh://user@backup.server/home/user/backups/
```
The encryption passphrase for the remote backup is stored as a DPAPI-encrypted string in the field `secret` of this json file. Furthermore:
- `binary` stores the *remote* path to your borg executable.
- `bflags` are parameters passed to the borg command for each **create** operation.
- `format` is the format for the remote backup archive name and for the local logfile. The remote backup will have the name `::format` while the local log files will have the name `format.log`.
- `pruned` contains the parameters passed to each **prune** operation.

The command `-Configure` is a (debatably) convenient way to change these settings, but you can also just go ahead and edit the json file, of course. Notably however, the only way to really change the stored encryption key is by calling `-Configure` with the `-SetSecret` option.

#### `qbackup.ps1 -Borg [BORGARGS]` 

Simply run borg with the specified arguments. The `BORG_REPO`, `BORG_PASSCOMMAND`, `BORG_RSH` and `BORG_REMOTE_PATH` environment variables will be set, so you can e.g. simply call `qbackup.ps1 -Borg list` to list your remote archives.

#### `qbackup.ps1 [-ACLs] [-Log] [-Pruned] [-Init]  DIRECTORY [BORGARGS]`

When run, qBackup will create a shadow copy of the disk where `DIRECTORY` is located, then mount this shadow copy in a temporary folder. If `-ACLs` is specified, it will backup the NTFS permissions of all files in the shadow copy of `DIRECTORY` to a file called `.acls`. 

The script will then backup the files from the shadow copy using the **create** operation of borg. The borg archive name  is derived from the current date and time according to the `format` setting. All aditional parameters from `BORGARGS` as well as those from the `bflags` setting will also be passed to this `borg` call. If the `-Log` option is specified, qBackup will create a logfile containing the output of `borg`. 

If the `-Pruned` option is specified, qBackup will then prune the remote archive according to the `pruned` setting. 

Finally, the `-Init` option has to be set if and only if you run qBackup against a remote for the first time.


[borgbackup]: https://github.com/borgbackup
[Cygwin]: https://www.cygwin.com/
[Q]: https://en.wikipedia.org/wiki/Q_(Star_Trek)