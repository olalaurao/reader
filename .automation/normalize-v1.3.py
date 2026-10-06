from pathlib import Path

p = Path("readwisereader.koplugin/ui/sync.lua")
text = p.read_text()
old = '        string.format(_("Reader → KOReader pre-sync reconciliation: %s"), report.remote_highlight_import_status or _("not run")),'
new = '''        string.format(
            _("Reader → KOReader pre-sync reconciliation: %s"),
            report.remote_highlight_import_status or _("not run")
        ),'''
if old not in text:
    raise SystemExit("sync report anchor not found")
p.write_text(text.replace(old, new, 1))

p = Path("readwisereader.koplugin/tests/test_sync_ui.lua")
text = p.read_text()
old = '''        assert(SyncUI._errorText({
            kind = "worker",
            stage = "annotation_backlog",
        }):find("stage: annotation_backlog", 1, true))
'''
new = '        assert(SyncUI._errorText({ kind = "worker", stage = "annotation_backlog" }):find("annotation_backlog", 1, true))\n'
if old not in text:
    raise SystemExit("sync UI test anchor not found")
p.write_text(text.replace(old, new, 1))

print("v1.3 source anchors normalized")
