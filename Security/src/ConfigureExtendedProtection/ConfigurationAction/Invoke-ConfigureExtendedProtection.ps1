﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. $PSScriptRoot\..\DataCollection\Get-ExtendedProtectionConfiguration.ps1
. $PSScriptRoot\..\..\..\..\Shared\Invoke-ScriptBlockHandler.ps1
. $PSScriptRoot\..\..\..\..\Shared\Write-ErrorInformation.ps1

function Invoke-ConfigureExtendedProtection {
    [CmdletBinding()]
    param(
        [object[]]$ExtendedProtectionConfigurations
    )

    begin {
        $failedServers = New-Object 'System.Collections.Generic.List[string]'
        $noChangesMadeServers = New-Object 'System.Collections.Generic.List[string]'
        $updatedServers = New-Object 'System.Collections.Generic.List[string]'
        Write-Verbose "Calling: $($MyInvocation.MyCommand)"
    } process {
        foreach ($serverExtendedProtection in $ExtendedProtectionConfigurations) {
            # Check to make sure server is connected and valid information is provided.
            if (-not ($serverExtendedProtection.ServerConnected)) {
                $line = "Server $($serverExtendedProtection.ComputerName) isn't online to get valid Extended Protection Configuration settings"
                Write-Verbose $line
                Write-Warning $line
                $failedServers.Add($serverExtendedProtection.ComputerName)
                continue
            }

            if ($serverExtendedProtection.ExtendedProtectionConfiguration.Count -eq 0) {
                $line = "Server $($serverExtendedProtection.ComputerName) wasn't able to collect Extended Protection Configuration"
                Write-Verbose $line
                Write-Warning $line
                continue
            }

            # set the extended protection configuration to the expected and supported configuration if different
            $saveInformation = @{}

            foreach ($virtualDirectory in $serverExtendedProtection.ExtendedProtectionConfiguration) {
                Write-Verbose "Virtual Directory Name: $($virtualDirectory.VirtualDirectoryName) Current Set Extended Protection: $($virtualDirectory.ExtendedProtection) Expected Value $($virtualDirectory.ExpectedExtendedConfiguration)"
                if ($virtualDirectory.ExtendedProtection -ne $virtualDirectory.ExpectedExtendedConfiguration) {
                    $saveInformation.Add($virtualDirectory.VirtualDirectoryName, $virtualDirectory.ExpectedExtendedConfiguration)
                }
            }

            if ($saveInformation.Count -gt 0) {
                Write-Host "An update has occurred to the application host config file for server $($serverExtendedProtection.ComputerName). Backing up the application host config file and updating it."
                # provide what we are changing outside of the script block for remote servers.
                Write-Verbose "Setting the following values on the server $($serverExtendedProtection.ComputerName)"
                $saveInformation.Keys | ForEach-Object { Write-Verbose "Setting the $_ with the tokenChecking value of $($saveInformation[$_])" }
                $results = Invoke-ScriptBlockHandler -ComputerName $serverExtendedProtection.ComputerName -ScriptBlock {
                    param(
                        [hashtable]$Commands
                    )
                    $saveToPath = "$($env:WINDIR)\System32\inetsrv\config\applicationHost.config"
                    $backupLocation = $saveToPath.Replace(".config", ".cep.$([DateTime]::Now.ToString("yyyyMMddHHMMss")).bak")
                    try {
                        $backupSuccessful = $false
                        Copy-Item -Path $saveToPath -Destination $backupLocation -ErrorAction Stop
                        $backupSuccessful = $true
                        $errorContext = New-Object 'System.Collections.Generic.List[object]'
                        Write-Host "Successful backup of the application host config file to $backupLocation"
                        foreach ($siteKey in $Commands.Keys) {
                            try {
                                Set-WebConfigurationProperty -Filter "system.WebServer/security/authentication/windowsAuthentication" -Name extendedProtection.tokenChecking -Value $Commands[$siteKey] -Location $siteKey -PSPath IIS:\ -ErrorAction Stop
                            } catch {
                                Write-Host "Failed to set tokenChecking for $env:COMPUTERNAME SITE: $siteKey with the value $($Commands[$siteKey]). Inner Exception $_"
                                $errorContext.Add($_)
                            }
                        }
                    } catch {
                        Write-Host "Failed to save application host file on server $env:COMPUTERNAME. Inner Exception $_"
                    }
                    return [PSCustomObject]@{
                        BackupSuccess       = $backupSuccessful
                        BackupLocation      = $backupLocation
                        SetAllTokenChecking = $errorContext.Count -eq 0
                        ErrorContext        = $errorContext
                    }
                } -ArgumentList $saveInformation

                Write-Verbose "Backup Success: $($results.BackupSuccess) SetAllTokenChecking: $($results.SetAllTokenChecking)"

                if ($results.BackupSuccess -and $results.SetAllTokenChecking) {
                    Write-Verbose "Backed up the file to $($results.BackupLocation)"
                    Write-Host "Successfully backed up and saved new application host config file."
                    $updatedServers.Add($serverExtendedProtection.ComputerName)
                    continue
                } elseif ($results.BackupSuccess -eq $false) {
                    $line = "Failed to backup the application host config file. No settings were applied."
                    Write-Verbose $line
                    Write-Warning $line
                } else {
                    $line = "Failed to properly set all the tokenChecking values on the server $($serverExtendedProtection.ComputerName). Recommended to address!"
                    Write-Verbose $line
                    Write-Warning $line
                }
                $failedServers.Add($serverExtendedProtection.ComputerName)
                Start-Sleep 5 # Sleep to bring to attention to the customer
                Write-Host "Errors that occurred on the backup and set attempt:"
                # Group the events incase they are the same.
                $results.ErrorContext | Group-Object |
                    ForEach-Object {
                        Write-Host "There were $($_.Count) errors that occurred with the following information:"
                        $_.Group | Select-Object -First 1 | ForEach-Object { Write-HostErrorInformation $_ }
                    }
                Write-Host ""
            } else {
                Write-Host "No change was made for the server $($serverExtendedProtection.ComputerName) - Exchange build supports Extended Protection? $($serverExtendedProtection.SupportedVersionForExtendedProtection)"
                $noChangesMadeServers.Add($serverExtendedProtection.ComputerName)
            }
        }
    } end {
        if ($failedServers.Count -gt 0) {
            $line = "These are the servers that failed to apply extended protection: $([string]::Join(", " ,$failedServers))"
            Write-Verbose $line
            Write-Warning $line
        }

        if ($noChangesMadeServers.Count -gt 0) {
            Write-Host "No changes were made to these servers: $([string]::Join(", " ,$noChangesMadeServers))"
        }

        if ($updatedServers.Count -gt 0 ) {
            Write-Host "Successfully updated all of the following servers for extended protection:  $([string]::Join(", " ,$updatedServers))"
        }
    }
}
