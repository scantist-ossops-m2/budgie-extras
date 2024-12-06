using Gtk;
using Cairo;
using Gdk;


/*
Budgie WindowPreviews
Author: Jacob Vlijm
Copyright © 2017 Ubuntu Budgie Developers
Website=https://ubuntubudgie.org
This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or any later version. This
program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU General Public License for more details. You
should have received a copy of the GNU General Public License along with this
program.  If not, see <https://www.gnu.org/licenses/>.
*/

// valac --pkg gtk+-3.0 --pkg gio-2.0 --pkg cairo --pkg gdk-x11-3.0 --pkg libwnck-3.0 -X "-D WNCK_I_KNOW_THIS_IS_UNSTABLE"


namespace NewPreviews {

    int currtilindex;
    bool no_windows;
    int currws;
    int maxcol;
    bool allworkspaces;
    bool showtooltips;
    bool allapps;
    Gtk.Button[] currbuttons;
    File triggerdir;
    File nexttrigger;
    File allappstrigger;
    File allappstriggerhotc;
    File currapptriggerhotc;
    bool allappshotc_trigger;
    bool currapphotc_trigger;
    bool prev_winexists;
    File previoustrigger;
    File triggercurrent;
    bool ignore;
    string filepath;
    Gtk.Window previews_window;
    string[] num_ids_fromdir;
    FileMonitor monitor;
    unowned Wnck.Screen wnck_scr;
    unowned GLib.List<Wnck.Window> z_list;
    Gdk.X11.Window timestamp_window;
    string previewspath;

    private uint get_now() {
        // time stamp needs it
        return Gdk.X11.get_server_time(timestamp_window);
    }

    private int get_stringindex (string[] arr, string lookfor) {
        // get index of string in list
        for (int i=0; i < arr.length; i++) {
            if(lookfor == arr[i]) return i;
        }
        return -1;
    }


    public class PreviewsWindow : Gtk.Window {

        Grid maingrid;
        Grid currlast_startspacer;
        Grid[] subgrids;
        string[] win_workspaces;

        string newpv_css = """
        .windowbutton {
        border-width: 2px;
        border-color: #5A5A5A;
        background-color: transparent;
        padding: 4px;
        border-radius: 1px;
        -gtk-icon-effect: none;
        border-style: solid;
        transition: 0.1s linear;
        }
        .windowbutton:hover {
        border-color: #E6E6E6;
        background-color: transparent;
        border-width: 1px;
        padding: 6px;
        border-radius: 1px;
        border-style: solid;
        }
        .windowbutton:focus {
        border-color: white;
        background-color: transparent;
        border-width: 2px;
        padding: 3px;
        }
        .label {
        color: white;
        padding-bottom: 0px;
        }
        """;

        private string[] get_devices() {
            // get the fixed section of the function
            string output = "";
            try {
                GLib.Process.spawn_command_line_sync(
                    Config.PACKAGE_BINDIR + "/xinput --list", out output
                );
            }
            catch (Error e) {
                //simply pass, nothing bad will happen on a single failure
            }
            string[] keyboard_data = output.split("\n");
            string[] valid = {};
            foreach (string s in keyboard_data) {
                    if (
                        !s.contains("Button") &&
                        !s.contains("Virtual") &&
                        !s.contains("pointer") &&
                        s.contains("id")) {
                            //device ids to check
                            string tocheck = s.split("=")[1].split("\t")[0];
                            valid += tocheck;
                    }
                }
                return valid;
            }

        private Grid create_hspacer(int extend = 0) {
            // last row needs to be positioned, add to all boxes,
            // only set width > 0 on the last
            var spacegrid = new Gtk.Grid();
            spacegrid.attach(new Gtk.Grid(), 0, 0, 1, 1);
            spacegrid.attach(new Gtk.Grid(), 1, 0, 1, 1);
            spacegrid.set_column_spacing(extend);
            return spacegrid;
        }

        private void remove_button (Button button) {
            // remove a button from the array of buttons
            // to prevent browse errors
            Button[] newbuttons = {};
            foreach (Button b in currbuttons) {
                if (b != button) {
                    newbuttons += b;
                }
            }
            currbuttons = newbuttons;
        }

        private void set_closebuttonimg(Button button, string icon_name) {
            // we don't like repeating
            var newimage = new Gtk.Image.from_icon_name(
                "budgie_wpreviews_" + icon_name,
                Gtk.IconSize.BUTTON);
            button.set_image(newimage);
        }

        private Grid makebuttongrid(
            string imgpath, Image appicon, string windowname, string some_xid
            ) {
            var subgrid = new Gtk.Grid();
            subgrid.set_row_spacing(0);
            // window image button
            var button = new Gtk.Button();
            if (showtooltips) {
                button.set_tooltip_text(windowname);
            }
            button.set_size_request(280, 180);
            var image = new Gtk.Image.from_file (imgpath);
            button.set_image(image);
            var st_ct = button.get_style_context();
            st_ct.add_class("windowbutton");
            st_ct.remove_class("image-button");
            button.set_relief(Gtk.ReliefStyle.NONE);
            button.clicked.connect (() => {
                //raise_win(s)
                activate_window(some_xid);
                previews_window.destroy();
            });
            currbuttons += button;
            subgrid.attach(button, 0, 1, 1, 1);
            // box
            Gtk.Box actionbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            subgrid.attach(actionbar, 0, 0, 1, 1);
            // app icon
            actionbar.pack_start(appicon, false, false, 0);
            // window name
            Label wname = new Label(windowname);
            wname.set_ellipsize(Pango.EllipsizeMode.END);
            wname.set_max_width_chars(22);
            var label_ct = wname.get_style_context();
            label_ct.add_class("label");
            actionbar.pack_start(wname, false, false, 10);
            // close X button and its behavior
            var closebutton = new Gtk.Button();
            set_closebuttonimg(closebutton, "grey_x");
            closebutton.set_relief(Gtk.ReliefStyle.NONE);
            closebutton.set_can_focus(false);
            closebutton.enter_notify_event.connect (() => {
                set_closebuttonimg(closebutton,
                    "white2_x"
                );
                return false;
            });
            closebutton.leave_notify_event.connect (() => {
                set_closebuttonimg(closebutton,
                    "grey_x"
                );
                return false;
            });
            button.enter_notify_event.connect (() => {
                set_closebuttonimg(closebutton,
                    "white_x"
                );
                return false;
            });
            button.leave_notify_event.connect (() => {
                set_closebuttonimg(closebutton,
                    "grey_x"
                );
                return false;
            });

            actionbar.pack_end(closebutton, false, false, 0);
            closebutton.clicked.connect (() => {
                if (currbuttons.length == 1) {
                    this.destroy();
                }
                else {
                    remove_button(button);
                    subgrid.set_sensitive(false);
                    currtilindex = 0;
                    this.resize(100, 100);
                }

                close_window(some_xid);
            });
            return subgrid;
        }

        // new functions, looking up window from most recent Wnck stack
        private Wnck.Window? get_wnckwindow_fromxid (string xid_str) {
            z_list = wnck_scr.get_windows_stacked();
            foreach (Wnck.Window w in z_list) {
                string compare = w.get_xid().to_string();
                if (compare == xid_str) {
                    return w;
                }
            }
            return null;
        }

        private void close_window (string xid_str) {
            Wnck.Window found_match = get_wnckwindow_fromxid (xid_str);
            if (found_match != null) {
                uint now = get_now();
                found_match.close(now);
            }
        }

        private void activate_window (string xid_str) {
            Wnck.Window found_match = get_wnckwindow_fromxid (xid_str);
            if (found_match != null) {
                uint now = get_now();
                found_match.activate(now);
            }
        }

        private bool filter_wmclass (
            Wnck.Window w, string? wm_class
        ) {
            // if set, only allow current wm_class
            if (allapps || wm_class == null) {
                return true;
            }
            else {
                string group = w.get_class_group_name();
                if (group == wm_class) {
                    return true;
                }
                return false;
            }
        }

        private bool filter_workspace (int windowspace, int currspace) {
            // check windows on workspace if set in gsettings
            if (allworkspaces) {
                return true;
            }
            else {
                if (windowspace == currspace) {
                    return true;
                }
                return false;
            }
        }

        public void actonbrowsetrigger () {
            // browse through tiles -only works if prv window exists-
            if (nexttrigger.query_exists()) {
                currtilindex += 1;
                if (currtilindex == currbuttons.length) {
                    currtilindex = 0;
                }
                delete_file(nexttrigger);
                if (currtilindex <= currbuttons.length &&
                    currtilindex >= 0) {
                        currbuttons[currtilindex].grab_focus();
                }

            }
            else if (previoustrigger.query_exists()) {
                currtilindex -= 1;
                if (currtilindex < 0) {
                    currtilindex =  currbuttons.length - 1;
                }
                delete_file(previoustrigger);
                if (currtilindex <= currbuttons.length &&
                    currtilindex >= 0) {
                        currbuttons[currtilindex].grab_focus();
                }
            }
        }

        public PreviewsWindow () {
            /*
            safety" procedure to make sure the window doesn't stick on
            reversed release Alt-Tab
            */
            wnck_scr.active_window_changed.connect(check_ifactive);
            if (!allappshotc_trigger && !currapphotc_trigger) {
                string[] devices = get_devices();
                GLib.Timeout.add (100, () => {
                    bool pressed = false;
                    foreach (string s in devices) {
                        string output = "";
                        try {
                            GLib.Process.spawn_command_line_sync(
                                Config.PACKAGE_BINDIR + "/xinput --query-state " + s, out output
                            );
                        }
                        catch (Error e) {
                            // just pass
                        }
                        pressed = output.contains("down");
                        if (pressed) {
                            break;
                        }
                    }
                    if (!pressed) {
                        if (currbuttons.length != 0) {
                            currbuttons[currtilindex].clicked();
                        }
                        return false;
                    }
                    return true;
                });
            }

            // if nothing to show
            no_windows = true;
            this.set_default_size(200, 150);
            this.set_decorated(false);
            this.set_keep_above(true);
            this.set_skip_taskbar_hint(true);
            monitor.changed.connect(actonbrowsetrigger);
            currbuttons = {};
            currtilindex = 0;
            // set initial numbers cols/rows etc.
            int row = 1;
            int col = 0;
            // whole bunch of styling
            var screen = this.get_screen();
            this.set_app_paintable(true);
            var visual = screen.get_rgba_visual();
            this.set_visual(visual);
            this.draw.connect(on_draw);
            Gtk.CssProvider css_provider = new Gtk.CssProvider();
            try {
                css_provider.load_from_data(newpv_css);
                Gtk.StyleContext.add_provider_for_screen(
                    screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            }
            catch (Error e) {
            }
            // create maingrid
            maingrid = new Gtk.Grid();
            maingrid.attach(new Label(""), 0, 0, 1, 1);
            maingrid.attach(new Label("\n"), 100, 100, 1, 1);
            maingrid.set_column_spacing(20);
            maingrid.set_row_spacing(20);
            // create arrays from dirlist ->
            // window_id arr, path arr (which is dirlist), workspace arr
            string[] currpreviews = previews(previewspath);
            num_ids_fromdir = {};
            foreach (string s in currpreviews) {
                string[] fname = s.split("/");
                string[] last_section = fname[fname.length - 1].split(".");
                string win_workspace = last_section[1];
                win_workspaces += win_workspace;
                string found_xid = last_section[0];
                num_ids_fromdir += found_xid;
            }
            z_list = wnck_scr.get_windows_stacked();
            // watch out! window can be null -> wm_class can be null
            string? wm_class = null;
            Wnck.Window? curr_active = wnck_scr.get_active_window();
            if (curr_active != null) {
                wm_class = curr_active.get_class_group_name();
            }

            foreach (Wnck.Window w in z_list) {
                string z_intid = w.get_xid().to_string();  // store in array
                int dirlistindex = get_stringindex(num_ids_fromdir, z_intid);
                if (
                    w.get_window_type() == Wnck.WindowType.NORMAL &&
                    dirlistindex != -1
                    ) {
                    int window_on_workspace = int.parse(
                        win_workspaces[dirlistindex]
                    );
                    if (
                        filter_workspace(window_on_workspace, currws) &&
                        filter_wmclass(w, wm_class)
                    ) {
                        no_windows = false;
                        string img_path = currpreviews[dirlistindex];
                        Pixbuf icon = w.get_mini_icon();
                        Image img = new Gtk.Image.from_pixbuf(icon);
                        string wname = w.get_name();
                        string some_xid = w.get_xid().to_string();
                        Grid newtile = makebuttongrid(img_path, img, wname, some_xid);
                        subgrids += newtile;
                    }
                }
            }

            // reverse buttons
            Button[] reversed_buttons = {};
            int n_buttons = currbuttons.length;
            while (n_buttons > 0) {
                reversed_buttons += currbuttons[n_buttons - 1];
                n_buttons -= 1;
            }
            currbuttons = reversed_buttons;
            // reverse order of tiles
            Grid[] reversed_tiles = {};
            int n_tiles = subgrids.length;
            while (n_tiles > 0) {
                reversed_tiles += subgrids[n_tiles-1];
                n_tiles -= 1;
            }
            // firstbox / row
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 20);
            // start spacer
            box.pack_start(create_hspacer(), false, false, 0);
            currlast_startspacer = create_hspacer();
            foreach (Grid g in reversed_tiles) {
                box.pack_start(g, false, false, 0);
                col += 1;
                if (col == maxcol) {
                    // end spacer previous one
                    box.pack_start(create_hspacer(), false, false, 0);
                    maingrid.attach(box, 1, row, 1);
                    box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 20);
                    currlast_startspacer = create_hspacer();
                    // start spacer new one
                    box.pack_start(currlast_startspacer, false, false, 0);
                    row += 1;
                    col = 0;
                }
            }
            // add last box, align (tile width = 300px)
            box.pack_start(create_hspacer(), false, false, 0);
            maingrid.attach(box, 1, row, 1);
            if (col != 0) {
                int tofix = maxcol - col;
                int add = tofix * 300 / 2;
                currlast_startspacer.set_column_spacing (add);
            }
            if (reversed_buttons.length > 1) {
                currtilindex = 1;
                reversed_buttons[1].grab_focus();
            }
            this.title = "PreviewsWindow";
            prev_winexists = true;
            this.add(maingrid);
            // lazy patch, but for a rare situation, should do
            if (reversed_buttons.length == 0) {
                this.destroy();
                cleanup();
            }
        }

        private void check_ifactive () {
            Wnck.Window curr = wnck_scr.get_active_window();
            if (curr.get_name() != "PreviewsWindow") {
                this.destroy();
            }

        }

        private bool on_draw (Widget da, Context ctx) {
            // needs to be connected to transparency settings change
            ctx.set_source_rgba(0.15, 0.15, 0.15, 0.85);
            ctx.set_operator(Cairo.Operator.SOURCE);
            ctx.paint();
            ctx.set_operator(Cairo.Operator.OVER);
            return false;
        }

        private string[] previews (string directory) {
            // list the created preview images
            string[] somestrings = {};
            try {
                var dr = Dir.open(directory);
                string ? filename = null;
                while ((filename = dr.read_name()) != null) {
                    string addpic = GLib.Path.build_filename(
                        directory, filename
                    );
                    somestrings += addpic;
                }
            }
            catch (FileError err) {
                    stderr.printf(err.message);
            }
            return somestrings;
        }
    }

    private void delete_file (File file) {
        try {
            file.delete();
        }
        catch (Error e) {
        }
    }

    private void cleanup () {
        // remove trigger files
        delete_file(allappstrigger);
        delete_file(allappstriggerhotc);
        delete_file(triggercurrent);
        delete_file(currapptriggerhotc);
        ignore = false;
        prev_winexists = false;
    }

    private bool close_onrelease(Gdk.EventKey k) {
        // on releasing Alt_L, destroy previews, virtually click current
        // button (connect is gone with destroying previews window)
        string key = Gdk.keyval_name(k.keyval);
        if (key == "Escape") {
            previews_window.destroy();
        }
        if (key == "Alt_L" || key == "Meta_L") {
            if (!no_windows) {
                currbuttons[currtilindex].clicked();
            }
            else {
                previews_window.destroy();
            }
        }
        return true;
    }

    private void raise_previewswin(Wnck.Window newwin) {
        // make sure new previews window is activated on creation
        if (newwin.get_name() == "PreviewsWindow") {
            uint timestamp = get_now();
            newwin.activate(timestamp);
        }
    }

    private void get_n_cols () {
        // set number of columns, depending on screen width
        Gdk.Monitor prim = Gdk.Display.get_default().get_primary_monitor();
        var geo = prim.get_geometry();
        int width = geo.width;
        maxcol = width / 360;
    }

    private void update_currws () {
        // keep track of current workspace
        wnck_scr.force_update();
        var currspace = wnck_scr.get_active_workspace();
        unowned GLib.List<Wnck.Workspace> currspaces = wnck_scr.get_workspaces();
        int n = 0;
        foreach (Wnck.Workspace ws in currspaces) {
            if (ws == currspace) {
                currws = n;
                break;
            }
            n += 1;
        }
    }

    private void actonfile(File file, File? otherfile, FileMonitorEvent event) {
        if (event == FileMonitorEvent.CREATED) {
            bool allapps_trigger = allappstrigger.query_exists();
            bool onlycurrent_trigger = triggercurrent.query_exists();
            allappshotc_trigger = allappstriggerhotc.query_exists();
            currapphotc_trigger = currapptriggerhotc.query_exists();
            bool fromhotcorner = allappshotc_trigger || currapphotc_trigger;
            if (fromhotcorner && prev_winexists) {
                previews_window.destroy();
                cleanup();
            }
            else if (
                allapps_trigger || onlycurrent_trigger || allappshotc_trigger || currapphotc_trigger
            ) {

                if (allappshotc_trigger || currapphotc_trigger) {
                    cleanup();
                }
                if (!ignore) {
                    if (allapps_trigger || allappshotc_trigger)  {
                        allapps = true;
                    }
                    else {
                        allapps = false;
                    }
                    previews_window = new PreviewsWindow();
                    previews_window.destroy.connect(cleanup);
                    previews_window.key_release_event.connect(close_onrelease);
                    previews_window.set_position(Gtk.WindowPosition.CENTER_ALWAYS);
                    previews_window.show_all();
                }
                ignore = true;
            }
            else {
                previews_window.destroy();
                ignore = false;
            }
        }
    }

    private string get_filepath (string arg) {
        // get path of current (executable) file
        string[] steps = arg.split("/");
        string[] trim_filename = steps[0:steps.length-1];
        return string.joinv("/", trim_filename);
    }

    private void windowdaemon(string[] args) {
        filepath = get_filepath (args[0]);
        GLib.Settings previews_settings = new GLib.Settings(
            "org.ubuntubudgie.budgie-wpreviews"
        );
        allworkspaces = previews_settings.get_boolean("allworkspaces");
        showtooltips = previews_settings.get_boolean("showtooltips");
        previews_settings.changed.connect (() => {
            allworkspaces = previews_settings.get_boolean("allworkspaces");
            showtooltips = previews_settings.get_boolean("showtooltips");
        });
        string tmp = Environment.get_variable("XDG_RUNTIME_DIR") ?? Environment.get_variable("HOME");
        triggerdir = File.new_for_path(tmp);
        allappstrigger = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".prvtrigger_all")
        );
        allappstriggerhotc = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".prvtrigger_all_hotcorner")
        );
        currapptriggerhotc = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".prvtrigger_curr_hotcorner")
        );
        nexttrigger = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".nexttrigger")
        );
        previoustrigger = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".previoustrigger")
        );
        triggercurrent = File.new_for_path(
            GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".prvtrigger_current")
        );
        // start with a clean plate please
        cleanup();
        // start the loop
        // X11 stuff, non-dynamic part
        unowned X.Window xwindow = Gdk.X11.get_default_root_xwindow();
        unowned X.Display xdisplay = Gdk.X11.get_default_xdisplay();
        Gdk.X11.Display display = Gdk.X11.Display.lookup_for_xdisplay(xdisplay);
        timestamp_window = new Gdk.X11.Window.foreign_for_display(display, xwindow);
        // monitoring files / dirs
        try {
            monitor = triggerdir.monitor(FileMonitorFlags.NONE, null);
            monitor.changed.connect(actonfile);
        }
        catch (Error e) {
        }
        // monitoring wnck_screen & Display for n_columns
        var gdk_screen = Gdk.Screen.get_default();
        gdk_screen.monitors_changed.connect(get_n_cols);
        get_n_cols();
        // miscellaneous
        wnck_scr = Wnck.Screen.get_default();
        wnck_scr.active_workspace_changed.connect(update_currws);
        update_currws();
        wnck_scr.window_opened.connect(raise_previewswin);
        // prevent cold start (not sure why, but it works)
        previews_window = new PreviewsWindow();
        previews_window.destroy();
    }

    public static void main (string[] args) {
        string tmp = Environment.get_variable("XDG_RUNTIME_DIR") ?? Environment.get_variable("HOME");
        previewspath = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, tmp, ".windows-previews");
        try {
            File file = File.new_for_commandline_arg (previewspath);
            file.make_directory ();
        } catch (Error e) {
            // directory exists, nothing to do
        }
        Gtk.init(ref args);
        NewPreviews.windowdaemon(args);
        Gtk.main();
    }
}