import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


def text(value):
    return str(value or "").encode("utf-8", "replace").decode("utf-8").replace("\0", "")


request = json.load(sys.stdin)
hints = {"urgency": GLib.Variant("y", min(2, max(0, int(request.get("urgency", 1)))))}
if request.get("glyph"):
    hints["omarchy-glyph"] = GLib.Variant("s", text(request["glyph"]))
if request.get("exec"):
    hints["omarchy-exec-argv"] = GLib.Variant("s", json.dumps([text(a) for a in request["exec"]]))
replaces = min(0xFFFFFFFF, max(0, int(request.get("replaces", 0))))
args = GLib.Variant("(susssasa{sv}i)", (
    "Pigeon", replaces, "", text(request.get("summary")), text(request.get("body")), [], hints, -1))
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
reply = bus.call_sync(
    "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
    "Notify", args, GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 10000, None)
print(reply.unpack()[0])
