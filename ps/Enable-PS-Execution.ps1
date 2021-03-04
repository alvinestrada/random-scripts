<#
    .SYNOPSIS
    This script enable powershell execution

    .DESCRIPTION
    To enable PowerShell script execution please follow the step below:

    1. Open PowerShell Admin console (not ISE)
    2. Run the following PowerShell.

#>

Set-ExecutionPolicy AllSigned -Scope CurrentUser -Force
Set-ExecutionPolicy Default -Scope CurrentUser -Force
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force