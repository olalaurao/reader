-- SPDX-License-Identifier: AGPL-3.0-only

local Html = {}

local function escapeHtml(value)
    value = tostring(value or "")
    return (value
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;"))
end

local function bodyFragment(content)
    local lower = content:lower()
    local body_start, body_open_end = lower:find("<body[^>]*>")
    if not body_start then
        return content
    end

    local body_close_start = lower:find("</body%s*>", body_open_end + 1)
    if body_close_start then
        return content:sub(body_open_end + 1, body_close_start - 1)
    end
    return content:sub(body_open_end + 1)
end

function Html.build(document)
    assert(type(document) == "table", "document is required")
    local content = document.html_content
    if type(content) ~= "string" or content:match("^%s*$") then
        return nil, {
            kind = "content",
            retryable = false,
            message = "Reader did not provide processed HTML content for this article.",
        }
    end

    local title = document.title
    if type(title) ~= "string" or title == "" then
        title = "Untitled"
    end

    local head = {
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        '<meta charset="UTF-8">',
        "<title>" .. escapeHtml(title) .. "</title>",
    }
    if type(document.author) == "string" and document.author ~= "" then
        head[#head + 1] = '<meta name="author" content="' .. escapeHtml(document.author) .. '">'
    end
    head[#head + 1] = [[<style>
img { max-width: 100%; height: auto; }
.rw-image-placeholder { display: block; margin: 0.8em 0; padding: 0.5em; border: 1px solid #888; font-style: italic; }
</style>]]
    head[#head + 1] = "</head>"
    head[#head + 1] = "<body>"
    head[#head + 1] = '<article data-readwise-reader="true">'

    return table.concat(head, "\n")
        .. "\n" .. bodyFragment(content)
        .. "\n</article>\n</body>\n</html>\n"
end

Html._escapeHtml = escapeHtml
Html._bodyFragment = bodyFragment

return Html
