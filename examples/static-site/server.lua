local Tsua = require("tsua")
local app = Tsua.new({ -- init & config
    max_headers = 15,
    timeout = 2,
    not_found = "./frontend/404.html"
})

app:static("/static", "./static")

app:get("/", function(req, res)
    res:serve("./frontend/index.html")
end)

app:get("/otherpage", function(req, res)
    res:serve("./frontend/otherpage.html")
    if req.query.name then
        print(req.query.name) -- /otherpage?name=ryo -> "ryo"
    end
end)

app:get("/<page>", function(req, res) -- dynamic!!! serves whatever is passed if it is findable!!!
    res:serve("./frontend/"..req.dyn.page..".html")
end)

app:post("/submit", function(req, res)
    if req.params.name then
        print(req.params.name)  -- "ryo"
    end
end)

app:listen(19999) -- serve on http://0.0.0.0:19999/