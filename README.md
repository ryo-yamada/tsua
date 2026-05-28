# tsua - Tiny Lua webserver framework
Tsua is a tiny, minimalistic HTTP server framework built on top of LuaSocket.

The framework allows you to simply serve files and send data over HTTP for something like a website, such as a portfolio, without messing with raw, low-level HTTP too much. It works similar to Express.js or Python's Flask.

Because Lua's runtime is pretty small compared to something like Python's Flask, tsua runs well on stuff like old devices, a tiny VPS, or even microcontrollers such as an ESP32 or Raspberry Pi Pico.

## Current status
Tsua is experimental and only encouraged for static websites where dynamic activity is limited. Security hardening is something I want to gladly work towards. When deploying publicly with tsua, it is recommended that you run it in a containerized environment like Docker.

## Use guide
- You must have Lua and LuaSocket installed

e.g. `luarocks install luasocket`
- You can simply download `tsua.lua` and require it in your `server.lua` file
- No dependencies beyond LuaSocket are required.

Basic example of a `server.lua` file (examples/ichi/server.lua):
```lua
local Tsua = require("tsua")
local app = Tsua.new({ -- init & config
    max_headers = 15,
    timeout = 2,
    not_found = "examples/ichi/frontend/404.html"
})

app:static("/static", "examples/ichi/static")

app:get("/", function(req, res)
    res:serve("examples/ichi/frontend/index.html")
end)

app:get("/otherpage", function(req, res)
    res:serve("examples/ichi/frontend/otherpage.html")
end)

app:post("/submit", function(req, res)
    if req.params.name then
        print(req.params.name)  -- "ryo"
    end
end)

app:listen(19999) -- serve on http://localhost:19999/
```

### req and res objects
Parse information about the request with *req*:
```lua
app:post("/sendcredentials", function(req, res)
    req.method -- POST
    req.path -- /sendcredentials
    req.headers -- table of headers
    req.body -- key1=abc&key2=123
    req.params.key1 -- abc
end)
```
These are the only objects that req contains.

*res* wraps the raw socket and provides helper methods:
```lua
app:get("/", function(req, res)
    res:serve("index.html") -- this line right here !!
end)

app:get("/oldpage", function(req, res)
    res:send("301 Moved Permanently", {["Location"] = "/new-page"}, "") -- this one aswell !!
end)
```
### Configuration
You can configure an instance from the framework to according to how you want it to be.

You can see how options are set in the `server.lua` example.

These are all the configurable options and their defaults:
```lua
request_logging = config.request_logging ~= false, -- looks weird but it prevents unexpected behavior when setting a config, default is true
max_body = config.max_body or (1024 * 1024), -- 1MB default max body in requests
max_headers = config.max_headers or 30, -- default 30 max headers possible in requests
timeout = config.timeout or 3, -- default 3s before dropping client
error_handler = config.error_handler, -- custom error handler function config
not_found = config.not_found,  -- path to a custom 404 html file, default is framework-provided page
forbidden = config.forbidden, -- path to a custom 403 html file, default is framework-provided page
```
---

## Contributing

Contribution is heavily encouraged, and I'm trying to keep tsua small and approachable for this reason

If you are:
- learning Lua
- interested in HTTP
- looking for something to contribute to

then I'm looking forward to working with you.

Issues, pull requests, feature suggestions, and discussion are all appreciated. If you're looking to contribute but aren't sure how, you can check the issue tracker, in which I or others might post some issues for you to look into.

Development is currently focused on:
- Security
- Dynamic support
- Developer experience enhancements

## Philosophy
This was a project I started just for fun, as I wanted to see how easy it would be to deliver a site over the web with a Lua backend. However, it started becoming its own little framework, and so I decided to publish it on GitHub. My plan is to continue developing it with a focus on simplicity.

This framework is aimed towards sites that don't have too much dynamic functionality. Portfolios, documentation, etc. However, I suppose when this framework continues development, it will probably be able to support more dynamic functionality.