## Backup rman

Set 3 crontab entries one for with three parameters backup type, oracle_sid and backup media.
e.g.:
```
* * * * * <path>/backup_rman.sh lvl0 orcl DISK
* * * * * <path>/backup_rman.sh lvl1 orcl DISK
* * * * * <path>/backup_rman.sh archive orcl DISK
```
Is also possible to create a file named env_<DB_NAME>.par in the same directory of the script, so you won't need to pass any parameter beside the backup level/type.
