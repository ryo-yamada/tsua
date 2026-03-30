local tsua = {}
tsua.__index = tsua

function tsua.new(config)
    config = config or {}
    return setmetatable({
        routes = {},
        static_dirs = {},
        -- config starts here
        
        request_logging = config.request_logging ~= false, -- looks weird but it prevents unexpected behavior when setting a config, default is true
        max_body = config.max_body or (1024 * 1024), -- 1MB default max body in requests
        max_headers = config.max_headers or 30, -- default 30 max headers possible in requests
        timeout = config.timeout or 3, -- default 3s before dropping client
        not_found = config.not_found,  -- path to a custom 404 html file, default is framework-provided page
        forbidden = config.forbidden, -- path to a custom 403 html file, default is framework-provided page
        error_handler = config.error_handler, -- custom error handler function config

        -- config ends here
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
    return mime_types[ext] or "application/octet-stream" -- fallback for unknown types
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

local function url_decode(str) -- i don't know how decoding works! ^_^
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return str
end

local function parse_body(body)
    local params = {}
    for key, value in body:gmatch("([^&=]+)=([^&=]+)") do
        params[url_decode(key)] = url_decode(value)
    end
    return params
end

local status_code = "???"
local function send(client, status, headers, body) -- func to send http data
    status = status or "200 OK" -- get the number
    status_code = status:match("^(%d+)")
    headers = headers or {}
    body = body or ""

    assert(type(client) == "userdata", "client must be userdata")
    assert(type(status) == "string", "status must be string")
    assert(type(headers) == "table", "headers must be table")
    assert(type(body) == "string", "body must be string")

    client:send(build_response(status, headers, body))
end

local function send_404(self, client)
    if self.not_found then
        local file = io.open(self.not_found, "rb")
        if file then
            local content = file:read("*all")
            file:close()
            send(client, "404 Not Found", { ["Content-Type"] = "text/html" }, content)
        end
    else
        send(client, "404 Not Found", { ["Content-Type"] = "text/html" }, "<h1>404 Not Found</h1>")
    end
end

local function send_403(self, client)
    if self.forbidden then
        local file = io.open(self.forbidden, "rb")
        if file then
            local content = file:read("*all")
            file:close()
            send(client, "403 Forbidden", { ["Content-Type"] = "text/html" }, content)
        end
    else
        send(client, "403 Forbidden", { ["Content-Type"] = "text/html" }, "<h1>403 Forbidden</h1>")
    end
end

-- handle GET
function tsua:get(path, handler)
    self.routes["GET " .. path] = handler
end

-- handle POST
function tsua:post(path, handler)
    self.routes["POST " .. path] = handler
end

-- compose static serving
function tsua:static(url_prefix, dir_path)
    self.static_dirs[url_prefix] = dir_path
end

-- start server
function tsua:listen(port)
    local socket = require("socket")
    local server = assert(socket.bind("*", port))

    local server_instance = self -- required for functions called from the res object

    print("server running on http://127.0.0.1:" .. port)
    if self.request_logging then
        print("request logging enabled\n-----")
    end

    while true do
        status_code = "???" -- reset status code, prevents misleading logs
        local client = server:accept()
        client:settimeout(self.timeout)

        local request_line = client:receive("*l") -- get request line

        if not request_line then -- deny weird clients
            client:close()
            goto continue
        end

        local method, path = request_line:match("^(%S+)%s+(%S+)") -- parse method and the path

        if not method or not path then -- deny weird clients
            send(client, "400 Bad Request", { ["Content-Type"] = "text/plain" }, "400 Bad Request")
            if self.request_logging then print("??? ??? -> 400") end
            client:close()
            goto continue
        end

        if path:find("%.%.") then -- THE GREATEST SECURITY KNOWN TO MANKIND
            send_403(self, client)
            if self.request_logging then print(method.." "..path.." -> 403") end
            client:close()
            goto continue
        end

        local headers = {}
        local header_count = 0
        while header_count < self.max_headers do -- parse headers, max headers to prevent malicious clients overloading the server
            local line = client:receive("*l")
            if not line or line == "" then break end -- blank line = end of headers

            local key, value = line:match("^([^:]+):%s*(.+)")
            if key and value then
                headers[key:lower()] = value -- lowercase keys for consistent lookups
            end
            header_count = header_count + 1
        end

        local body = ""
        if method == "POST" then -- parse body
            local length = tonumber(headers["content-length"])
            if length and length > 0 then
                if length > self.max_body then -- combats malicious clients
                    send(client, "413 Content Too Large", { ["Content-Type"] = "text/plain" }, "413 Content Too Large")
                    if self.request_logging then print(method.." "..path.." -> 413") end
                    client:close()
                    goto continue
                end
                body = client:receive(length)
            end
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
                    send_404(self, client)
                end

                static_handled = true
                break
            end
        end

        if not static_handled then
            local handler = self.routes[method .. " " .. path]
            local req = { method = method, path = path, headers = headers, body = body, params = method == "POST" and parse_body(body) or {} }
            local res = {}

            function res:send(status, res_headers, res_body)
                send(client, status, res_headers or {}, res_body or "")
            end

            function res:serve(file_path) -- serve html page
                local file = io.open(file_path, "rb")

                if file then
                    local content = file:read("*all")
                    file:close()
                    self:send("200 OK", { ["Content-Type"] = get_mime(file_path), ["Connection"] = "close" }, content)
                else
                    send_404(server_instance, client)
                end
            end

            -- run route
            if handler then
                local ok, err = pcall(handler, req, res)
                if not ok then
                    if self.error_handler then
                        self.error_handler(err, req, res)
                    else
                        send(client, "500 Internal Server Error", {["Content-Type"] = "text/plain"}, "500 Internal Server Error")
                        print("handler error: " .. tostring(err))
                    end
                end
            else
                send_404(self, client)
            end
        end

        if self.request_logging then print(method.." "..path.." -> "..status_code) end -- log request if enabled

        client:close()
        ::continue::
    end
end

return tsua