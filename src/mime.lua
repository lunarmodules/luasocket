if not ltn12 then error('Requires LTN12 module') end
-- create mime namespace
mime = mime or {}
-- make all module globals fall into mime namespace
setmetatable(mime, { __index = _G })
setfenv(1, mime)

-- encode, decode and wrap algorithm tables
encodet = {}
decodet = {}
wrapt = {}

-- creates a function that chooses a filter by name from a given table 
function choose(table)
    return function(name, opt1, opt2)
        if type(name) ~= "string" then 
            name, opt1, opt2 = "default", name, opt1
        end
        local f = table[name or "nil"]
        if not f then error("unknown key (" .. tostring(name) .. ")", 3)
        else return f(opt1, opt2) end
    end
end

-- define the encoding filters
encodet['base64'] = function()
    return ltn12.filter.cycle(b64, "")
end

encodet['quoted-printable'] = function(mode)
    return ltn12.filter.cycle(qp, "", 
        (mode == "binary") and "=0D=0A" or "\13\10")
end

-- define the decoding filters
decodet['base64'] = function()
    return ltn12.filter.cycle(unb64, "")
end

decodet['quoted-printable'] = function()
    return ltn12.filter.cycle(unqp, "")
end

-- define the line-wrap filters
wrapt['text'] = function(length)
    length = length or 76
    return ltn12.filter.cycle(wrp, length, length) 
end
wrapt['base64'] = wrapt['text']
wrapt['default'] = wrapt['text']

wrapt['quoted-printable'] = function()
    return ltn12.filter.cycle(qpwrp, 76, 76) 
end

-- function that choose the encoding, decoding or wrap algorithm
encode = choose(encodet) 
decode = choose(decodet)
wrap = choose(wrapt)

-- define the end-of-line normalization filter
function normalize(marker)
    return ltn12.filter.cycle(eol, 0, marker)
end

return mime
