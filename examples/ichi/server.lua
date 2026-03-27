local Tsua = require("tsua")
local app = Tsua.new()

app:static("/static", "examples/ichi/static/style.css")

app:get("/", function(req, res)
    res:serve("examples/ichi/frontend/index.html")
end)

app:get("/otherpage", function(req, res)
    res:serve("examples/ichi/frontend/otherpage.html")
end)

app:listen(19999) -- serve on http://localhost:19999/