# SNMP Monitoring Script
# Reads list of OIDs from CTR_SNMP_OID.csv and writes current values to CTR_SNMP_Output.txt

# Configuration
$snmpExe = "C:\Users\s.uhlmann\snmpget.exe"   # Path to snmpget.exe
$ip = "192.168.178.88"                                   # SNMP device IP
$community = "public"                                    # Change if necessary
$csvFile = "C:\Users\s.uhlmann\CTR_SNMP_OID.csv"                    # Input file: Variable,OID
$outFile = "C:\Users\s.uhlmann\CTR_SNMP_Output.txt"                 # Output file
$intervalSeconds = 5                                     # Update interval in seconds

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

# Ensure directories exist
New-Item -ItemType Directory -Force -Path (Split-Path $csvFile) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $outFile) | Out-Null

# Verify input file exists
if (-not (Test-Path $csvFile)) {
    Write-Host "ERROR: File $csvFile not found!"
    exit 1
}

Write-Host "Starting SNMP monitoring of $ip using $csvFile ... (Ctrl + C to stop)"

while ($true) {
    try {
        # Read OID list
        $oids = Import-Csv -Path $csvFile -Header "Variable","OID"

        $output = @()
        foreach ($entry in $oids) {
            $variable = $entry.Variable.Trim()

			#Write-Host $entry.OID.Trim()
            $oid = $entry.OID.Trim()
			#Write-Host $oid
			
            # Query SNMP value
            $raw = & $snmpExe -r:$ip -o:$oid -q 2>&1
			
			#Write-Host $raw

			if ($oid -eq '.1.3.6.1.4.1.58765.1.2.10.0') {
				$value = Get-FirmwareVersion $raw

				#$matches = $null
				#$raw -match '\d+\.\d+\.\d+'
				#$value = $matches[1]
				#TODO: Convert the Firmware-Segment to an actual number
				#Write-Host $oid
			} else {
				$value = $raw
				#Write-Host $oid
			}

            # Extract the value after '='
            #if ($raw -match '=\s*(.*)$') {
            #    $value = $matches[1].Trim()
            #} else {
            #    $value = "Error: no response"
            #}

			

			#Write-Host $raw
            # Store formatted line
            $output += "$variable, $value"
			#Start-Sleep -Seconds 5 
        }

        # Write all results to output file (overwrite each time)
		Write-Host $output
        $output | Out-File -FilePath $outFile -Encoding UTF8

        # Wait before next update
        Start-Sleep -Seconds $intervalSeconds
    }
    catch {
        "Error: $($_.Exception.Message)" | Out-File -FilePath $outFile
        Start-Sleep -Seconds $intervalSeconds
    }
}
