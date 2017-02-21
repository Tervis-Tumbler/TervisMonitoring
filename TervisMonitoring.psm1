#requires -module TervisMailMessage

function Install-TervisMonitoring {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot
    )
    Install-PasswordStatePowerShell

    $ScheduledTasksCredential = Get-PasswordstateCredential -PasswordID 259

    Install-PowerShellApplicationScheduledTask -PathToScriptForScheduledTask $PathToScriptForScheduledTask `
        -Credential $ScheduledTasksCredential `
        -ScheduledTaskFunctionName "Send-TervisDNSServerReport" `
        -RepetitionInterval EveryDayEvery15Minutes
}

function Test-TervisDNSServerHealth {
    $DNSServers = Get-NetIPConfiguration | 
        select -ExpandProperty DNSServer | 
        select -ExpandProperty ServerAddresses

    foreach ($Server in $DNSServers) {
        $Test_DomainName = try {
            if (Resolve-DnsName -Name $env:USERDNSDOMAIN -Type A -Server $Server -DnsOnly -NoHostsFile -ErrorAction Stop) {
                $true
            }
        } catch {
            $false
        }  
        
        $Test_External = try {
            if (Resolve-DnsName -Name www.google.com -Type A -Server $Server -DnsOnly -NoHostsFile -ErrorAction Stop) {
                $true
            }
        } catch {
            $false
        }

        [PSCustomObject][Ordered]@{
            DNSServer = $Server
            InternalRequestTest = $Test_DomainName
            ExternalRequestTest = $Test_External
        }
    }
}

function Send-TervisDNSServerReport {
    $DNSHealthTests = Test-TervisDNSServerHealth
    
    foreach ($DNSTest in $DNSHealthTests) {
        if (!$DNSTest.InternalRequestTest -or !$DNSTest.ExternalRequestTest) {
                Send-TervisMailMessage `
                    -From mailerdaemon@tervis.com `
                    -To technicalservices@tervis.com `
                    -Subject "ALERT: $($DNSTest.DNSServer) - No response to DNS request" `
                    -Body @"
DNS Server: $($DNSTest.DNSServer)
Internal Request Test: $($DNSTest.InternalRequestTest)
External Request Test: $($DNSTest.ExternalRequestTest)
"@
        }
    }
}