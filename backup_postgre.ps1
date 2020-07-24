#############################################
## PostgreSQL base backup automation
## Author: Christian Hann
## Date : 20.04.2017
#############################################

# path settings
$BackupRoot = 'Y:\meddixPACS\Postgre';
$BackupLabel = (Get-Date -Format 'yyyy-MM-dd_HHmmss');

# pg_basebackup settings
$PgBackupExe = 'C:\Program Files\PostgreSQL\9.4\bin\pg_basebackup.exe';
$PgUser = 'postgres';

# set environment-variable for postgre-password
$env:PGPASSWORD='password_here';

# log settings
$EventSource = 'pg_basebackup';

# log erros to Windows Application Event Log
function Log([string] $message, [System.Diagnostics.EventLogEntryType] $type){
    if (![System.Diagnostics.EventLog]::SourceExists($EventSource)){
        New-Eventlog -LogName 'Application' -Source $EventSource;
    }
    Write-EventLog -LogName 'Application' -Source $EventSource -EventId 1 -EntryType $type -Message $message;
}

# check free space based on last backup size if destination is local
function CheckDiskSpace([string] $backupRoot){
    $currentDrive = Split-Path -qualifier $backupRoot;
    $logicalDisk = Get-WmiObject Win32_LogicalDisk -filter "DeviceID = '$currentDrive'";

    if ($logicalDisk.DriveType -eq 3){
        $freeSpace = $logicalDisk.FreeSpace;
        $lastBackup = Get-ChildItem -Directory $backupRoot | sort CreationTime -desc | select -f 1;
        $lastBackupDir = Join-Path $backupRoot $lastBackup;
        $totalSize = Get-ChildItem -path $lastBackupDir | Measure-Object -property length -sum;

        if($totalSize.sum -ge $freeSpace){
            $sizeMB = "{0:N2}" -f ($totalSize.sum / 1MB) + " MB";
            $spaceError = "Not enough free space to backup on $backupRoot last backup $lastBackup was $sizeMB";
            Log $spaceError Error;
            Exit 1;
        }
    }
}

$BackupDir = Join-Path $BackupRoot $BackupLabel;
$PgBackupErrorLog = Join-Path $BackupRoot ($BackupLabel + '-tmp.log');

# check free space
CheckDiskSpace $BackupRoot;

# create backup dir
New-Item -ItemType Directory -Force -Path $BackupDir;

# execution time
$StartTS = (Get-Date);

# start pg_basebackup
try
{
    Start-Process $PgBackupExe -ArgumentList "-D $BackupDir", "-Ft", "-z", "-x", "-R", "-U $PgUser" -Wait -NoNewWindow -RedirectStandardError $PgBackupErrorLog;
}
catch
{
    Write-Error $_.Exception.Message;
    Log $_.Exception.Message Error;
    Exit 1;
}

# check pg_basebackup output
If (Test-Path $PgBackupErrorLog){
    $errors = Get-Content $PgBackupErrorLog;
    If($errors -eq $null){
        Log $errors Error;
    }
    Remove-Item $PgBackupErrorLog -Force;
}

# Log backup duration
$ElapsedTime = $(get-date) - $StartTS;
Log "Backup done in $($ElapsedTime.TotalMinutes) minutes" Information;
