-----------------------------------------------------------------------------
-- URI parsing, composition and relative URL resolution
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 2396, LTN7
-- RCS ID: $Id$
----------------------------------------------------------------------------

-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME]
if not socket then error('module requires LuaSocket') end
-- create smtp namespace inside LuaSocket namespace
local url = socket.url or {}
socket.url = url
-- make all module globals fall into smtp namespace
setmetatable(url, { __index = _G })
setfenv(1, url)

-----------------------------------------------------------------------------
-- Encodes a string into its escaped hexadecimal representation
-- Input 
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-----------------------------------------------------------------------------
function escape(s)
    return string.gsub(s, "(.)", function(c)
        return string.format("%%%02x", string.byte(c))
    end)
end

-----------------------------------------------------------------------------
-- Protects a path segment, to prevent it from interfering with the
-- url parsing. 
-- Input 
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-----------------------------------------------------------------------------
local function make_set(t)
	local s = {}
	for i = 1, table.getn(t) do
		s[t[i]] = 1
	end
	return s
end

-- these are allowed withing a path segment, along with alphanum
-- other characters must be escaped
local segment_set = make_set {
    "-", "_", ".", "!", "~", "*", "'", "(", 
	")", ":", "@", "&", "=", "+", "$", ",",
}

local function protect_segment(s)
	return string.gsub(s, "(%W)", function (c) 
		if segment_set[c] then return c
		else return escape(c) end
	end)
end

-----------------------------------------------------------------------------
-- Encodes a string into its escaped hexadecimal representation
-- Input 
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-----------------------------------------------------------------------------
function unescape(s)
    return string.gsub(s, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

-----------------------------------------------------------------------------
-- Builds a path from a base path and a relative path
-- Input
--   base_path
--   relative_path
-- Returns
--   corresponding absolute path
-----------------------------------------------------------------------------
local function absolute_path(base_path, relative_path)
    if string.sub(relative_path, 1, 1) == "/" then return relative_path end
    local path = string.gsub(base_path, "[^/]*$", "")
    path = path .. relative_path
    path = string.gsub(path, "([^/]*%./)", function (s) 
        if s ~= "./" then return s else return "" end
    end)
    path = string.gsub(path, "/%.$", "/")
    local reduced 
    while reduced ~= path do
        reduced = path
        path = string.gsub(reduced, "([^/]*/%.%./)", function (s)
            if s ~= "../../" then return "" else return s end
        end)
    end
    path = string.gsub(reduced, "([^/]*/%.%.)$", function (s)
        if s ~= "../.." then return "" else return s end
    end)
    return path
end

-----------------------------------------------------------------------------
-- Parses a url and returns a table with all its parts according to RFC 2396
-- The following grammar describes the names given to the URL parts
-- <url> ::= <scheme>://<authority>/<path>;<params>?<query>#<fragment>
-- <authority> ::= <userinfo>@<host>:<port>
-- <userinfo> ::= <user>[:<password>]
-- <path> :: = {<segment>/}<segment>
-- Input
--   url: uniform resource locator of request
--   default: table with default values for each field
-- Returns
--   table with the following fields, where RFC naming conventions have
--   been preserved:
--     scheme, authority, userinfo, user, password, host, port, 
--     path, params, query, fragment
-- Obs:
--   the leading '/' in {/<path>} is considered part of <path>
-----------------------------------------------------------------------------
function parse(url, default)
    -- initialize default parameters
    local parsed = default or {}
    -- empty url is parsed to nil
    if not url or url == "" then return nil end
    -- remove whitespace
    -- url = string.gsub(url, "%s", "")
    -- get fragment
    url = string.gsub(url, "#(.*)$", function(f) parsed.fragment = f end)
    -- get scheme
    url = string.gsub(url, "^([%w][%w%+%-%.]*)%:", 
        function(s) parsed.scheme = s end)
    -- get authority
    url = string.gsub(url, "^//([^/]*)", function(n) parsed.authority = n end)
    -- get query stringing
    url = string.gsub(url, "%?(.*)", function(q) parsed.query = q end)
    -- get params
    url = string.gsub(url, "%;(.*)", function(p) parsed.params = p end)
    -- path is whatever was left
    if url ~= "" then parsed.path = url end
    local authority = parsed.authority
    if not authority then return parsed end
    authority = string.gsub(authority,"^([^@]*)@",
        function(u) parsed.userinfo = u end)
    authority = string.gsub(authority, ":([^:]*)$", 
        function(p) parsed.port = p end)
    if authority ~= "" then parsed.host = authority end
    local userinfo = parsed.userinfo
    if not userinfo then return parsed end
    userinfo = string.gsub(userinfo, ":([^:]*)$", 
        function(p) parsed.password = p end)
    parsed.user = userinfo 
    return parsed
end

-----------------------------------------------------------------------------
-- Rebuilds a parsed URL from its components.
-- Components are protected if any reserved or unallowed characters are found
-- Input
--   parsed: parsed URL, as returned by parse
-- Returns
--   a stringing with the corresponding URL
-----------------------------------------------------------------------------
function build(parsed)
    local ppath = parse_path(parsed.path or "")
    local url = build_path(ppath)
    if parsed.params then url = url .. ";" .. parsed.params end
    if parsed.query then url = url .. "?" .. parsed.query end
	local authority = parsed.authority
	if parsed.host then
		authority = parsed.host
		if parsed.port then authority = authority .. ":" .. parsed.port end
		local userinfo = parsed.userinfo
		if parsed.user then
			userinfo = parsed.user
			if parsed.password then 
				userinfo = userinfo .. ":" .. parsed.password 
			end
		end
		if userinfo then authority = userinfo .. "@" .. authority end
	end
    if authority then url = "//" .. authority .. url end
    if parsed.scheme then url = parsed.scheme .. ":" .. url end
    if parsed.fragment then url = url .. "#" .. parsed.fragment end
    -- url = string.gsub(url, "%s", "")
    return url
end

-----------------------------------------------------------------------------
-- Builds a absolute URL from a base and a relative URL according to RFC 2396
-- Input
--   base_url
--   relative_url
-- Returns
--   corresponding absolute url
-----------------------------------------------------------------------------
function absolute(base_url, relative_url)
    local base = parse(base_url)
    local relative = parse(relative_url)
    if not base then return relative_url
    elseif not relative then return base_url
    elseif relative.scheme then return relative_url
    else
        relative.scheme = base.scheme
        if not relative.authority then
            relative.authority = base.authority
            if not relative.path then
                relative.path = base.path
                if not relative.params then
                    relative.params = base.params
                    if not relative.query then
                        relative.query = base.query
                    end
                end
            else     
                relative.path = absolute_path(base.path or "", relative.path)
            end
        end
        return build(relative)
    end
end

-----------------------------------------------------------------------------
-- Breaks a path into its segments, unescaping the segments
-- Input
--   path
-- Returns
--   segment: a table with one entry per segment
-----------------------------------------------------------------------------
function parse_path(path)
	local parsed = {}
	path = path or ""
	--path = string.gsub(path, "%s", "")
	string.gsub(path, "([^/]+)", function (s) table.insert(parsed, s) end)
	for i = 1, table.getn(parsed) do
		parsed[i] = unescape(parsed[i])
	end
	if string.sub(path, 1, 1) == "/" then parsed.is_absolute = 1 end
	if string.sub(path, -1, -1) == "/" then parsed.is_directory = 1 end
	return parsed
end

-----------------------------------------------------------------------------
-- Builds a path component from its segments, escaping protected characters.
-- Input
--   parsed: path segments
--   unsafe: if true, segments are not protected before path is built
-- Returns
--   path: corresponding path stringing
-----------------------------------------------------------------------------
function build_path(parsed, unsafe)
	local path = ""
	local n = table.getn(parsed)
	if unsafe then
		for i = 1, n-1 do
			path = path .. parsed[i]
			path = path .. "/"
		end
		if n > 0 then
			path = path .. parsed[n]
			if parsed.is_directory then path = path .. "/" end
		end
	else
		for i = 1, n-1 do
			path = path .. protect_segment(parsed[i])
			path = path .. "/"
		end
		if n > 0 then
			path = path .. protect_segment(parsed[n])
			if parsed.is_directory then path = path .. "/" end
		end
	end
	if parsed.is_absolute then path = "/" .. path end
	return path
end
