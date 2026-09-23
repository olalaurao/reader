-- SPDX-License-Identifier: AGPL-3.0-only

package.path = "readwisereader.koplugin/?.lua;"
    .. "readwisereader.koplugin/?/init.lua;"
    .. package.path

local tests = {
    "tests.test_config",
    "tests.test_http",
    "tests.test_reader",
    "tests.test_reader_pagination",
    "tests.test_metadata_scan",
    "tests.test_library_ui",
    "tests.test_article_ui",
    "tests.test_filenames",
    "tests.test_html",
    "tests.test_installer",
    "tests.test_first_article",
    "tests.test_koreader_documents",
    "tests.test_collections",
    "tests.test_document_sync",
    "tests.test_sync_ui",
    "tests.test_storage_db",
    "tests.test_storage_repositories",
}

local passed = 0
for _, module_name in ipairs(tests) do
    local test = require(module_name)
    test()
    passed = passed + 1
    io.stdout:write("ok - " .. module_name .. "\n")
end

io.stdout:write(string.format("%d test module(s) passed\n", passed))
