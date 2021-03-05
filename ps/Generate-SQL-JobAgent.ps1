<#
.SYNOPSIS
Generate SQL Script to create SQL Server Job Agents 

.DESCRIPTION
This script will generate an SQL Script to create SQL Server Job Agent. 
The objective is that you can easily move your SQL Job Agent configuration from one server instance to another

.LOGS
    @Author: Alvin Estrada
             alvin@vinestrada.com
#>
$SQLInstance = "dev/sql-instance"
Get-DbaAgentJob -SqlInstance $SQLInstance | Where-Object { $_.Name -notlike '*Filter String*' -and
                                                           $_.Name -eq 'dev' 
                                                        } | Export-DbaScript -Path "c:\Test\<local folder>\"

# When you want to replace certain text within a Job Agent                                                           
# | Export-DbaScript -Passthru | 
# ForEach-Object {$_.Replace('str1','str2')} | 
# Export-DbaScript -Path "c:\test\<local folder>\"
                                             