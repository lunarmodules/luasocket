smtp = require("smtp")

function test_dot(original, right)
    local result, n = smtp.dot(2, original)
    assert(result == right, "->" .. result .. "<-")
    print("ok")
end

function test_stuff(original, right)
    local result, n = smtp.dot(2, original)
    assert(result == right, "->" .. result .. "<-")
    print("ok")
end

test_dot("abc", "abc")
test_dot("", "")
test_dot("\r\n", "\r\n")
test_dot("\r\n.", "\r\n..")
test_dot(".\r\n.", "..\r\n..")
test_dot(".\r\n.", "..\r\n..")
test_dot("abcd.\r\n.", "abcd.\r\n..")
