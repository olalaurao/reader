-- SPDX-License-Identifier: AGPL-3.0-only
-- Test-only compatibility wrapper. Production uses KOReader's lua-ljsqlite3/init.

local sqlite3 = require("lsqlite3")

local Compat = {}

local function check(db, rc)
    if rc ~= sqlite3.OK and rc ~= sqlite3.ROW and rc ~= sqlite3.DONE then
        error(db:errmsg())
    end
    return rc
end

function Compat.open(path)
    local raw = assert(sqlite3.open(path))
    local conn = {}

    function conn:exec(sql)
        check(raw, raw:exec(sql))
        return true
    end

    function conn:rowexec(sql)
        local stmt = assert(raw:prepare(sql))
        local rc = check(raw, stmt:step())
        if rc ~= sqlite3.ROW then
            stmt:finalize()
            return nil
        end
        local values = stmt:get_values()
        stmt:finalize()
        if #values == 1 then
            return values[1]
        end
        return values
    end

    function conn:prepare(sql)
        local raw_stmt = assert(raw:prepare(sql))
        local stmt = {}

        function stmt:reset()
            raw_stmt:reset()
            return self
        end

        function stmt:clearbind()
            if raw_stmt.clear_bindings then
                raw_stmt:clear_bindings()
            end
            return self
        end

        function stmt:bind(...)
            check(raw, raw_stmt:bind_values(...))
            return self
        end

        function stmt:step()
            local rc = check(raw, raw_stmt:step())
            if rc == sqlite3.ROW then
                return raw_stmt:get_values()
            end
            return nil
        end

        function stmt:close()
            raw_stmt:finalize()
        end

        return stmt
    end

    function conn:close()
        raw:close()
    end

    return conn
end

return Compat
