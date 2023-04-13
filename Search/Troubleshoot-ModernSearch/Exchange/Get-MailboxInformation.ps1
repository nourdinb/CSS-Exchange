﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. $PSScriptRoot\..\..\..\Shared\StoreQueryFunctions.ps1
# Gets the information required to determine an issue for the particular mailbox.
function Get-MailboxInformation {
    [CmdletBinding()]
    param(
        [string]
        $Identity,

        [bool]
        $IsArchive,

        [bool]
        $IsPublicFolder
    )

    try {

        <#
            From Get-StoreQueryMailboxInformation we already collect the following:
                - Get-Mailbox
                - Get-MailboxStatistics
                - Get-MailboxDatabaseCopyStatus
                - Get-ExchangeServer
                - Get-MailboxDatabase -Status
        #>
        $storeQueryMailboxInfo = Get-StoreQueryMailboxInformation -Identity $Identity -IsArchive $IsArchive -IsPublicFolder $IsPublicFolder

        if ($storeQueryMailboxInfo.ExchangeServer.AdminDisplayVersion.ToString() -notlike "Version 15.2*") {
            throw "User isn't on an Exchange 2019 server"
        }

        if (-not $IsPublicFolder) {
            try {
                # Only thing additionally that needs to be collected is Get-MailboxFolderStatistics
                $mailboxFolderStats = Get-MailboxFolderStatistics -Identity $Identity -Archive:$IsArchive -ErrorAction Stop
                $storeQueryMailboxInfo | Add-Member -MemberType NoteProperty -Name "MailboxFolderStatistics" -Value $mailboxFolderStats
            } catch {
                Write-Verbose "Failed to collect Get-MailboxFolderStatistics"
            }
        }

        return $storeQueryMailboxInfo
    } catch {
        throw "Failed to find '$Identity' information. InnerException: $($Error[0].Exception)"
    }
}
