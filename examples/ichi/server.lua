local Tsua = require("tsua")
local app = Tsua.new({ --[[request_logging = false]] })

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