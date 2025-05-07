#!/bin/bash

while : 
do
  echo "==========================================================="
  echo "Do you want MHA_HOME variable setting by default ? [ Y || N ] : " 
  echo "Current setting : MHA_HOME = /MHA/mha"
  read aws # stdin
  if [ "${aws}" = "Y" ] || [ "${aws}" = "y" ]; then
    MHA_HOME="/MHA/mha"
    echo "[Info] MHA_HOME = ${MHA_HOME} "
    break
  elif [ "${aws}" = "N" ] || [ "${aws}" = "n" ]; then
    echo "[Info]: Trying to parsing $(pwd)/.env.ini... Checking $(pwd)/.env.ini path."
    if [ ! -e "$(pwd)/.env.ini" ]; then
      echo "[Failed] Cannot find $(pwd)/.env.ini file. Please check your system enviroment."
      echo "[Failed] Aborted..."
      exit 1;
    else
      echo "[Info] Start to parsing $(pwd)/.env.ini... "
      source $(pwd)/.env.ini
      echo "[Info] Setting system variable successfully. MHA_HOME = ${MHA_HOME}"
      break
    fi
  else
    echo "[Warning] Invalid argument ${aws} Please input again..."
  fi
done

dirs=(
  "$MHA_HOME/logs"
  "$MHA_HOME/conf"
  "$MHA_HOME/remote"
  "$MHA_HOME/scripts"
  "$MHA_HOME/work"
  "$MHA_HOME/work/mhatest"
  "$MHA_HOME/remote/mhatest"
)

perl_dirs=(
  "/usr/local/share/perl5"
  "/usr/lib64/perl5"
  "/usr/share/perl5"
)

# Checking perl bianry
if [ ! -f /usr/bin/perl ]; then
  echo "[Failed]: Cannot find perl binary. if you not install MHA-node.rpm, Please run this script after install the MHA... "
  echo "Aborted ..."
  exit 1;

fi

for dir in "${dirs[@]}"; do
  if [ -d "$dir" ]; then
    echo "[Warning]: Directory $dir already exist. It will be passed on directory create phase."
  fi
done

while : 
do
  echo "Do you want to continue directory create and grant phase? [Y || N ]"
  read stdin_value
  if [ "${stdin_value}" = "Y" ] || [ "${stdin_value}" = "y" ]; then
    echo "=== Directory Created Start ==="

    for dir in "${dirs[@]}"; do
      if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "[Info] Directory created successfully: $dir"
      else
        echo "[Warning] Already exists directory: $dir --> Passed"
      fi
    done

    echo "=== Setting permissons and grant options ==="

    ### Moved VIP scripts ### 
    if [ -e "$(pwd)/master_ip_online_change.txt" ] && [ -e "$(pwd)/master_ip_failover.txt" ]; then
      echo "[INFO]: Moved to ${MHA_HOME} directory from $(pwd)/master_ip_online script  " 
      mv "$(pwd)/master_ip_"* ${MHA_HOME}/scripts/
    else
      echo "[Warning]: Cannot find $(pwd)/master_ip_online_change.txt or $(pwd)/master_ip_failover.txt. Please check your file location -> Passed"
    fi

    ### Moving mha.cnf ###
    if [ -e "$(pwd)/mha.cnf" ]; then
      mv "$(pwd)/mha.cnf" "${MHA_HOME}/conf/mha.cnf"
      echo "[Info]: Moved to ${MHA_HOME}/conf/mha.cnf from $(pwd)/mha.cnf successfully."
    else
      echo "[Warning]: Cannot find $(pwd)/mha.cnf. -> Passed "
    fi

    # grant perl binary dirs
    for perl_dir in "${perl_dirs[@]}"; do
      if [ -d "$perl_dir" ]; then
        chmod -R 755 "$perl_dir"
        echo "[Info]: Setting directory permissions successfully: $perl_dir"
      else
        echo "[Warning]: No such file or directory - $perl_dir -> Passed"
      fi
    done
    echo "[Info]: Setting perl binary permission successfully"
    chmod 755 /usr/bin/perl
    break

  elif [ "${stdin_value}" = "N" ] || [ "${stdin_value}" = "n" ]; then
    echo "[Info]: Skipping directory create Phase... "
    echo "=== Script done. ==="
  break

  else
    echo "[Warning] Invalid argument ${stdin_value} Please input again..."
  fi
done
echo "=== Script Done. ==="
