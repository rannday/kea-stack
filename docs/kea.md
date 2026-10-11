# Kea deployment notes

Use the [official Kea Administrator Reference Manual](https://kea.readthedocs.io/en/stable/) for configuration instructions. Consult the manual for your installed Kea version. This page highlights details specific to this Docker deployment.

## Kea versions and schema initialization

The three daemon images use ISC's official Cloudsmith 3.2.1 images. The `kea-init` tool reuses the Stork agent image, which includes matching Kea admin packages and schema `34.0`. Update daemon tags, admin package version, and expected schema together.

`kea-init` initializes fresh lease and shared databases, then checks their schemas before the daemons start. It connects to the separate PostgreSQL 18 services `lease-db` and `shared-db`; successful completion leaves this one-shot container exited. The lease database stores leases, while the shared database stores reservations and legal logging. Schema upgrades for retained databases require a separately tested procedure.

## Configuration inputs

The files in `dhcp4/`, `dhcp6/`, and `ddns/` are examples, not a ready-to-use network configuration. Adapt subnets, address pools, routers, and advertised DNS resolvers to your network using the official documentation:

- [DHCPv4 configuration](https://kea.readthedocs.io/en/kea-3.2.1/arm/dhcp4-srv.html)
- [DHCPv6 configuration](https://kea.readthedocs.io/en/stable/arm/dhcp6-srv.html)
- [Dynamic DNS configuration](https://kea.readthedocs.io/en/kea-3.2.1/arm/ddns.html)

Edit the mounted source files, not the generated `/run/kea/` configuration inside the container. Preserve the database and control-address placeholders; the entrypoint resolves them at startup. See [configuration refresh instructions](../README.md#edit-service-configuration).

## DHCP host address and relays

Set `dhcp-server-identifier` in the global `Dhcp4.option-data` array in `dhcp4/kea-dhcp4.conf` before starting the stack:

```json
{ "name": "dhcp-server-identifier", "data": "192.168.1.10" }
```

`192.168.1.10` is an example Docker host LAN IPv4 address: replace it with your host's actual address, preferably static or reserved. Never use `0.0.0.0`, a loopback or multicast address, or a Docker container address. The entrypoint preserves this user-configured option; it does not derive or inject a server identifier from `.env`. Kea checks configuration syntax, but cannot establish whether clients can reach the address. If you configure a server identifier at subnet, shared-network, or client-class scope, it overrides the global value; remove those overrides or ensure they advertise the appropriate reachable host address.

**This setting is important for DHCPv4 to function correctly.** Without a reachable server identifier, initial leasing through a relay can succeed while clients cannot contact the advertised server for T1 unicast renewal. `DHCP4_BIND_ADDRESS=0.0.0.0` only controls host port listening; it does not advertise an address to clients. Configure relays to target the Docker host's IPv4 address and allow client and relay traffic to host UDP 67, with a working return path. Clients need no route to Docker's internal subnet. Test both initial leasing and T1 renewal from a representative client.

DHCPv6 uses a DUID as its server identifier, not an IPv6 address, so there is no `DHCP6_SERVER_IDENTIFIER` IP setting. Configure DHCPv6 relays to forward to a reachable IPv6 address of the Docker host, permit UDP 547 and return traffic, and verify leasing and renewal. `DHCP6_BIND_ADDRESS=::` means listening on all host IPv6 interfaces; it is not an address a relay can target. Docker bridge port publishing does not forward raw client broadcasts or link-local DHCPv6 multicast; use relays for this deployment.

See the [Kea DHCPv4 server identifier documentation](https://kea.readthedocs.io/en/kea-3.2.1/arm/dhcp4-srv.html) and [DHCPv6 server identifier documentation](https://kea.readthedocs.io/en/stable/arm/dhcp6-srv.html).

## Persistent DHCPv6 server identity

DHCPv6 stores `/var/lib/kea/kea-dhcp6-serverid` in the `dhcp_state` named volume. Recreating the daemon preserves its DUID; removing the volume changes the server identity.

## Optional DNS

Enabling the Compose `dns` profile starts BIND, the separate `ddns` daemon, `agent-ddns`, and the BIND exporter, and enables DHCP DDNS integration. Set the resolver addresses advertised to clients in `dhcp4/kea-dhcp4.conf` and `dhcp6/kea-dhcp6.conf`; use addresses clients can reach, not internal Compose service names or container IPs. Keep DHCP pools, D2 forward/reverse domains, and BIND zones aligned. The supplied reverse-zone examples match the test pools `192.0.2.0/24` and `2001:db8:1::/64`. Replace these examples for your deployment, updating the DHCP subnets and pools, D2 reverse domains in `ddns/kea-dhcp-ddns.conf`, BIND zone declarations, and seed filenames together. BIND startup validation and health checks derive zones from `dns/named.conf`.

When DNS is disabled, the entrypoint removes DDNS integration while preserving configured DHCP options, including advertised resolvers and the server identifier. External resolvers can still be advertised. See [DNS deployment setup](../README.md#use-dns-optional) for the profile and TSIG key.
