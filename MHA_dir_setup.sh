#!/bin/bash
# dummy test comment 2025_11_07
# test pull message on github

if [ ! -e "$(pwd)/.env.ini" ]; then
  echo "[Failed] Cannot find .etv.ini file !!! Please check file location."
  exit 1;
fi

source $(pwd)/.env.ini


home_dir="/home/maria"
mha_dir="/MHA/mha"

dirs=(
  "$mha_dir/logs"
  "$mha_dir/conf"
  "$mha_dir/remote"
  "$mha_dir/scripts"
  "$mha_dir/work"
  "$mha_dir/work/mhatest"
  "$mha_dir/remote/mhatest"
)

echo "=== Directory Created Start ==="

if [ ! -d "${mha_dir}" ]; then 
  mkdir -p ${mha_dir}
else  
  echo "Already created ${mha_dir} directory. -> Passed"
fi

for dir in "${dirs[@]}"; do
  parent_dir=$(dirname "$dir")

  if [ ! -d "$parent_dir" ]; then
    echo "No such Parent Directory: $parent_dir -> Passed"
    continue
  fi

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    echo "Directory created Successfully: $dir"
  else
    echo "Already exists directory: $dir"
  fi
done

echo "=== Configure permisson and grant options ==="

if [ -e "$(pwd)/master_ip_online_change.txt" ] && [ -e "$(pwd)/master_ip_online_change.txt" ]; then
  echo "[INFO] Moved from $(pwd) to ${mha_dir} directory" 
  mv "$(pwd)/master_ip"* ${mha_dir}/scripts/
else
  echo "[Warning] Cannot find $(pwd)/master_ip_online-change.txt and $(pwd)/master_ip_failover.txt. Please check your file location -> Passed"
fi

if [ -e "$(pwd)/mha.cnf" ]; then
  mv "$(pwd)/mha.cnf" "${mha_dir}/conf/mha.cnf"
  echo "[Info] Moved from $(pwd)/mha.cnf to ${mha_dir}/conf/mha.cnf successfully."
else
  echo "[Warning] Cannot find $(pwd)/mha.cnf. -> Passed "
fi



# /mha 권한 설정
if [ -d $mha_dir ]; then
  chown -R maria.dba $mha_dir
  chmod -R 750 $mha_dir
else
  echo "[Warning] $mha_dir No such file or directory. -> Passed"
fi

# perl 바이너리
if [ -f /usr/bin/perl ]; then
  chmod 755 /usr/bin/perl
  chmod +x /usr/bin/perl
else
  echo "[Warning]: /usr/bin/perl No such file or directory. -> Passed"
  echo "[Warning]: if you not install MHA-node.rpm, Please run this script after install the MHA.rpm. "
fi

# perl 라이브러리 디렉토리들
for perl_dir in /usr/local/share/perl5/ /usr/lib64/perl5/ /usr/share/perl5/; do
  if [ -d "$perl_dir" ]; then
    chmod -R 755 "$perl_dir"
    echo "[Info] Permission config successfully: $perl_dir"
  else
    echo "[Warning] No such file or directory - $perl_dir -> Passed"
  fi
done

echo "=== Script finished ==="
