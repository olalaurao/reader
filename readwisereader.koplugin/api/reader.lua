-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Reader = {}
Reader.__index = Reader

function Reader:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        config = assert(options.config, "config is required"),
    }, self)
end

function Reader:validateToken()
    local token = self.config:getAccessToken()
    if not token then
        return nil, {
            kind = "auth",
            retryable = false,
            message = "Access token is not configured.",
        }
    end

    local response, err = self.http:request{
        method = "GET",
        url = Constants.AUTH_URL,
        headers = {
            ["Accept"] = "application/json",
            ["Authorization"] = "Token " .. token,
        },
        timeout_class = "api",
    }

    if not response then
        return nil, err
    end

    if response.status ~= 204 then
        return nil, {
            kind = "unknown",
            status = response.status,
            retryable = false,
            message = "Authentication returned an unexpected success status.",
        }
    end

    return true
end

return Reader
