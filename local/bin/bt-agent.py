#!/usr/bin/env python3
# Агент сопряжения Bluetooth для сессии без blueman: hyprstack своего агента не имеет,
# и bluetoothd отклоняет запросы подтверждения ("No agent available").
# Подтверждает сопряжение/доступ к сервисам автоматически; переподключается при рестарте bluetoothd.
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_PATH = "/org/hyprstack/btagent"
CAPABILITY = "NoInputNoOutput"


class Agent(dbus.service.Object):
    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print(f"authorize service {device} {uuid}", flush=True)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        return "0000"

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        return dbus.UInt32(0)

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        print(f"confirm {device} {passkey:06d}", flush=True)
        set_trusted(device)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        print(f"authorize {device}", flush=True)
        set_trusted(device)

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        pass


def set_trusted(device):
    # Доверенные устройства (геймпады, наушники) потом сами переподключаются.
    try:
        props = dbus.Interface(bus.get_object("org.bluez", device), "org.freedesktop.DBus.Properties")
        props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
    except dbus.DBusException as e:
        print(f"trust failed: {e}", flush=True)


def register(*_):
    try:
        manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
        manager.RegisterAgent(AGENT_PATH, CAPABILITY)
        manager.RequestDefaultAgent(AGENT_PATH)
        print("agent registered", flush=True)
    except dbus.DBusException as e:
        print(f"register failed: {e}", flush=True)


def on_owner_changed(name, old, new):
    if name == "org.bluez" and new:
        GLib.timeout_add(500, lambda: register() or False)


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
Agent(bus, AGENT_PATH)
bus.add_signal_receiver(on_owner_changed, "NameOwnerChanged", "org.freedesktop.DBus",
                        arg0="org.bluez")
if bus.name_has_owner("org.bluez"):
    register()
GLib.MainLoop().run()
