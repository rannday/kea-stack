$TTL 300
@   IN  SOA ns1.example.com. hostmaster.example.com. (
        2026101001
        300
        120
        604800
        300
)

    IN  NS  ns1.example.com.

ns1 IN  A   192.0.2.53
ns1 IN  AAAA 2001:db8::53
www IN  A   192.0.2.80
workflow-check IN TXT "compose-cycle-20261010"
