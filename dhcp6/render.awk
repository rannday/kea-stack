#!/usr/bin/awk -f

# Render exact placeholder strings using only utilities in ISC's images.
function quote(value,    result, i, char) {
    result = "\""
    for (i = 1; i <= length(value); i++) {
        char = substr(value, i, 1)
        if (char == "\\" || char == "\"") result = result "\\" char
        else if (char == "\n") result = result "\\n"
        else if (char == "\r") result = result "\\r"
        else if (char == "\t") result = result "\\t"
        else result = result char
    }
    return result "\""
}
function replace(line, token, value,    position, result) {
    token = "\"" token "\""
    while ((position = index(line, token))) {
        result = result substr(line, 1, position - 1) quote(value)
        line = substr(line, position + length(token))
    }
    return result line
}
function nesting(line,    i, char, quoted, escaped, depth) {
    for (i = 1; i <= length(line); i++) {
        char = substr(line, i, 1)
        if (escaped) { escaped = 0; continue }
        if (quoted && char == "\\") { escaped = 1; continue }
        if (char == "\"") { quoted = !quoted; continue }
        if (!quoted) {
            if (char == "{") depth++
            if (char == "}") depth--
        }
    }
    return depth
}
BEGIN {
    split("LEASE_DB_NAME LEASE_DB_USER LEASE_DB_PASS SHARED_DB_NAME SHARED_DB_USER SHARED_DB_PASS KEA_CONTROL_ADDRESS DDNS_ADDRESS", names, " ")
}
{
    if (ENVIRON["DNS_ACTIVE"] != "true") {
        if ($0 ~ /"dhcp-ddns"[[:space:]]*:/) skipping = 1
        if (skipping) {
            depth += nesting($0)
            if (depth == 0) skipping = 0
            next
        }
        if ($0 ~ /libdhcp_ddns_tuning[.]so/) next
        sub(/"ddns-send-updates":[[:space:]]*true/, "\"ddns-send-updates\": false")
    }
    line = $0
    for (i in names) line = replace(line, "__" names[i] "__", ENVIRON[names[i]])
    print line
}
