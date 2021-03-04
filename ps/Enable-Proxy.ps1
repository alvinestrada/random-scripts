<#
    .SYNOPSIS
    This script enable/disable internet proxy settings

    .DESCRIPTION
    with this script users with special permission can automatically enable/disable their internet
    proxy settings in their laptop

    .EXAMPLE
    - .\Enable-Proxy.ps1
#>
function Show-Menu
{
<#
.SYNOPSIS
    Basic menu
.DESCRIPTION
#>
[CmdletBinding()]
     param (
           [string]$Title = 'Enable/Disable Windows Web Proxy'
     )
     begin { cls }
     process {
         Write-Host "================ $Title ================"
         Write-Host -foregroundcolor "Green"
         Write-Host ""
         Write-Host "Please select one of the options:"
         Write-Host ""
         Write-Host "1: Enable Windows Web Proxy."
         Write-Host "2: Disable Windows Web Proxy"
         Write-Host "3: Set Web Proxy Server"
	     Write-Host "4: Show current settings"
         Write-Host ""

         Write-Host "Q: Press 'Q' to quit."
     }
     end {}
}

# ---- Main Block --- #
do
{
     Show-Menu
     $input = Read-Host "Please make a choice"

     switch ($input)
     {
           '1' {
                cls
                'The Web Proxy is now enabled!'
                set-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -value 1
           } '2' {
                cls
                'The Web Proxy is now disabled!'
                set-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -value 0
           } '3' {
                cls
                'Please fill in the proxy server!'
				$ProxyServer = Read-Host -Prompt 'proxy.example.org:8080'
				'Proxy Server is set!'
                set-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -Value "$ProxyServer"
           } '4' {
                cls
                'Current Settings'
				'ProxyEnable: 1 = Enabled, 0 = Disabled'
				get-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer,ProxyEnable	   
		   } 'r' {
                cls
                'The Computer will be rebooted right now.. I will be back, like terminator'
                Restart-computer -Force
           } 'q' {
                return
           }
     }
     pause
}
until ($input -eq 'q')