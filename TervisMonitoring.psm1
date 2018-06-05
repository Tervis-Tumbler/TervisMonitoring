$ModulePath = (Get-Module -ListAvailable TervisMonitoring).ModuleBase
. $ModulePath\Definition.ps1

function Install-TervisMonitoring {
    param (
        [Parameter(Mandatory)]$ComputerName
    )

    $ScheduledTasksCredential = Get-PasswordstatePassword -ID 259 -AsCredential

    Install-PowerShellApplication `
        -ModuleName TervisMonitoring `
        -DependentTervisModuleNames "TervisMailMessage"
        -ScheduledTasksCredential $ScheduledTasksCredential `
        -ScheduledScriptCommandsString "Send-TervisDNSServerReport" `
        -ScheduledTaskName "Send-TervisDNSServerReport" `
        -RepetitionIntervalName EveryDayEvery15Minutes `
        -ComputerName $ComputerName

    Install-PowerShellApplication `
        -ModuleName TervisMonitoring `
        -DependentTervisModuleNames "InvokeSQL",
            "TervisMailMessage",
            "TervisWCSSybase",
            "TervisPasswordstate",
            "PasswordstatePowerShell",
            "WebServicesPowerShellProxyBuilder",
            "TervisMicrosoft.PowerShell.Utility" `
        -ScheduledTasksCredential $ScheduledTasksCredential `
        -ScheduledScriptCommandsString "Test-ConveyorScaleSameWeight" `
        -ScheduledTaskName "Test-ConveyorScaleSameWeight" `
        -RepetitionIntervalName EveryMinuteOfEveryDay `
        -ComputerName $ComputerName
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

function Test-ConveyorScaleSameWeight {
    $NumberOfBoxesToSample = 30
    $ConveyorScaleNumberOfUniqueWeights = Get-ConveyorScaleNumberOfUniqueWeights -NumberOfBoxesToSample $NumberOfBoxesToSample

    if ($ConveyorScaleNumberOfUniqueWeights -eq 1) {
        Send-ConveyorScaleSameWeightMessage -NumberOfBoxesToSample $NumberOfBoxesToSample
    }

    if (-not $ConveyorScaleNumberOfUniqueWeights) {
        Throw "Something went wrong"
    }
}

function Send-ConveyorScaleSameWeightMessage {
    param (
        $NumberOfBoxesToSample
    )
    $To = "WCSIssues@tervis.com"
    Send-TervisMailMessage -To $To -Bcc $Bcc -From ITNotification@tervis.com -Subject "ERROR: Last $NumberOfBoxesToSample boxes on the conveyor scale received the same weight" -Body "Last $NumberOfBoxesToSample boxes on the conveyor scale received the same weight.`r`n`r`nPlease check the scale."
}
