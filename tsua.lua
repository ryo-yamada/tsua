local tsua = {}
tsua.__index = tsua

function tsua.new(config)
    config = config or {}
    return setmetatable({
        routes = {},
        static_dirs = {},
        request_logging = config.request_logging ~= false, -- looks weird but it prevents unexpected behavior when setting a config
    }, tsua)
end

local mime_types = {
    html = "text/html; charset=UTF-8",
    css  = "text/css",
    js   = "application/javascript",
    json = "application/json",
    png  = "image/png",
    jpg  = "image/jpeg",
    ico  = "image/x-icon",
    svg  = "image/svg+xml",
    txt  = "text/plain"
}

local function get_mime(file_path)
    local ext = file_path:match("%.([^%.]+)$") -- i don't know how to use lua's spinoff of regex! ^_^
    return mime_types[ext] or "application/octet-stream"  -- fallback for unknown types
end

local function build_response(status, headers, body) -- func to build http response for client browser
    body = body or ""
    headers["Content-Length"] = #body

    local lines = { "HTTP/1.1 " .. status }

    for k, v in pairs(headers) do
        table.insert(lines, k .. ": " .. v)
    end

    table.insert(lines, "")
    table.insert(lines, body)

    return table.concat(lines, "\r\n")
end

local function send(client, status, headers, body) -- func to send http data
    status = status or "200 OK"
    headers = headers or {}
    body = body or ""

    assert(type(client) == "userdata", "client must be userdata")
    assert(type(status) == "string", "status must be string")
    assert(type(headers) == "table", "headers must be table")
    assert(type(body) == "string", "body must be string")

    client:send(build_response(status, headers, body))
end

-- compose GET
function tsua:get(path, handler)
    self.routes["GET " .. path] = handler
end

-- compose static serving
function tsua:static(url_prefix, dir_path)
    self.static_dirs[url_prefix] = dir_path
end

-- start server
function tsua:listen(port)
    local socket = require("socket")
    local server = assert(socket.bind("*", port))

    print("server running on http://127.0.0.1:" .. port)

    while true do
        local client = server:accept()
        client:settimeout(3)

        local request_line = client:receive("*l") -- get request line

        if not request_line then -- deny weird clients
            client:close()
            goto continue
        end

        if self.request_logging == true then
            print(request_line)
        end

        local method, path = request_line:match("^(%S+)%s+(%S+)") -- get method and the path

        if not method or not path then -- deny weird clients
            send(client, "400 Bad Request", {["Content-Type"] = "text/plain"}, "400 Bad Request")
            client:close()
            goto continue
        end

        if path:find("%.%.") then -- THE GREATEST SECURITY KNOWN TO MANKIND
            send(client, "403 Forbidden", {["Content-Type"] = "text/plain"}, "403 Forbidden")
            client:close()
            goto continue
        end

        local headers = {}
        local header_count = 0
        while header_count < 30 do -- parse headers, max of 30 to prevent malicious clients overloading the server
            local line = client:receive("*l")
            if not line or line == "" then break end  -- blank line = end of headers

            local key, value = line:match("^([^:]+):%s*(.+)")
            if key and value then
                headers[key:lower()] = value  -- lowercase keys for consistent lookups
            end
            header_count = header_count + 1
        end

        -- check static directories before route lookup
        local static_handled = false
        for prefix, dir in pairs(self.static_dirs) do
            if path:sub(1, #prefix) == prefix then
                local file_path = dir .. path:sub(#prefix + 1)
                local file = io.open(file_path, "rb")

                if file then
                    local content = file:read("*all")
                    file:close()
                    send(client, "200 OK", {
                        ["Content-Type"] = get_mime(file_path),
                        ["Connection"] = "close"
                    }, content)
                else
                    send(client, "404 Not Found", {["Content-Type"] = "text/html"}, "<h1>404 Not Found</h1>")
                end

                client:close()
                static_handled = true
                break
            end
        end
        if static_handled then goto continue end

        local handler = self.routes[method .. " " .. path]
        local req = { method = method, path = path, headers = headers }
        local res = {}

        function res:send(status, res_headers, body)
            send(client, status, res_headers or {}, body or "")
        end

        function res:serve(file_path) -- serve html page
            local file = io.open(file_path, "rb")

            if file then
                local content = file:read("*all")
                file:close()
                send(client, "200 OK", {["Content-Type"] = get_mime(file_path), ["Connection"] = "close"}, content)
            else
                send(client, "404 Not Found", {["Content-Type"] = "text/html"} , "<h1>404 Not Found</h1>")
            end
        end

        -- run route
        if handler then
            handler(req, res)
        else
            send(client, "404 Not Found", {["Content-Type"] = "text/html"}, "<h1>404 Not Found</h1>")
        end

        client:close()
        ::continue::
    end
end

return tsua