#!/bin/bash
set -a

BACKUP_TYPE=${1}                #lvl0, lvl1, archive
ORACLE_SID=${2}                 
BACKUP_MEDIA=${3}               #DISK or TAPE
BACKUP_LIB_PARAM=               #Required when backup_media=TAPE
BACKUP_DISK_DEST=/backup        #Required when backup_media=DISK
COMPRESSED=Y                    #Y or N
RETENTION_POLICY=REDUNDANCY     #REDUNDANCY, RECOVERY_WINDOW, NONE
RETENTION=1                     #Nr of copies of redundancy, nr of days for recovery_window
PARALLEL_DEGREE=4
ORACLE_HOME=/app/oracle/19.3.0
EXCLUDED_TABLESPACES="PDB1:LOG_TABLESPACE"             #Quoted domma separeted list of tablespace names that won't be backuped 
                                                        #eg:    EXCLUDED_TABLESPACES="tbs1 ,tbs2, tbs3"
                                                        #if pdb:EXCLUDED_TABLESPACES="PDB1:TBS1, PDB2:TBS2, P
# TO OVERWRITE THE PARAMETER ABOVE CREATE A FILE env<DB_NAME>.par IN THE SAME DIRECTORY OF THIS SCRIPT WITH THE PARAMETERS TO BE OVERWRITEN



BASE_FILE_DIR=$(dirname "$0")
if [ -f ${BASE_FILE_DIR}/env_${DB_NAME}.par ]; then
    source ${BASE_FILE_DIR}/env_${DB_NAME}.par
fi

CURR_DATE=`date +%Y%m%d%H%M`

read -r DB_NAME DB_LIC_VER BCT_STATUS <<<$(${ORACLE_HOME}/bin/sqlplus -s / as sysdba <<EOF
set pages 0
set head off
set feed off
select 
(select value from v\$parameter where name = 'db_name') as db_name,
(select case when lower(banner) like ('%enterprise%') then 0 else 1 end  from v\$version) as db_lic_version,
(select status from v\$block_change_tracking) as bct_status
from dual;
exit
EOF
)

if [ ${DB_LIC_VER} == "0" ] && [ ${BCT_STATUS} == "DISABLED" ]; then
${ORACLE_HOME}/bin/sqlplus -s / as sysdba <<EOF
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;
exit
EOF
fi

COMMAND_RMAN()
{   
    BACKUP_TYPE=${1}
    BACKUP_DATABASE_CMD="BACKUP INCREMENTAL ${BACKUP_TYPE} AS ${COMPRESSED} BACKUPSET TAG='${BACKUP_TYPE_NO_SPACE}_${CURR_DATE}' 
DATABASE
PLUS ARCHIVELOG TAG='${DB_NAME}_archive_${CURR_DATE}' DELETE INPUT;"
}


if [ ${COMPRESSED,,} == "y" ]; then
    COMPRESSED="COMPRESSED"
elif [ ${COMPRESSED,,} == "n" ]; then
    COMPRESSED=""
else
    COMPRESSED=""
fi

case ${BACKUP_TYPE,,} in 
    "lvl0") 
        COMMAND_RMAN "level 0"
    ;;
    "lvl1")
        COMMAND_RMAN "level 1"
    ;;
    "archive")
        BACKUP_DATABASE_CMD="BACKUP AS ${COMPRESSED} BACKUPSET TAG='archive_${CURR_DATE}' ARCHIVELOG ALL DELETE INPUT;"
    ;;
    *)
        echo "Invalid backup option."
esac

if [ ${BACKUP_MEDIA^^} == "TAPE" ]; then
BACKUP_CONFIGURE_CHANNEL=("CONFIGURE CHANNEL DEVICE TYPE SBT PARMS '${BACKUP_LIB_PARAM}';
CONFIGURE DEFAULT DEVICE TYPE TO 'SBT_TAPE';
CONFIGURE DEVICE TYPE SBT PARALLELISM ${PARALLEL_DEGREE};")
elif [ ${BACKUP_MEDIA^^} == "DISK" ]; then
BACKUP_CONFIGURE_CHANNEL=("CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '${BACKUP_DISK_DEST}/%d_${BACKUP_TYPE_NO_SPACE,,}_%U';
CONFIGURE DEFAULT DEVICE TYPE TO 'DISK';
CONFIGURE DEVICE TYPE DISK PARALLELISM ${PARALLEL_DEGREE};")
else
    echo "Wrong backup type"
fi

BACKUP_CONTROLFILE_CMD="BACKUP CURRENT CONTROLFILE TAG='controlfile_${CURR_DATE}';"

BACKUP_SPFILE_CMD="BACKUP SPFILE TAG='spfile_${CURR_DATE}';"

CROSSCHECK_CMD="CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;"

DELETE_EXPIRED_CMD="DELETE NOPROMPT EXPIRED BACKUP;"

DELETE_OBSOLETE_CMD="DELETE NOPROMPT OBSOLETE;"

if [ ! -d ${LOG_FILE_PATH} ]; then
    mkdir -p ${LOG_FILE_PATH}
fi

IFS=,
EXCLUDE_TABLESPACES=$(for TBS_NAME in ${EXCLUDED_TABLESPACES}; do
    TBS_NAME_CLEAN=$(echo ${TBS_NAME/" "/""} | tr a-z A-Z)
    echo "CONFIGURE EXCLUDE FOR TABLESPACE ${TBS_NAME_CLEAN};"
done)


BACKUP_RETENTION="CONFIGURE RETENTION POLICY TO ${RETENTION_POLICY/"_"/" "} ${RETENTION};"
BACKUP_TYPE_NO_SPACE=${BACKUP_TYPE/" "/"_"}
LOG_FILE_PATH="${BACKUP_DISK_DEST}/log/${DB_NAME}-${BACKUP_TYPE_NO_SPACE}-${CURR_DATE}.log"


echo "run {
SET COMMAND ID TO 'backup-${BACKUP_TYPE_NO_SPACE}';
${BACKUP_CONFIGURE_CHANNEL}
${EXCLUDE_TABLESPACES}
${BACKUP_RETENTION}
${BACKUP_DATABASE_CMD}
${BACKUP_CONTROLFILE_CMD}
${BACKUP_SPFILE_CMD}
}" > /tmp/rman_backup_${DB_NAME}.rcv

echo "run {
SET COMMAND ID TO 'croscheck-backup';
${BACKUP_CONFIGURE_CHANNEL}
${CROSSCHECK_CMD}
${DELETE_EXPIRED_CMD}
${DELETE_OBSOLETE_CMD}
}" > /tmp/rman_crosscheck_${DB_NAME}.rcv


${ORACLE_HOME}/bin/rman target / \
log=${LOG_FILE_PATH}/${DB_NAME}_${BACKUP_TYPE_NO_SPACE}_${CURR_DATE}.log \
cmdfile=/tmp/rman_backup_${DB_NAME}.rcv

${ORACLE_HOME}/bin/rman target / \
log=${LOG_FILE_PATH}/${DB_NAME}_crosscheck_${CURR_DATE}.log \
cmdfile=/tmp/rman_crosscheck_${DB_NAME}.rcv