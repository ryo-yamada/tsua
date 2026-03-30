# Tsua - Tiny Lua webserver framework
Tsua is a tiny, minimalistic HTTP server framework built on top of LuaSocket. The framework allows you to achieve the goal of simply delivering files over HTTP and build a website, such as a portfolio, without messing with raw, low-level HTTP too much. It works similar to Express.js or Python's Flask.

An advantage that comes with using Tsua is that Lua's runtime is pretty small, so compared to something like Python's Flask, it uses significantly less system resources. Lua is also faster than Python in terms of raw execution speed. I'm also planning to try using LuaJIT some time soon, which will improve raw execution speed.

However, it mostly doesn't matter how fast a CPU can execute instructions if the context is a web server. The bottleneck is almost always I/O.

### IMPORTANT,
Right now, the use of Tsua is discouraged, as I have not implemented it asynchronously. There are also a lot more things that must be implemented, such as more HTTP method handling, and I am also afraid that the currently implemented security is not good enough to secure a more dynamic web application. For static sites however, there should be no security issues, but it can only handle a measly couple of people connecting at once due to it's synchronous nature. If you do still decide to host a website with this, I advise that you run it in a Docker container, as it isolates the application from the rest of the system. Everything that is currently planned to be implemented can be found in the roadmap at the bottom of this README.

No dependencies beyond LuaSocket are required.

## Use guide
- You must have Lua and LuaSocket installed

e.g. `luarocks install luasocket`
- You can simply download `tsua.lua` and require it in your `server.lua` file

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
not_found = config.not_found,  -- path to a custom 404 html file, default is framework-provided page
forbidden = config.forbidden, -- path to a custom 403 html file, default is framework-provided page
error_handler = config.error_handler, -- custom error handler function config
```
---

## Philosophy
This was a project I started just for fun, as I wanted to see how easy it would be to deliver a site over the web with a Lua backend. However, it started becoming its own little framework, and so I decided to publish it on GitHub. My plan is to continue developing it with a focus on simplicity. I myself seem to be learning a decent amount from this, and perhaps if you're learning Lua, this repository could also help you become a better programmer.

This framework is aimed towards sites that don't have too much dynamic functionality. Portfolios, documentation, etc. However, I suppose when this framework continues development, it will probably be able to support more dynamic functionality.

## Todo
- Implement async [TOP PRIORITY]
- DELETE method handling
- Query string parsing
- Documentation page that lists out all supported res methods, HTTP methods, etc

*I am planning to be slightly hands-off on this project, because I want to invite people to open issues, pull requests and discuss changes. Contribute!*
