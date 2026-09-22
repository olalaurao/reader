-- SPDX-License-Identifier: AGPL-3.0-only

local Reader = require("api/reader")

return function()
    do
        local captured
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return "abc123"
                end,
            },
            http = {
                request = function(_, options)
                    captured = options
                    return { status = 204, headers = {}, body = "" }
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == true)
        assert(err == nil)
        assert(captured.method == "GET")
        assert(captured.headers.Authorization == "Token abc123")
    end

    do
        local called = false
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return nil
                end,
            },
            http = {
                request = function()
                    called = true
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == nil)
        assert(err.kind == "auth")
        assert(called == false)
    end

    do
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return "abc123"
                end,
            },
            http = {
                request = function()
                    return nil, { kind = "auth", retryable = false }
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == nil)
        assert(err.kind == "auth")
    end
end
