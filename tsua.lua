local tsua_version = "v1.3"
local tsua = {}
tsua.__index = tsua

function tsua.new(config)
    config = config or {}
    return setmetatable({
        routes = {},
        dynamic_routes = {},
        static_dirs = {},
        -- config starts here

        request_logging = config.request_logging ~= false, -- looks weird but it prevents unexpected behavior when setting a config, default is true
        max_body = config.max_body or (1024 * 1024), -- 1MB default max body in requests
        max_headers = config.max_headers or 30, -- default 30 max headers possible in requests
        timeout = config.timeout or 3, -- default 3s before dropping client
        error_handler = config.error_handler, -- custom error handler function config
        not_found = config.not_found,  -- path to a custom 404 html file, default is framework-provided page
        forbidden = config.forbidden, -- path to a custom 403 html file, default is framework-provided page
        internal_error = config.internal_error, -- path to a custom 500 html file, default is framework-provided page

        -- config ends here
    }, tsua)
end

local mime_types = {
    html = "text/html; charset=UTF-8",
    css  = "text/css",
    txt  = "text/plain",
    js   = "application/javascript",
    json = "application/json",
    pdf  = "application/pdf",
    xml  = "application/xml",
    zip  = "application/zip",
    png  = "image/png",
    jpg  = "image/jpeg",
    ico  = "image/x-icon",
    svg  = "image/svg+xml",
    gif  = "image/gif",
    webp = "image/webp",
    mp4  = "video/mp4",
    webm = "video/webm",
    mp3  = "audio/mpeg",
    wav  = "audio/wav",
    ogg  = "audio/ogg",
}

local errors = {
    ["403"] = {
        title = "Forbidden",
        config = "forbidden",
        message = "Access to the requested resource is forbidden - tsua"
    },

    ["404"] = {
        title = "Not Found",
        config = "not_found",
        message = "The requested resource doesn't exist or could not be found - tsua"
    },

    ["500"] = {
        title = "Internal Server Error",
        config = "internal_error",
        message = "The server encountered an unexpected error - tsua"
    }
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

local function parse_encoded(body)
    local params = {}
    for key, value in body:gmatch("([^&=]+)=([^&=]+)") do -- i hope i dont have to touch this code for a while
        params[url_decode(key)] = url_decode(value)
    end
    return params
end

local function send(client, status, headers, body) -- func to send http data
    status = status or "200 OK" -- get the number
    headers = headers or {}
    body = body or ""

    assert(type(client) == "userdata", "client must be userdata")
    assert(type(status) == "string", "status must be string")
    assert(type(headers) == "table", "headers must be table")
    assert(type(body) == "string", "body must be string")

    client:send(build_response(status, headers, body))
end

-- default, universal page for errors
local function default_error_page(status_code, status_text, message)
    return string.format([[
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>%s %s</title>
    <style>
        body { min-height: 100vh; margin: 0; display: grid; place-items: center; font-family: system-ui, sans-serif; background: #f7f7fb; color: #20212a; }
        main { width: min(90vw, 34rem); padding: 2rem; border: 1px solid #d9dbe8; border-radius: 0.75rem; background: #fff; }
        p:first-child { margin: 0 0 0.75rem; color: #696d7d; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
        h1 { margin: 0; font-size: clamp(2rem, 8vw, 4rem); line-height: 1; }
        p:last-child { margin: 1rem 0 0; color: #4d5163; line-height: 1.6; }
        @media (prefers-color-scheme: dark) {
            body { background: #11131a; color: #f4f5f8; }
            main { border-color: #2a2d3a; background: #191c26; }
            p:first-child { color: #aeb4c5; }
            p:last-child { color: #c5cad8; }
        }
    </style>
</head>
<body>
    <main>
        <p>%s</p>
        <h1>%s</h1>
        <p>%s</p>
    </main>
</body>
</html>]], status_code, status_text, status_code, status_text, message)
end

-- func to make it easier to serve pretty much any error
local function send_error_page(self, client, status, custom_path, fallback_body)
    if custom_path then
        local file = io.open(custom_path, "rb")
        if file then
            local content = file:read("*all")
            file:close()
            send(client, status, { ["Content-Type"] = "text/html; charset=UTF-8", ["Connection"] = "close" }, content)
            return
        end
    end

    send(client, status, { ["Content-Type"] = "text/html; charset=UTF-8", ["Connection"] = "close" }, fallback_body)
end

local function cleanup(sock, coroutines, birth_times, read_list) -- func to clean up sockets for some reason
    coroutines[sock] = nil
    birth_times[sock] = nil
    for i, s in ipairs(read_list) do
        if s == sock then
            table.remove(read_list, i)
            break
        end
    end
    sock:close()
end

local function receive_line(client)
    while true do
        local line, err = client:receive("*l") -- get data (maybe lol)
        if line then
            return line  -- got data, return it
        elseif err == "timeout" then
            coroutine.yield()  -- no data yet, so maybe later
        else
            return nil  -- error, client's problem now LOL
        end
    end
end

local function receive_bytes(client, length) -- literally just almost the same thing as the function above
    while true do
        local data, err = client:receive(length)
        if data then
            return data
        elseif err == "timeout" then
            coroutine.yield()
        else
            return nil
        end
    end
end

local function register_dynamic(self, method, path, handler)
    local pattern = "^" .. path:gsub("<([%w_]+)>", "([^/]+)") .. "$"
    local param_names = {}
    for name in path:gmatch("<([%w_]+)>") do
        table.insert(param_names, name)
    end
    table.insert(self.dynamic_routes, {
        method = method,
        pattern = pattern,
        param_names = param_names,
        handler = handler
    })
end

local function handle_request(instance, client)
    local status_code = "???" -- status code, should be set later on in the func

    local function send_local(status, headers, body)
        status_code = status:match("^(%d+)") -- moooooreeee reegeeeeex
        send(client, status, headers, body)
    end

    
    local function send_error(code)
        local err = errors[code]

        send_error_page(
            instance,
            client,
            code .. " " .. err.title,
            instance[err.config],
            default_error_page(code, err.title, err.message)
        )

        status_code = code
    end

    local request_line = receive_line(client)  -- get request line
    if not request_line then return end  -- deny weird clients

    local method, path = request_line:match("^(%S+)%s+(%S+)") -- parse method and the path

    if not method or not path then -- deny weird clients
        send_local("400 Bad Request", { ["Content-Type"] = "text/plain" }, "400 Bad Request")
        if instance.request_logging then print("??? ??? -> 400") end
        return
    end

    path = url_decode(path)

    local query_string
    path, query_string = path:match("^([^?]*)%??(.*)") -- MORE WEIRD REGEX!!! I HATE THIS WORLD

    local query = {}
    if query_string and query_string ~= "" then
        query = parse_encoded(query_string) -- parse query_string before adding it to req
    end

    if path ~= "/" and path:sub(-1) == "/" then
        path = path:sub(1, -2) -- remove trailing slash
    end

    if path:find("%.%.") then -- THE GREATEST SECURITY KNOWN TO MANKIND
        send_error("403")
        if instance.request_logging then print(method.." "..path.." -> 403") end
        return
    end

    local headers = {}
    local header_count = 0
    while header_count < instance.max_headers do -- parse headers, max headers to prevent malicious clients overloading the server
        local line = receive_line(client)
        if not line or line == "" then break end -- blank line = end of headers

        local key, value = line:match("^([^:]+):%s*(.+)")
        if key and value then
            headers[key:lower()] = value -- lowercase keys for consistent lookups
        end
        header_count = header_count + 1
    end

    local body = ""
    if method == "POST" or method == "PUT" then -- parse body for methods with form data
        local length = tonumber(headers["content-length"])
        if length and length > 0 then
            if length > instance.max_body then -- combats malicious clients
                send_local("413 Content Too Large", { ["Content-Type"] = "text/plain" }, "413 Content Too Large")
                if instance.request_logging then print(method.." "..path.." -> 413") end
                return
            end
            body = receive_bytes(client, length) or ""
        end
    end

    -- check static directories before route lookup
    local static_handled = false
    for prefix, dir in pairs(instance.static_dirs) do
        if path:sub(1, #prefix) == prefix then
            local file_path = dir .. path:sub(#prefix + 1)
            local file = io.open(file_path, "rb")

            if file then
                local content = file:read("*all")
                file:close()
                send_local("200 OK", {
                    ["Content-Type"] = get_mime(file_path),
                    ["Connection"] = "close"
                }, content)
            else
                send_error("404")
            end

            static_handled = true
            break
        end
    end

    if not static_handled then -- create req and res objects
        local handler = instance.routes[method .. " " .. path]
        local dyn = {}
        local req = {
            method = method,
            path = path,
            headers = headers,
            body = body,
            params = (method == "POST" or method == "PUT") and parse_encoded(body) or {},
            query = query,
            dyn = dyn
        }
        local res = {}

        if not handler then -- no routes registered, try dynamic
            for _, route in ipairs(instance.dynamic_routes) do
                if route.method == method then
                    local captures = { path:match(route.pattern) }
                    if #captures > 0 then -- if any match found
                        handler = route.handler
                        for i, name in ipairs(route.param_names) do
                            local value = captures[i]
                            if value:find("%.%.") or value:find("[/\\%z]") then
                                send_error("403")
                                if instance.request_logging then print(method .. " " .. path .. " -> 403") end
                                return
                            end
                            dyn[name] = url_decode(value)
                        end
                        break
                    end
                end
            end
        end

        function res:send(status, res_headers, res_body) -- send general data
            send_local(status, res_headers or {}, res_body or "")
        end

        function res:serve(file_path) -- serve any file from disk
            local file = io.open(file_path, "rb")

            if file then
                local content = file:read("*all")
                file:close()
                self:send("200 OK", { ["Content-Type"] = get_mime(file_path), ["Connection"] = "close" }, content)
            else
                send_error("404")
            end
        end

        function res:redirect(new_page) -- redirect helper
            self:send("301 Moved Permanently", {["Location"] = new_page}, "")
        end

        function res:json(encode_fn, data, status)
            local ok, encoded = pcall(encode_fn, data)
            if not ok then
                send_error("500")
                print("res:json() encode error: " .. tostring(encoded))
                return
            end
            send_local(status or "200 OK", {["Content-Type"] = "application/json", ["Connection"] = "close"}, encoded)
        end

        function res.escape(str) -- html escape helper
            str = str:gsub("&", "&amp;") -- must be first, otherwise it escapes the & in other replacements!!
            str = str:gsub("<", "&lt;")
            str = str:gsub(">", "&gt;")
            str = str:gsub('"', "&quot;")
            str = str:gsub("'", "&#39;")
            return str
        end

        -- run route
        if handler then
            local ok, err = pcall(handler, req, res)
            if not ok then
                if instance.error_handler then
                    instance.error_handler(err, req, res)
                else
                    send_error("500")
                    print("handler error: " .. tostring(err))
                end
            end
        else
            send_error("404")
        end
    end

    if instance.request_logging then print(method.." "..path.." -> "..status_code) end -- log request if enabled
end

-- handle GET
function tsua:get(path, handler)
    if path:find("<") then -- for dynamic routing
        register_dynamic(self, "GET", path, handler)
    else
        self.routes["GET " .. path] = handler
    end
end

-- handle POST
function tsua:post(path, handler)
    if path:find("<") then -- for dynamic routing
        register_dynamic(self, "POST", path, handler)
    else
        self.routes["POST " .. path] = handler
    end
end

-- handle PUT
function tsua:put(path, handler)
    if path:find("<") then -- for dynamic routing
        register_dynamic(self, "PUT", path, handler)
    else
        self.routes["PUT " .. path] = handler
    end
end

-- handle DELETE
function tsua:delete(path, handler)
    if path:find("<") then -- for dynamic routing
        register_dynamic(self, "DELETE", path, handler)
    else
        self.routes["DELETE " .. path] = handler
    end
end

-- compose static serving
function tsua:static(url_prefix, dir_path)
    self.static_dirs[url_prefix] = dir_path
end

-- start server
function tsua:listen(port)
    local socket = require("socket")
    local server = assert(socket.bind("*", port))
    server:settimeout(0) -- non-blocking

    print("tsua "..tsua_version.." - server running on http://0.0.0.0:" .. port)
    if self.request_logging then
        print("request logging enabled\n-----")
    end

    local coroutines = {}
    local read_list = { server }
    local birth_times = {}

    while true do
        local readable = socket.select(read_list, nil, 0.01) -- which socket has data ready??!
        local now = socket.gettime()
        local expired = {}
        for sock, born in pairs(birth_times) do
            if now - born > self.timeout then
                table.insert(expired, sock) -- collect all the connections living rentfree...
            end
        end

        for _, sock in ipairs(expired) do
            cleanup(sock, coroutines, birth_times, read_list) -- ...and DESTROY THEM
        end

        for _, sock in ipairs(readable) do
            if sock == server then
                local client = server:accept() -- accept new client
                if client then
                    client:settimeout(0) -- non-blocking

                    local co = coroutine.create(function() -- make coroutine for client
                        handle_request(self, client)
                    end)
                    coroutines[client] = co
                    birth_times[client] = socket.gettime()
                    table.insert(read_list, client) -- add it to the list
                end
            else
                local co = coroutines[sock]
                if co then
                    local ok, err = coroutine.resume(co)
                    if not ok or coroutine.status(co) == "dead" then
                        cleanup(sock, coroutines, birth_times, read_list) -- discard dead clients
                    end
                end
            end
        end
    end -- HELLO AND WELCOME TO MY PYRAMID. CODE-READING TOURISTS PAY A FEE OF 5 GAJILLION DOLLARS.
end

return tsua