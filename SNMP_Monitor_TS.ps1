# SNMP Monitoring Script
# Reads list of OIDs from CTR_SNMP_OID.csv and writes current values to CTR_SNMP_Output.txt

# Configuration
$snmpExe = "C:\Users\s.uhlmann\snmpget.exe"   # Path to snmpget.exe
$ip = "192.168.178.88"                        # SNMP device IP
$community = "public"                         # Change if necessary
$csvFile = "C:\Users\s.uhlmann\CTR_SNMP_OID.csv"  # Input file: Variable,OID
$outFile = "C:\Users\s.uhlmann\CTR_SNMP_Output.txt" # Output file
$intervalSeconds = 60                          # Update interval in seconds

function Get-FirmwareVersion {
    param(
        [string]$Raw
    )

    # 1) Direct ASCII "5.4.13" match
    if ($Raw -match "\d+\.\d+\.\d+") {
        return $matches[0]
    }

    # 2) Extract hex pairs from raw dump
    $hexPairs = [regex]::Matches($Raw, '(?i)\b[0-9A-F]{2}\b') |
                ForEach-Object { $_.Value }

    if ($hexPairs.Count -eq 0) {
        return $null
    }

    # 3) Convert hex to byte array
    $bytes = $hexPairs | ForEach-Object { [Convert]::ToByte($_,16) }

    # 4) Decode ASCII
    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)

    # 5) Cut at first NUL (0x00)
    $asciiClean = ($ascii -split "`0")[0]

    # 6) Final regex match
    if ($asciiClean -match "\d+\.\d+\.\d+") {
        return $matches[0]
    }

    return $null
}

# -------------------------------
# NEW STATE TABLE FOR CHANGE TRACKING
# -------------------------------
$State = @{}

# Main Loop
while ($true) {
    try {
        $output = @()

        # Read CSV list
        $list = Import-Csv -Path $csvFile -Header "Variable","OID"

        foreach ($item in $list) {
            $var = $item.Variable
            $oid = $item.OID

            # Execute SNMPGET
            $cmd = "$snmpExe -r:$ip -o:$oid -q"
            $result = Invoke-Expression $cmd
			

            # Parse value
            if ($result) {
                $value = $result


                # Optional decoding of firmware version
                if ($oid -eq '.1.3.6.1.4.1.58765.1.2.10.0') {
                    $value = Get-FirmwareVersion $value
                }
				
				# Case Statements to add the state
				
				# nmxCentaurInstrumentState
				if ($oid -eq '.1.3.6.1.4.1.58765.1.2.8.0') {
					switch ($value) {
					0 { $value = "0: ok" }
					1 { $value = "1: warning" }
					2 { $value = "2: error" }
					}
				}
				
				# nmxCentaurCommitState
				if ($oid -eq '.1.3.6.1.4.1.58765.1.2.4.0') {
					switch ($value) {
					0 { $value = "0: comitted" }
					1 { $value = "1: not committed" }
					}
				}

				# nmxCentaurGnssState
				if ($oid -eq '.1.3.6.1.4.1.58765.1.1.3.0') {
					switch ($value) {
					0 { $value = "0: off" }
					1 { $value = "1: unlocked" }
					2 { $value = "2: locked" }
					}
				}				
				
				# nmxCentaurTimingPLLState
				if ($oid -eq '.1.3.6.1.4.1.58765.1.1.1.0') {
					switch ($value) {
					0 { $value = "0: noLock" }
					1 { $value = "1: coarseLock" }
					2 { $value = "2: fineLock" }
					3 { $value = "2: freeRunning" }
					}
				}			

				# nmxCentaurTimeState
				if ($oid -eq '.1.3.6.1.4.1.58765.1.1.4.0') {
					switch ($value) {
					0 { $value = "0: timeOK" }
					1 { $value = "1: freeRunning" }
					2 { $value = "2: init" }
					3 { $value = "3: timeError" }
					4 { $value = "4: timeServerUnreachable" }
					5 { $value = "4: noAntenna" }
					}
				}								
				
				if ($oid -eq '.1.3.6.1.4.1.58765.1.3.1.0') {
					switch ($value) {
					0 { $value = "0: ok" }
					1 { $value = "1: warning" }
					2 { $value = "2: error" }
					}
				}
				
				if ($oid -eq '.1.3.6.1.4.1.58765.1.3.2.0') {
					switch ($value) {
					0 { $value = "0: ok" }
					1 { $value = "1: warning" }
					2 { $value = "2: error" }
					}
				}

				#Write-Host $oid "#" $value


                # -------------------------------
                # VALUE CHANGE TRACKING LOGIC
                # -------------------------------
                if (-not $State.ContainsKey($var)) {
                    # First time: initialize
                    $State[$var] = @{
                        LastValue = $value
                        LastChanged = (Get-Date).ToString("o")
                    }
                }
                else {
                    # Compare values
                    if ($State[$var].LastValue -ne $value) {
                        $State[$var].LastValue = $value
                        $State[$var].LastChanged = (Get-Date).ToString("o")
                    }
                }

                # Final timestamp for output
                $timestamp = $State[$var].LastChanged
				

                # Output format: variable, value, timestamp
                $output += "$($var), $value, $timestamp"
            }
            else {
                $output += "$($var), ERROR"
            }
        }

        # Write all results to output file (overwrite each time)
        #Write-Host $output
        $output | Out-File -FilePath $outFile -Encoding UTF8

        # Wait before next update
        Start-Sleep -Seconds $intervalSeconds
    }
    catch {
        "Error: $($_.Exception.Message)" | Out-File -FilePath $outFile
        Start-Sleep -Seconds $intervalSeconds
    }
}
