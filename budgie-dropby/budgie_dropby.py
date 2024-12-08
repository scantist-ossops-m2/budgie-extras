#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Wnck", "3.0")
gi.require_version('Budgie', '1.0')
from gi.repository import Budgie, GObject, Gtk, Gio, Wnck, GLib
import os
import dropby_tools as db
import subprocess


"""
DropBy
Author: Jacob Vlijm
Copyright © 2017-2022 Ubuntu Budgie Developers
Website=https://ubuntubudgie.org
This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or any later version. This
program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU General Public License for more details. You
should have received a copy of the GNU General Public License along with this
program.  If not, see <https://www.gnu.org/licenses/>.
"""


class BudgieDropBy(GObject.GObject, Budgie.Plugin):
    """ This is simply an entry point into your Budgie Applet implementation.
        Note you must always override Object, and implement Plugin.
    """

    # Good manners, make sure we have unique name in GObject type system
    __gtype_name__ = "BudgieDropBy"

    def __init__(self):
        """ Initialisation is important.
        """
        GObject.Object.__init__(self)

    def do_get_panel_widget(self, uuid):
        """ This is where the real fun happens. Return a new Budgie.Applet
            instance with the given UUID. The UUID is determined by the
            BudgiePanelManager, and is used for lifetime tracking.
        """
        return BudgieDropByApplet(uuid)


class DropBySettings(Gtk.Grid):

    def __init__(self, setting):

        super().__init__()
        explanation = Gtk.Label()
        explanation.set_text(
            "The applet will show up when a usb device is connected."
        )
        explanation.set_xalign(0)
        explanation.set_line_wrap(True)
        self.attach(explanation, 0, 0, 1, 1)

        self.attach(Gtk.Label(""), 0, 1, 1, 1)
        popup_positionlabel = Gtk.Label()
        popup_positionlabel.set_text(
            "Dropby popup window position:"
        )
        popup_positionlabel.set_xalign(0)
        self.attach(popup_positionlabel, 0, 2, 1, 1)
        self.attach(Gtk.Label(""), 0, 3, 1, 1)
        # settings
        self.settings = Gio.Settings.new(
            "org.ubuntubudgie.plugins.budgie-dropby"
        )
        initially_active = self.settings.get_int("popup-corner")
        # anchor section
        anchorgrid = Gtk.Grid()
        leftspace = Gtk.Label("\t")
        centerlabel = Gtk.Label("\t")
        anchorgrid.attach(leftspace, 1, 0, 1, 1)
        anchorgrid.attach(centerlabel, 3, 1, 1, 1)
        # group
        nw = Gtk.RadioButton(group=None)
        ne = Gtk.RadioButton(group=nw)
        se = Gtk.RadioButton(group=nw)
        sw = Gtk.RadioButton(group=nw)
        self.buttons = [nw, ne, sw, se]
        self.buttons[initially_active - 1].set_active(True)
        pos = [[2, 0], [4, 0], [2, 2], [4, 2]]
        i = 0
        for button in self.buttons:
            button.connect("toggled", self.update_corner)
            anchorgrid.attach(button, pos[i][0], pos[i][1], 1, 1)
            i = i + 1
        self.attach(anchorgrid, 0, 5, 2, 1)
        self.show_all()

    def update_corner(self, togglebutton):
        newcorner = self.buttons.index(togglebutton) + 1
        self.settings.set_int("popup-corner", newcorner)


class BudgieDropByApplet(Budgie.Applet):
    """ Budgie.Applet is in fact a Gtk.Bin """
    manager = None

    def __init__(self, uuid):
        Budgie.Applet.__init__(self)
        self.uuid = uuid
        self.connect("destroy", Gtk.main_quit)
        app_path = os.path.dirname(os.path.abspath(__file__))
        self.tmp_path = os.getenv("XDG_RUNTIME_DIR") if "XDG_RUNTIME_DIR" in os.environ else os.getenv("HOME")
        self.copytrigger = os.path.join(self.tmp_path, ".dropby_icon_copy")
        self.copying = False
        self.winpath = os.path.join(app_path, "dropover")
        self.box = Gtk.EventBox()
        self.box.connect("button-press-event", self.create_windowtrigger)
        self.icon = Gtk.Image.new_from_icon_name(
            "budgie-dropby-symbolic", Gtk.IconSize.MENU
        )
        self.idle_icon = Gtk.Image.new_from_icon_name(
            "budgie-dropby-idle", Gtk.IconSize.MENU
        )
        self.smallsq_icon = Gtk.Image.new_from_icon_name(
            "budgie-dropbysmallsq-symbolic", Gtk.IconSize.MENU
        )
        self.bigsq_icon = Gtk.Image.new_from_icon_name(
            "budgie-dropbybigsq-symbolic", Gtk.IconSize.MENU
        )
        self.scr = Wnck.Screen.get_default()
        self.box.add(self.icon)
        self.curr_iconindex = 0
        self.add(self.box)
        self.box.show_all()
        self.show_all()
        self.setup_watching()
        self.start_dropover()
        self.refresh_from_idle()

    def set_icon_state(self):
        if not self.copying:
            self.refresh_from_idle()
        else:
            GLib.timeout_add_seconds(1, self.toggle_icons)

    def toggle_icons(self):
        if self.copying:
            for wdg in self.box.get_children():
                self.box.remove(wdg)
            if self.curr_iconindex == 0:
                nexticon = self.bigsq_icon
                self.curr_iconindex = 1
            elif self.curr_iconindex == 1:
                nexticon = self.idle_icon
                self.curr_iconindex = 2
            elif self.curr_iconindex == 2:
                nexticon = self.smallsq_icon
                self.curr_iconindex = 3
            elif self.curr_iconindex == 3:
                nexticon = self.icon
                self.curr_iconindex = 0
            GObject.idle_add(
                self.update_activeicon, nexticon,
                priority=GObject.PRIORITY_DEFAULT,
            )
        return self.copying

    def update_activeicon(self, icon):
        self.box.add(icon)
        self.box.show_all()
        self.show_all()

    def getridof_copytrigger(self):
        try:
            os.remove(self.copytrigger)
        except FileNotFoundError:
            pass

    def set_iconactive(self, arg1, arg2, arg3, event):
        copytriggerexists = os.path.exists(self.copytrigger)
        copytriggercreated = event == Gio.FileMonitorEvent.CREATED
        if all([copytriggerexists, copytriggercreated]):
            self.copying = True
            self.set_icon_state()
        elif all([self.copying, not copytriggerexists]):
            self.getridof_copytrigger()
            self.copying = False
            self.set_icon_state()

    def create_windowtrigger(self, *args):
        if not self.check_winexists():
            open(os.path.join(self.tmp_path, ".call_dropby"), "wt").write("")

    def start_dropover(self):
        try:
            pid = subprocess.check_output(
                ["/usr/bin/pgrep", "-f", self.winpath]
            )
        except subprocess.CalledProcessError:
            subprocess.Popen([self.winpath, self.uuid])

    def check_winexists(self):
        wins = self.scr.get_windows()
        for w in wins:
            if w.get_name() == "dropby_popup":
                return True
        return False

    def setup_watching(self):
        # setup watching triggers
        infofile = Gio.File.new_for_path(self.copytrigger)
        try:
            os.remove(self.copytrigger)
        except FileNotFoundError:
            pass
        self.monitor = infofile.monitor(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self.set_iconactive)
        self.watchdrives = Gio.VolumeMonitor.get()
        self.actiontriggers = [
            "volume_added", "volume_removed", "mount_added", "mount_removed",
        ]
        for t in self.actiontriggers:
            self.watchdrives.connect(t, self.refresh_from_idle)

    def do_get_settings_ui(self):
        """Return the applet settings with given uuid"""
        return DropBySettings(self.get_applet_settings(self.uuid))

    def do_supports_settings(self):
        """Return True if support setting through Budgie Setting,
        False otherwise.
        """
        return True

    def refresh_from_idle(self, subject=None, newvol=None):
        GObject.idle_add(
            self.refresh, subject, newvol,
            priority=GObject.PRIORITY_DEFAULT,
        )

    def refresh(self, subject=None, newvol=None):
        allvols = self.watchdrives.get_volumes()
        get_relevant = db.get_volumes(allvols)
        # decide if we should show or not
        for c in self.box.get_children():
            c.destroy()
        if get_relevant:
            self.box.add(self.icon)
        else:
            for img in self.box:
                self.box.remove(img)
        self.box.show_all()
