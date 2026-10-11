# Windows firewall

These examples create inbound Windows Defender Firewall rules with PowerShell. Run PowerShell as Administrator. Replace the example addresses with the actual relay, client, administrator, and Docker host addresses for your network.

The rules restrict remote sources where practical. Windows firewall rules do not make Docker bridge networking carry DHCP broadcasts or link-local DHCPv6 multicast; use DHCP relays for this deployment. Published ports bind to `0.0.0.0` by default, except DHCPv6, which binds to `::`. Set the relevant service-specific `*_BIND_ADDRESS` variable in `.env` to bind a service to one host address instead.

## DHCP relays and client renewals

Allow DHCPv4 traffic from both relay addresses and client networks. Initial leasing can succeed through a relay while T1 unicast renewal fails if only relays can reach host UDP 67. Use separate IPv4 and IPv6 relay addresses; replace all examples with your network's addresses and client subnets:

```powershell
$Dhcp4RelayAddresses = @('192.0.2.2') # Replace with IPv4 relay address(es)
$Dhcp4ClientNetworks = @('198.51.100.0/24') # Replace with IPv4 client subnet(s)
$Dhcp6RelayAddresses = @('2001:db8::2') # Replace with IPv6 relay address(es)
$Dhcp4Sources = $Dhcp4RelayAddresses + $Dhcp4ClientNetworks
$RuleBase = 'Kea Stack'

New-NetFirewallRule -DisplayName "$RuleBase DHCPv4 relays and clients UDP 67" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol UDP -LocalPort 67 -RemoteAddress $Dhcp4Sources
New-NetFirewallRule -DisplayName "$RuleBase DHCPv6 relay UDP 547" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol UDP -LocalPort 547 -RemoteAddress $Dhcp6RelayAddresses
```

Set `dhcp-server-identifier` in `dhcp4/kea-dhcp4.conf` to the Docker host IPv4 address that clients can reach, as described in [DHCP host address and relays](kea.md#dhcp-host-address-and-relays). Clients need a route to that address for direct T1 renewal, and the host needs a working return path to the client networks. Listening on `DHCP4_BIND_ADDRESS=0.0.0.0` does not advertise a reachable server address or create those routes.

If you previously applied the relay-only IPv4 example, apply the new IPv4 rule with your client subnets too; the existing relay-only rule does not permit client renewals. Verify both initial leasing through a relay and direct T1 renewal from a representative client after applying the rules. DHCPv6 relays still target a reachable host IPv6 address on UDP 547. These rules do not forward raw DHCP broadcasts or link-local DHCPv6 multicast into Docker's bridge network.

## DNS (only when enabled)

If the optional DNS service is running and clients use it, allow DNS queries from any source address:

```powershell
$RuleBase = 'Kea Stack'
$DnsPort = 53 # Match BIND9_BIND_PORT in .env.

New-NetFirewallRule -DisplayName "$RuleBase DNS UDP $DnsPort" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol UDP -LocalPort $DnsPort
New-NetFirewallRule -DisplayName "$RuleBase DNS TCP $DnsPort" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol TCP -LocalPort $DnsPort
```

If `BIND9_BIND_PORT` is set to a host port other than 53, use that same value for `$DnsPort` above. DNS clients normally expect port 53.

## Management interfaces

Stork, Grafana, Prometheus, and the Kea control APIs are published for administration. They are not required for clients to receive DHCP or DNS. If you need remote administration, restrict these ports to a trusted management subnet. Otherwise, leave them unavailable to remote machines.

Replace the subnet and run only the rules for interfaces you intend to access:

```powershell
$AdminNetworks = @('192.0.2.0/24') # Replace with trusted management subnet(s)
$RuleBase = 'Kea Stack'

New-NetFirewallRule -DisplayName "$RuleBase Kea API TCP 8100-8102" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol TCP -LocalPort 8100-8102 -RemoteAddress $AdminNetworks
New-NetFirewallRule -DisplayName "$RuleBase Stork TCP 8080" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol TCP -LocalPort 8080 -RemoteAddress $AdminNetworks
New-NetFirewallRule -DisplayName "$RuleBase Prometheus TCP 9090" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol TCP -LocalPort 9090 -RemoteAddress $AdminNetworks
New-NetFirewallRule -DisplayName "$RuleBase Grafana TCP 3000" -Direction Inbound -Action Allow -Enabled True -Profile Domain,Private -Protocol TCP -LocalPort 3000 -RemoteAddress $AdminNetworks
```

Docker publishes these ports using the corresponding service-specific `*_BIND_ADDRESS` variables. Confirm the address and port mappings with `docker compose ps`. A listening Docker port does not by itself prove the Windows firewall allows remote traffic.

The DDNS control API on TCP 8102 is published only with the `dns` profile. PostgreSQL, Stork agent ports, DHCP exporter ports, BIND statistics, and the BIND exporter remain internal to Docker; they need no inbound host rules. Kea-to-DDNS traffic also stays inside Docker.

## Check and remove these rules

List rules created by the examples:

```powershell
Get-NetFirewallRule -DisplayName 'Kea Stack *' | Format-Table DisplayName, Enabled, Profile, Direction, Action
```

Remove only the rules with this display-name prefix:

```powershell
Get-NetFirewallRule -DisplayName 'Kea Stack *' | Remove-NetFirewallRule
```

The rules above apply to Domain and Private profiles. Adjust `-Profile` if the Docker host uses a different Windows network profile. See Microsoft's [New-NetFirewallRule](https://learn.microsoft.com/powershell/module/netsecurity/new-netfirewallrule) and [Remove-NetFirewallRule](https://learn.microsoft.com/powershell/module/netsecurity/remove-netfirewallrule) documentation for all options.
