local Public = {}

mbox = Public

function Public.split_message(message_s)
    local message = {}
    message_s = gsub(message_s, "\r\n", "\n")
	gsub(message_s, "^(.-\n)\n", function (h) %message.headers = h end)
	gsub(message_s, "^.-\n\n(.*)", function (b) %message.body = b end)
    if not message.body then
	    gsub(message_s, "^\n(.*)", function (b) %message.body = b end)
    end
    if not message.headers and not message.body then 
        message.headers = message_s
    end
    return message.headers or "", message.body or ""
end

function Public.split_headers(headers_s)
    local headers = {}
    headers_s = gsub(headers_s, "\r\n", "\n")
    headers_s = gsub(headers_s, "\n[ ]+", " ")
    gsub("\n" .. headers_s, "\n([^\n]+)", function (h) tinsert(%headers, h) end)
    return headers
end

function Public.parse_header(header_s)
    header_s = gsub(header_s, "\n[ ]+", " ")
    header_s = gsub(header_s, "\n+", "")
    local _, __, name, value = strfind(header_s, "([^%s:]-):%s*(.*)")
    return name, value
end

function Public.parse_headers(headers_s)
    local headers_t = %Public.split_headers(headers_s)
    local headers = {}
    for i = 1, getn(headers_t) do
        local name, value = %Public.parse_header(headers_t[i])
        if name then
            name = strlower(name)
            if headers[name] then
                headers[name] = headers[name] .. ", " .. value
            else headers[name] = value end
        end
    end
    return headers
end

function Public.parse_from(from)
    local _, __, name, address = strfind(from, "^%s*(.-)%s*%<(.-)%>")
    if not address then
        _, __, address = strfind(from, "%s*(.+)%s*")
    end
    name = name or ""
    address = address or ""
    if name == "" then name = address end
	name = gsub(name, '"', "")
    return name, address
end

function Public.split_mbox(mbox_s)
	mbox = {}
	mbox_s = gsub(mbox_s, "\r\n", "\n") .."\n\nFrom \n"
	local nj, i, j = 1, 1, 1
	while 1 do
		i, nj = strfind(mbox_s, "\n\nFrom .-\n", j)
		if not i then break end
		local message = strsub(mbox_s, j, i-1)
		tinsert(mbox, message)
		j = nj+1
	end
	return mbox
end

function Public.parse_mbox(mbox_s)
	local mbox = %Public.split_mbox(mbox_s)
	for i = 1, getn(mbox) do
		mbox[i] = %Public.parse_message(mbox[i])
	end
	return mbox
end

function Public.parse_message(message_s)
    local message = {}
    message.headers, message.body = %Public.split_message(message_s)
    message.headers = %Public.parse_headers(message.headers)
    return message
end
