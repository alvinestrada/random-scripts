<#
.SYNOPSIS
    Copy content of a table into another table
.DESCRIPTION
    Copy content of a table into another table  
    
.REQUIREMENTS
  DBATools   
  Install-Module -Name DBATools -Scope CurrentUser  

  SqlServer
  Install-Module -Name SqlServer -Scope CurrentUser 

  Yaml Module
  Install-Module -Name yaml -Scope CurrentUser 

.NOTES
    Tags: Migration, Data Pipeline, Export
    Author: Alvin Estrada | alvin@vinestrada.com 
    License: MIT https://opensource.org/licenses/MIT
.EXAM
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $config = "config.yml"
)

Import-Module -Name dbatools
Import-Module -Name SqlServer
Import-Module -Name powershell-yaml

# Determine current script location
$CurrentDir = $PSScriptRoot
$config_file = $config

# ============== MAIN BLOCK ==========================
# Set-Config-Vars
# Read yAML config file
$cf = "$CurrentDir\$config_file"
Write-Host $cf

# Write-Host "config file is $cf"
$config_conent = Get-Content $cf 
$content = ''

# Let us assign yaml value into variables
foreach ($line in $config_conent) { $content = $content + "`n" + $line }
$yaml = ConvertFrom-Yaml $content

$env                = $yaml.env
$pcd_server         = $yaml.pcd_server_name
$pcd_database       = $yaml.pcd_database
$pcd_user           = $yaml.pcd_user
$pcd_password       = $yaml.pcd_password

$date_interval      = $yaml.interval
$date_numbers       = $yaml.interval_number
$log_loc            = $yaml.log_location
$dateadd_dt         = $yaml.date_time

$log_time = Get-Date -Format "MMddyyyy_hhmmss"
$log_file = "{0}\MID_Data_Log_{1}.log" -f $log_loc, $log_time 
Write-Host "--> LogFile : $log_file"

$log_date = Get-Date -Format "MM-dd-yyyy hhmmss"
"Data Load start : $log_date" | Out-File $log_file -Append -Force
Write-Host "--> Data Load start : $log_date"

# Setup Credential for PCD database
$pcd_encrypted_pwd = ConvertTo-SecureString -String $pcd_password -AsPlainText -Force
$pcd_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pcd_user, $pcd_encrypted_pwd

# Initiate a batch 
# $idflowinstance = Invoke-SQLcmd -ServerInstance $env:dataserver -query $SQLQuery -Username $env:user -Password $env:pass -Database $env:database
$batch_sql = "INSERT INTO dbo.MID_Batch (job_name, run_type, run_desc) VALUES('MID Data Load', 'BULK Load', 'PowerShell'); SELECT SCOPE_IDENTITY();" 
Write-Verbose $batch_sql

$batch_parms = @{
    ServerInstance = $pcd_server
    Database       = $pcd_database
    Credential     = $pcd_creds
    Query          = $batch_sql
    
}
$retsult_batch_id = Invoke-Sqlcmd @batch_parms  
$batch_id = $retsult_batch_id[0]  

$msg = "--> Current Batch #: $batch_id" 
$msg  | Out-File $log_file -Append -Force
Write-Host $msg

# Fetch List of tables we want to copy the content from
$parms = @{
    ServerInstance = $pcd_server
    DatabaseName   = $pcd_database
    Credential     = $pcd_creds
    SchemaName     = "dbo"
    ViewName      = "vw_Select_Data_Load"
}
# recordSet a.k.a DataFrame
$source_table_names = Read-SqlViewData @parms 
# $source_table_names = Read-SqlTableData @parms

# Loop through the table listing we want to copy
Foreach ($table_name in $source_table_names) {

    # Write-Host $table_name
    $target_env          = $table_name.target_stage

    # Write-Host $target_env
    # skip this row if its not the target environment
    if ($target_env -ne $env) { continue }
    # Write-Host "Lets do it"

    $table_id            = $table_name.tab_id
    $source_sql_instance = $table_name.source_sql_instance
    $source_user         = $table_name.source_user_name   
    $source_password     = $table_name.source_pwd
    $source_database     = $table_name.source_database
    $source_table_names  = $table_name.source_table_name
    
    $destination_sql_instance = $table_name.target_sql_instance
    $destination_user         = $table_name.target_user_name   
    $destination_password     = $table_name.target_pwd
    $destination_database     = $table_name.target_database
    $destination_table        = $table_name.target_table_name

    $IsActive                 = $table_name.ready_for_import
    $IsPartial_Load           = $table_name.iterative_run  

    # If the current table require an iterative run, please read this comment carefully to understand
    # how this will work.
    # Please Note: if you are using CURRENT_TIMESTAMP please ensure that your where clause have this format
    #  Default syntax for iterative run
    #    > WHERE <key_column> betweeN DATEADD({0}, {1}, '{2}') AND '{3}'
    #  Else if you want to use CURRENT_TIMESTAMP
    #    > WHERE <key_column> betweeN DATEADD({0}, {1}, CURRENT_TIMESTAMP) AND CURRENT_TIMESTAMP
    if ($dateadd_dt -eq 'CURRENT_TIMESTAMP') {
        
        $sql_where = $table_name.where_clause -f $date_interval, $date_numbers
    } else {
        # $dt = "{yyyy-MM-dd}" -f $dateadd_dt
        $sql_where = $table_name.where_clause -f $date_interval, $date_numbers,  $dateadd_dt, $dateadd_dt
    }
    
    # Setup Credential for both source and target SQL instances
    $src_encrypted_pwd = ConvertTo-SecureString -String $source_password -AsPlainText -Force
    $src_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $source_user, $src_encrypted_pwd
    
    $tar_encrypted_pwd = ConvertTo-SecureString -String $destination_password -AsPlainText -Force
    $tar_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $destination_user, $tar_encrypted_pwd
    
    try {
        if ($IsActive -eq 1 ) {

            $msg = " --> Copying Table Name: $($source_table_names)"
            $msg | Out-File $log_file -Append -Force
            Write-Host $msg
            

            if ($IsActive -eq 1 ) { 
                    $msg = " --> Where Syntax : $($table_name.where_clause)" 
                    $msg | Out-File $log_file -Append -Force
                    Write-Host $msg

                    $msg = " --> SQL where clause: $( $sql_where )"
                    $msg | Out-File $log_file -Append -Force
                    Write-Host $msg
                }
            $msg =  "Copying $source_sql_instance.$source_database.$source_table_names to $destination_sql_instance.$destination_database.$destination_table"
            $msg | Out-File $log_file -Append -Force
            Write-Verbose $msg
            
            if ($IsPartial_Load -eq 1) {

                $sql = "SET DATEFORMAT dmy;  Select * from {0} {1}" -f $source_table_names, $sql_where
                $msg = "  --> Partial SQL: $($sql)"
                $msg  | Out-File $log_file -Append -Force
                Write-Host $msg
                


                # Write-Host $sql
                $Copy_Parms = @{
                    SqlInstance              = $source_sql_instance
                    SqlCredential            = $src_creds
                    Database                 = $source_database 
                    Table                    = $source_table_names  
                    Query                    = $sql
                    Destination              = $destination_sql_instance 
                    DestinationSqlCredential = $tar_creds
                    DestinationDatabase      = $destination_database 
                    DestinationTable         = $destination_table 
                    BatchSize                = 100000        
                    Truncate                 = $True
                }
            }
            else { 
                $Copy_Parms = @{
                    SqlInstance              = $source_sql_instance
                    SqlCredential            = $src_creds
                    Database                 = $source_database 
                    Table                    = $source_table_names  
                    Destination              = $destination_sql_instance 
                    DestinationSqlCredential = $tar_creds
                    DestinationDatabase      = $destination_database 
                    DestinationTable         = $destination_table 
                    BatchSize                = 100000        
                    Truncate                 = $True   
                } 
            }
            # -------------------- Insert into Batch Process Log ----------------------------- #
            $INS_batch_process_sql = "INSERT INTO dbo.MID_Batch_Process_Log( batch_id, table_sequence, table_id, 
                                                                             phase_name,  source_table_name, 
                                                                             destination_table_name)
                                            VALUES({0},{1},{2},'Data Load','{3}', '{4}'); SELECT SCOPE_IDENTITY();    
                                    " -f $batch_id, $table_id, $table_id, $source_table_names, $destination_table
            # Write-Host $INS_batch_process_sql
            # $INS_batch_process_sql | Out-File $log_file -Append -Force
            $batch_parms = @{
                ServerInstance = $pcd_server
                Credential     = $pcd_creds
                Database       = $pcd_database
                Query          = $INS_batch_process_sql
            }
            $process_batch_id = Invoke-Sqlcmd @batch_parms -Verbose
            # -------------------- End of Insert into Batch Process Log ----------------------------- #
           
            $results = Copy-DbaDbTableData @Copy_Parms  -WarningVariable tablewarning 
            $results | Out-File $log_file -Append -Force

            if ($null -eq $results) {
                $row_count      = 0
                $elapsed_time   = 0
            } else {
                $row_count      = $results.RowsCopied
                $elapsed_time   = $results.Elapsed 
            }
            # ----- UPDATE Batch Process Log -----------------
            $UPD_sql =  "UPDATE t
                            SET t.row_count = {0},
                                t.end_datetime = SYSDATETIME()
                           FROM dbo.MID_Batch_Process_Log AS t
                          WHERE t.batch_id = {1}
                            AND t.log_id = {2}
                        " -f $row_count, $batch_id[0], $process_batch_id[0]
            $batch_parms = @{
                ServerInstance = $pcd_server
                Credential     = $pcd_creds
                Database       = $pcd_database
                Query          = $UPD_sql
            }
            Invoke-Sqlcmd @batch_parms
            # ----- End of UPDATE Batch Process Log -----------------
            $msg = "     ================================== `n"
            if ($null -eq $results) {
               if ($tablewarning) {
                   $msg += "     Warning Message: {0}" -f $tablewarning
               }
               $msg += "     Number of Rows Copied: 0" 
               $msg += "`n      Elapsed Time: 0" 
            
            } else {
                # $msg = "Source: {0}.{1}.{2}.{3}" -f $results.SourceInstance,  $results.SourceDatabase, $results.SourceSchema, $results.SourceTable
                $msg += "     Number of Rows Copied: {0}" -f  $results.RowsCopied
                $msg += "`n      Elapsed Time: {0}" -f $results.Elapsed
            }
            $msg += "`n     =================================="           
            $msg | Out-File $log_file -Append -Force
            Write-Host $msg
        } else {
            Write-Host " --> Skipping Table Name: $($source_table_names)"
        }
    }
    catch {
        Write-Warning $Error[0]
        $Error[0] | Out-File $log_file -Append -Force
    }
} # end of main for loop


$log_date = Get-Date -Format "MM-dd-yyyy hhmmss"
$msg = "--> Data Load End : $log_date"
$msg | Out-File $log_file -Append -Force
Write-Host $msg
