-- SPDX-License-Identifier: AGPL-3.0-only

local Images = require("content/images")

local PNG = "\137PNG\r\n\26\n" .. string.rep("x", 20)
local JPG = "\255\216\255" .. string.rep("j", 20)

local function newInstaller()
    local state = { files = {} }
    return {
        state = state,
        fileExists = function(_, path)
            return state.files[path] ~= nil
        end,
        install = function(_, body, path)
            state.files[path] = body
            return { path = path }
        end,
    }
end

return function()
    do
        local calls = {}
        local installer = newInstaller()
        local images = Images:new{
            http = {
                request = function(_, request)
                    calls[#calls + 1] = request
                    if request.url:find("one.png", 1, true) then
                        return { status = 200, headers = { ["Content-Type"] = "image/png" }, body = PNG }
                    end
                    if request.url:find("two.jpg", 1, true) then
                        return { status = 200, headers = {}, body = JPG }
                    end
                    return nil, { kind = "timeout", retryable = true }
                end,
            },
            installer = installer,
            per_image_max = 1024,
            total_max = 4096,
            max_images = 5,
            resolve_url = function(src)
                if src:sub(1, 2) == "//" then return "https:" .. src end
                return src
            end,
        }

        local html, report = images:localize({
            html_content = [[
<p>before</p>
<picture><source srcset="https://cdn.example/one@2x.png 2x">
<img src="https://cdn.example/one.png" alt="One">
</picture>
<img src="https://cdn.example/one.png" alt="Duplicate">
<img src="//cdn.example/two.jpg" alt="Two">
<img src="https://cdn.example/missing.png" alt="Missing">
<p>after</p>]],
        }, "/root/Articles/.rw-assets-id", ".rw-assets-id")

        assert(report.downloaded == 2)
        assert(report.failed == 1)
        assert(report.skipped == 0)
        assert(report.bytes == #PNG + #JPG)
        assert(#calls == 3, "duplicate image URL must not download twice")
        assert(html:find('src="%.rw%-assets%-id/img%-001%.png"'))
        assert(html:find('src="%.rw%-assets%-id/img%-002%.jpg"'))
        assert(html:find("Missing", 1, true))
        assert(html:find("image unavailable", 1, true))
        assert(not html:find("<source", 1, true))
        assert(not html:find("<picture", 1, true))
        assert(not html:find("https://cdn.example/one.png", 1, true))
        assert(installer.state.files["/root/Articles/.rw-assets-id/img-001.png"] == PNG)
        assert(installer.state.files["/root/Articles/.rw-assets-id/img-002.jpg"] == JPG)
    end

    do
        local installer = newInstaller()
        local requested = {}
        local images = Images:new{
            http = {
                request = function(_, request)
                    requested[#requested + 1] = request.url
                    return { status = 200, headers = { ["Content-Type"] = "image/png" }, body = PNG }
                end,
            },
            installer = installer,
            per_image_max = 1024,
            total_max = 4096,
            max_images = 5,
            resolve_url = function(src) return src end,
        }

        local html, report = images:localize({
            html_content = [[
<picture>
  <source srcset="https://cdn.example/small.png 400w, https://cdn.example/good.png 1000w, https://cdn.example/huge.png 1800w">
  <img src="data:image/gif;base64,placeholder" alt="Responsive">
</picture>
<img src="data:image/gif;base64,placeholder" data-src="https://cdn.example/lazy.png" alt="Lazy">
<img src="https://cdn.example/fallback.png" srcset="https://cdn.example/set-small.png 320w, https://cdn.example/set-good.png 900w" alt="Srcset">
]],
        }, "/root/assets", "assets")

        assert(report.candidates == 3)
        assert(report.responsive_promoted == 1)
        assert(report.downloaded == 3)
        assert(#requested == 3)
        assert(requested[1] == "https://cdn.example/good.png")
        assert(requested[2] == "https://cdn.example/lazy.png")
        assert(requested[3] == "https://cdn.example/set-good.png")
        assert(not html:find("data:image", 1, true))
        assert(html:find('src="assets/img%-001%.png"'))
        assert(html:find('src="assets/img%-002%.png"'))
        assert(html:find('src="assets/img%-003%.png"'))
    end

    do
        local installer = newInstaller()
        local requests = 0
        local images = Images:new{
            http = {
                request = function()
                    requests = requests + 1
                    return { status = 200, headers = { ["Content-Type"] = "image/png" }, body = PNG }
                end,
            },
            installer = installer,
            enabled = false,
        }
        local html, report = images:localize({
            html_content = '<p>A</p><img src="https://x/a.png" alt="A"><p>B</p>',
        }, "/root/assets", "assets")
        assert(requests == 0)
        assert(report.skipped == 1)
        assert(html:find("image download disabled", 1, true))
        assert(html:find("<p>B</p>", 1, true))
    end

    do
        local images = Images:new{
            http = {
                request = function(_, request)
                    assert(request.max_body_bytes == 5)
                    return nil, { kind = "too_large", retryable = false }
                end,
            },
            installer = newInstaller(),
            per_image_max = 5,
            total_max = 5,
            max_images = 1,
        }
        local html, report = images:localize({
            html_content = '<img src="https://x/huge.png" alt="Huge"><p>still text</p>',
        }, "/root/assets", "assets")
        assert(report.skipped == 1)
        assert(report.failed == 0)
        assert(html:find("image too large", 1, true))
        assert(html:find("still text", 1, true))
    end

    assert(Images._detectExt(PNG, {}) == "png")
    assert(Images._detectExt(JPG, {}) == "jpg")
    assert(Images._detectExt("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>", {}) == "svg")
end
