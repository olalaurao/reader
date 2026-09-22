-- SPDX-License-Identifier: AGPL-3.0-only

local Html = require("content/html")

return function()
    local html, err = Html.build{
        title = 'A <title> & "quote"',
        author = "Autora & Co.",
        html_content = "<p>Olá, coração 🧠 — “aspas”.</p>",
    }
    assert(err == nil)
    assert(html:find('<meta charset="UTF-8">', 1, true))
    assert(html:find("A &lt;title&gt; &amp; &quot;quote&quot;", 1, true))
    assert(html:find('content="Autora &amp; Co."', 1, true))
    assert(html:find("<p>Olá, coração 🧠 — “aspas”.</p>", 1, true))
    assert(not html:find("<h1>A <title>", 1, true))

    local full = Html.build{
        title = "Body extraction",
        html_content = "<html><head><style>x</style></head><body><p>Visible only</p></body></html>",
    }
    assert(full:find("<p>Visible only</p>", 1, true))
    assert(not full:find("<style>x</style>", 1, true))

    local missing, missing_err = Html.build{ title = "No content" }
    assert(missing == nil)
    assert(missing_err.kind == "content")
end
