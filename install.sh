keyfile=qbackup.sshkey

if [ ! -f "$keyfile" ]; then
  echo '-- generating ssh public key'
  /bin/ssh-keygen -t ed25519 -f "$keyfile" -q -N ""
fi

if [ ! -d "$1" ]; then 
  echo '-- generating python virtual environment'
  /bin/python3 -m venv "$1"
fi

pushd "$1" > /dev/null
source "./bin/activate"
if [[ $(pip list --format=columns | grep -oh borgbackup) = "borgbackup" ]]; then 
  echo "-- borg is already installed."
else 
  if [ ! -f "borg" ]; then 
    git clone https://github.com/borgbackup/borg.git
  fi
  pushd borg > /dev/null
    git checkout master 
    git pull
    git checkout $2
  popd > /dev/null
  pip install cython
  # fix for https://github.com/borgbackup/borg/issues/3597
  pip install msgpack-python==0.5.1 
  pip install -e borg
fi
deactivate
popd > /dev/null