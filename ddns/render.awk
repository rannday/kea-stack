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
BEGIN {
    split("KEA_CONTROL_ADDRESS DNS_ADDRESS", names, " ")
}
{
    line = $0
    for (i in names) line = replace(line, "__" names[i] "__", ENVIRON[names[i]])
    print line
}
