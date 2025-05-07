#!/bin/bash

#set -x

if [ $# -eq 0 ]; then
	echo "[Failed] : You must be input --version argument. Please execute after --version argument"
	echo "[Failed] Install aborted"
	exit 1;
fi


group="dba"
user="maria"
home="/home/${user}"


basedir="/MARIA"
datadir="/MARIA_DATA"
logdir="/MARIA_LOG"

if [ ! -e /home/${user} ]; then
	groupadd ${group}
	useradd -g ${group} ${user}
	echo "Please set password manually: ${user}.${group}"

else 
	echo "[Info] Already created ${user}.${group}. Passed for user creating phase"

fi


#echo "$#"
for arg do

        val=`echo "$arg" | sed -e 's/^[^=]*=//'`
	#### --help ####
        if [ "${arg}" == "--help" ] || [ "${arg}" == "help" ]; then

			echo "##################################################################################"
			echo ""
			echo " Please use follow command : $(pwd)/MariaDB_install.sh --<argument>=<value> ..."
			echo " --help "
			echo " --version= "
			echo " --basedir= "
			echo " --datadir= "
			echo " --bindir= "
			echo " --logdir "

			echo ""
			echo "##################################################################################"
			exit 1;
        fi

        case "$arg" in
			--version=*)
			version="${val}"  # 추출한 값 username 변수에 저장
			;;

			--basedir=*)
			basedir="${val}"
			;;

			--datadir=*)
			datadir="${val}"
			;;

			--bindir=*)
			bindir="${val}"
			;;

			--logdir=*)
			logdir="${val}"
			;;


			## set exception(Invalid arguments)
			*)
			echo "##################################################################################"
			echo ""
			echo " Invalid arguments: $arg                                                        "
			echo " Please use follow command : $(pwd)/MariaDB_install_online.sh --help                   "
			echo ""
					echo "##################################################################################"
			exit 1;
			;;
        esac
done

if [ ! -e "${home}/Maria*" ] || [ ! -e "${home}/maria*" ] || [ ! -e "${home}/my.cnf" ]; then	
	echo "Moved MariaDB files from $(pwd) to ${home}"
	mv Maria* maria* my.cnf /home/${user}

fi

MariaDB_rpms=(${home}/MariaDB-*.rpm)
MariaDB_engine="mariadb-${version}-linux-systemd-x86_64"
MariaDB_dependencies="${home}/mariadb_rpms/"
bindir="${basedir}/${MariaDB_engine}/bin"


#mysql_server="${basedir}/${MariaDB_engine}/support-files/mysql.server"
mysql_server="/etc/init.d/mariadb"

mysql_secure_installation="${bindir}/mysql_secure_installation"
config_file="/etc/my.cnf"
engine_dir="${basedir}/mariadb"

if [ ! -e "${home}/${MariaDB_engine}.tar.gz" ] && [ ! -e "${home}/${MariaDB_engine}" ]; then
        echo "[Warning] : Cannot find ${home}/${MariaDB_engine} file. Checking ${basedir} directoy..."

	if [ ! -e "${basedir}/${MariaDB_engine}.tar.gz" ] && [ ! -e "${basedir}/${MariaDB_engine}" ]; then
		echo "[Failed] Cannot find ${basedir}/${MariaDB_engine} file. Please check engine file first... "
		echo " Process aborted "
		exit 1;
	
	
	elif [ -e "${basedir}/${MariaDB_engine}.tar.gz" ] || [ -e "${basedir}/${MariaDB_engine}" ]; then
		echo "[Successful] ${MariaDB_engine} file is in ${basedir} directory."

	fi

elif [ -e "${home}/${MariaDB_engine}.tar.gz" ] || [ -e "${home}/${MariaDB_engine}" ]; then
	echo "[Successful] ${MariaDB_engien} file is in ${home} directory."

fi



maria_dir=(
        "${basedir}"
        "${datadir}"
        "${logdir}"
        "${datadir}/DATA"
        "${datadir}/tmp"
        "${logdir}/audit"
        "${logdir}/binary"
        "${logdir}/error"
        "${logdir}/slow"
        "${logdir}/relay"
)

#logging_file="/home/${user}/maria_dir_setup.log"

echo "##### this script setting for ${user}.${group}. you must be check your users #####"
echo "##### directory created and logging start #####"
echo "##### Currnet group_name : ${group}, user : ${user} #####"
echo "##### please check ${logging_file} #####"
echo "##### Current version : ${version} #####"



echo "##### Start install MariaDB packages #####"
echo "### Path Configure ###"
echo "### Current path : $(pwd) ###"
echo "### MariaDB_rpms : " "${MariaDB_rpms[@]} ###"
echo "### MariaDB_engine : ${MariaDB_engine} ###"
echo "### MariaDB_dependencies : ${MariaDB_dependencies} ###"
echo "### basedir=${basedir}, datadir=${datadir}, bindir=${bindir}, logdir=${logdir}"


for dir in "${maria_dir[@]}"; do
        echo "$dir"
        if [ ! -e ${dir} ]; then
                mkdir ${dir}

        else
                echo "[Warning] ${dir} already exists. Passing directory create..."
        fi
        chown -R ${user}.${group} "${dir}"
done


#echo "##################################################################"


echo "##### Start install MariaDB packages #####"
#exit 1;

##########################################################################


echo "##### Step 1-1. install dependencies MariaDB-rpms #####"
dnf localinstall "${MariaDB_rpms[@]}" --downloadonly --destdir ${MariaDB_dependencies}

if [ -d "${MariaDB_dependencies}" ]; then 
	eval "rpm -ivh ${MariaDB_dependencies}*.rpm"

else
	echo "Cannot find ${MariaDB_dependencies} directory. Please check directory"
	exit 1;
fi

echo "##### Step 1-2. install Maria-DB package rpm #####"

if [ -f "${MariaDB_rpms[0]}" ]; then 
	eval "rpm -Uvh ${home}/MariaDB-*.rpm"

else
	echo "Cannot find ${MariaDB_rpms}. Please check file path"
	exit 1;

fi

echo "##### Step 2. Maria-DB engine install #####"

if [ -d "${basedir}" ]; then
	mv "${home}/${MariaDB_engine}.tar.gz" "${basedir}/${MariaDB_engine}.tar.gz"
	tar -zxf "${basedir}/${MariaDB_engine}.tar.gz" -C "${basedir}"
	echo "### Uncompressed ${basedir}/${MariaDB_engine} completed. ###"
	ln -s "${basedir}/${MariaDB_engine}" "${engine_dir}"

else 
	echo "Cannot find ${basedir} directory. Please check your base directory"
	exit 1;
fi


echo "##### Step 3. Grant my.cnf configure file #####"

if [ -f "/etc/my.cnf" ] && [ -f "${home}/my.cnf" ]; then
	mv /etc/my.cnf "${home}/my.cnf.old"
	cp "${home}/my.cnf" /etc/my.cnf
	chmod 640 /etc/my.cnf
	chown "${user}.${group}" /etc/my.cnf
	echo "### my.cnf copy successful. Please check configuration ###"
fi

echo "##### Step 4. Creating mariadbd in /etc/init.d directory #####"

if [ -f "${engine_dir}/support-files/mysql.server" ]; then
	cp "${engine_dir}/support-files/mysql.server" /etc/init.d/mariadb
	chmod 750 /etc/init.d/mariadb
	chown "${user}.${group}" /etc/init.d/mariadb

	echo "### /etc/init.d/mariadb copy successful ###"
	echo "### You must be config /etc/init.d/mariadb files(basedir, datadir...) ###"
fi

echo "##### MariaDB install done. Please check my.cnf and executing scripts/mariadb-install-db --defaults-file=/etc/my.cnf #####"

echo "##### Creating MariaDB system table phase #####"
if [ -e ${engine_dir}/scripts/mariadb-install-db ]; then
	${engine_dir}/scripts/mariadb-install-db --defaults-file=/etc/my.cnf
	echo "[INFO] System table create successful"
elif [ -e ${engine_dir}/scripts/mysql_install_db ]; then
	echo "[INFO] Cannot find ${engine_dir}/scripts/mariadb-install-db scripts..."
	echo "[INFO] Redirecting ${engine_dir}/scripts/mysql_install_db. Running ... " 
	${engine_dir}/scripts/mysql_install_db --defaults-file=/etc/my.cnf
	echo "[INFO] System table create successful"

else
	echo "[Failed] System table create failed. you must be create manually. "
fi



#### MYSQL.SERVER ####
echo " ###################################################################### "
echo " ### SET mysql.sever ### "
echo " ### mysql.server => ${mysql_server} "
## SET BASEDIR=
sed -i "s|^basedir=[[:space:]]*\$|basedir=${basedir}/${MariaDB_engine}|" ${mysql_server}

## SET DATADIR=
sed -i "s|^datadir=[[:space:]]*\$|datadir=${datadir}|" ${mysql_server}

## SET UMASK=0640
if grep -qE "^export UMASK=[[:space:]]*$" "${mysql_server}"; then
    sed -i "s|^export UMASK=[[:space:]]*\$|export UMASK=0640|" ${mysql_server}
else
    # 없으면 추가
    sed -i "/^datadir=/a export UMASK=0640" ${mysql_server}

fi

## SET UMASK_DIR=0750
if grep -qE "^export UMASK_DIR=[[:space:]]*$" "${mysql_server}"; then
    sed -i "s|^export UMASK_DIR=[[:space:]]*\$|export UMASK_DIR=0750|" ${mysql_server}
else
    # 없으면 추가
    sed -i "/^datadir=/a export UMASK_DIR=0750" ${mysql_server}

fi


echo " ### done. ### "
echo " ###################################################################### "




#### MYSQL_SECURE_INSTALLATION ####

echo " ###################################################################### "
echo " ### SET mysql_secure_installtion ### "
echo " ### mysql_secure_installation => ${mysql_secure_installation} "


sed -i "s|^basedir=[[:space:]]*\$|basedir=${basedir}/${MariaDB_engine}|" ${mysql_secure_installation}

## SET BINDIR
if grep -qE "^bindir=[[:space:]]*$" "${mysql_secure_installation}"; then
    sed -i "s|^bindir=[[:space:]]*\$|bindir=${bindir}|" ${mysql_secure_installation}
else
    # 없으면 추가
    sed -i "/^basedir=/a bindir=${bindir}" ${mysql_secure_installation}

fi

## SET DEFAULTS-FILE
if grep -qE "^defaults_file=[[:space:]]*$" "${mysql_secure_installation}"; then
    sed -i "s|^defaults_file=[[:space:]]*\$|defaults_file=${config_file}|" ${mysql_secure_installation}
else
    # 없으면 추가
    sed -i "/^basedir=/a defaults_file=${config_file}" ${mysql_secure_installation}

fi

echo "##### Next Step #####"
echo "### 1. After checking ${config_File}. Running mariadb process. Please use this command => service mariadb start ###"

echo "### 2. Please setting up bin/mysql_secure_installation ###"
echo "### 2-1. If you need configure mysql_secure_installation, please execute this script. => ${mysql_secure_installation} ###"


echo "##### Script done. #####"
