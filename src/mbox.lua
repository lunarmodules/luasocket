local Public = {}

parse = Public

function Public.headers(headers_s)
    local headers = {}
    headers_s = "\n" .. headers_s .. "$$$:\n"
    local i, j = 1, 1
    local name, value, _
    while 1 do
        j = strfind(headers_s, "\n%S-:", i+1)
        if not j then break end
        _,_, name, value = strfind(strsub(headers_s, i+1, j-1), "(%S-):%s?(.*)")
        value = gsub(value or "", "\r\n", "\n")
        value = gsub(value, "\n%s*", " ")
        name = strlower(name)
        if headers[name] then headers[name] = headers[name] .. ", " ..  value
        else headers[name] = value end
        i, j = j, i
    end
    headers["$$$"] = nil
    return headers
end

function Public.message(message_s)
    message_s = gsub(message_s, "^.-\n", "")
    local _, headers_s, body
    _, _, headers_s, body = strfind(message_s, "^(.-\n)\n(.*)")
    headers_s = headers_s or ""
    body = body or ""
    return { headers = %Public.headers(headers_s), body = body }
end

function Public.mbox(mbox_s)
    local mbox = {}
    mbox_s = "\n" .. mbox_s .. "\nFrom "
    local i, j = 1, 1
    while 1 do
        j = strfind(mbox_s, "\nFrom ", i + 1)
        if not j then break end
        tinsert(mbox, %Public.message(strsub(mbox_s, i + 1, j - 1)))
        i, j = j, i
    end
    return mbox
end
