# =========================
# SSH K8S TUNNEL SERVICE
# =========================

$User = "difi"
$Middleware = "10.30.64.198"
$RemoteNodeIP = "172.22.64.245"
$RemotePort = "50207"
$LocalPort = "50207"

Write-Host "Starting Kubernetes SSH tunnel service..."

while ($true) {
    try {
        Write-Host "Launching tunnel: localhost:$LocalPort -> $RemoteNodeIP:$RemotePort"

        # Start SSH tunnel
        $proc = Start-Process -FilePath "ssh" -ArgumentList @(
            "-N",
            "-L", "$LocalPort`:$RemoteNodeIP`:$RemotePort",
            "$User@$Middleware"
        ) -PassThru

        # Monitor process
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 5
        }

        throw "SSH tunnel stopped"
    }
    catch {
        Write-Host "Tunnel down. Restarting in 3 seconds..."
        Start-Sleep -Seconds 3
    }
}
