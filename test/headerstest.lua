local socket = require("socket")
local headers = require("socket.headers")

-- the original hardcoded table this file used to contain, kept here so the
-- refactor to dynamic generation + a small anomaly table can be checked for
-- regressions.
local canonic = {
    ["accept"] = "Accept",
    ["accept-charset"] = "Accept-Charset",
    ["accept-encoding"] = "Accept-Encoding",
    ["accept-language"] = "Accept-Language",
    ["accept-ranges"] = "Accept-Ranges",
    ["action"] = "Action",
    ["alternate-recipient"] = "Alternate-Recipient",
    ["age"] = "Age",
    ["allow"] = "Allow",
    ["arrival-date"] = "Arrival-Date",
    ["authorization"] = "Authorization",
    ["bcc"] = "Bcc",
    ["cache-control"] = "Cache-Control",
    ["cc"] = "Cc",
    ["comments"] = "Comments",
    ["connection"] = "Connection",
    ["content-description"] = "Content-Description",
    ["content-disposition"] = "Content-Disposition",
    ["content-encoding"] = "Content-Encoding",
    ["content-id"] = "Content-ID",
    ["content-language"] = "Content-Language",
    ["content-length"] = "Content-Length",
    ["content-location"] = "Content-Location",
    ["content-md5"] = "Content-MD5",
    ["content-range"] = "Content-Range",
    ["content-transfer-encoding"] = "Content-Transfer-Encoding",
    ["content-type"] = "Content-Type",
    ["cookie"] = "Cookie",
    ["date"] = "Date",
    ["diagnostic-code"] = "Diagnostic-Code",
    ["dsn-gateway"] = "DSN-Gateway",
    ["etag"] = "ETag",
    ["expect"] = "Expect",
    ["expires"] = "Expires",
    ["final-log-id"] = "Final-Log-ID",
    ["final-recipient"] = "Final-Recipient",
    ["from"] = "From",
    ["host"] = "Host",
    ["if-match"] = "If-Match",
    ["if-modified-since"] = "If-Modified-Since",
    ["if-none-match"] = "If-None-Match",
    ["if-range"] = "If-Range",
    ["if-unmodified-since"] = "If-Unmodified-Since",
    ["in-reply-to"] = "In-Reply-To",
    ["keywords"] = "Keywords",
    ["last-attempt-date"] = "Last-Attempt-Date",
    ["last-modified"] = "Last-Modified",
    ["location"] = "Location",
    ["max-forwards"] = "Max-Forwards",
    ["message-id"] = "Message-ID",
    ["mime-version"] = "MIME-Version",
    ["original-envelope-id"] = "Original-Envelope-ID",
    ["original-recipient"] = "Original-Recipient",
    ["pragma"] = "Pragma",
    ["proxy-authenticate"] = "Proxy-Authenticate",
    ["proxy-authorization"] = "Proxy-Authorization",
    ["range"] = "Range",
    ["received"] = "Received",
    ["received-from-mta"] = "Received-From-MTA",
    ["references"] = "References",
    ["referer"] = "Referer",
    ["remote-mta"] = "Remote-MTA",
    ["reply-to"] = "Reply-To",
    ["reporting-mta"] = "Reporting-MTA",
    ["resent-bcc"] = "Resent-Bcc",
    ["resent-cc"] = "Resent-Cc",
    ["resent-date"] = "Resent-Date",
    ["resent-from"] = "Resent-From",
    ["resent-message-id"] = "Resent-Message-ID",
    ["resent-reply-to"] = "Resent-Reply-To",
    ["resent-sender"] = "Resent-Sender",
    ["resent-to"] = "Resent-To",
    ["retry-after"] = "Retry-After",
    ["return-path"] = "Return-Path",
    ["sender"] = "Sender",
    ["server"] = "Server",
    ["smtp-remote-recipient"] = "SMTP-Remote-Recipient",
    ["status"] = "Status",
    ["subject"] = "Subject",
    ["te"] = "TE",
    ["to"] = "To",
    ["trailer"] = "Trailer",
    ["transfer-encoding"] = "Transfer-Encoding",
    ["upgrade"] = "Upgrade",
    ["user-agent"] = "User-Agent",
    ["vary"] = "Vary",
    ["via"] = "Via",
    ["warning"] = "Warning",
    ["will-retry-until"] = "Will-Retry-Until",
    ["www-authenticate"] = "WWW-Authenticate",
    ["x-mailer"] = "X-Mailer",
}

local check_canonic = function(lower, expected)
    local got = headers.canonic[lower]
    if got ~= expected then
        print("canonic[" .. lower .. "] = " .. tostring(got) ..
            ", expected " .. expected)
        os.exit()
    end
end

print("testing all known header fields resolve to their canonical form")
for lower, expected in pairs(canonic) do
    check_canonic(lower, expected)
end

print("testing mixed/upper-case input normalizes correctly")
check_canonic("Content-Type", "Content-Type")
check_canonic("CONTENT-TYPE", "Content-Type")
check_canonic("ETAG", "ETag")
check_canonic("Www-Authenticate", "WWW-Authenticate")

print("testing novel unregistered headers are auto-titlecased")
check_canonic("x-request-id", "X-Request-Id")
check_canonic("x-custom-header-name", "X-Custom-Header-Name")
check_canonic("single", "Single")

print("testing setcanonic() registers a custom canonical capitalization")
headers.setcanonic("X-Request-ID")
check_canonic("x-request-id", "X-Request-ID")
check_canonic("X-REQUEST-ID", "X-Request-ID")

print("the library passed all tests")
