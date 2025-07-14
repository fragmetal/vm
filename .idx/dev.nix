{ pkgs, ... }: {
  channel = "stable-25.05";
  
  packages = [
    pkgs.nodePackages.pnpm
    pkgs.ngrok
    pkgs.neofetch
    pkgs.cloudflared
    pkgs.tigervnc
    pkgs.icewm
    pkgs.novnc
    pkgs.python3Packages.websockify
    pkgs.xterm
    pkgs.xorg.xset
    pkgs.xorg.xrandr
    pkgs.busybox
    pkgs.coreutils
    pkgs.firefox
    pkgs.feh
    pkgs.xorg.xsetroot
    pkgs.xdotool
    pkgs.libGLU
    pkgs.mesa
    
    # Add font packages
    pkgs.dejavu_fonts
    pkgs.liberation_ttf
    pkgs.ubuntu_font_family
    pkgs.fontconfig
  ];

  env = {
    DISPLAY = ":1";
    XLOCALEDIR = "${pkgs.glibcLocales}/share/X11/locale";
    NO_AT_BRIDGE = "1";
    MOZ_DISABLE_RDD_SANDBOX = "1";
    MOZ_ENABLE_WAYLAND = "0";
    DBUS_FATAL_WARNINGS = "0";
    NGROK_AUTHTOKEN = "your_ngrok_token_here";
    
    # Configure font paths
    FONTCONFIG_PATH = "${pkgs.fontconfig.out}/etc/fonts";
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
  };
  
  idx = {
    extensions = [];
    previews.enable = false;

    workspace = {
      onCreate = {};
      onStart = {
        start-all = ''
          # Create writable location for machine-id
          export MACHINE_ID=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
          mkdir -p ~/.dbus
          echo "$MACHINE_ID" > ~/.dbus/machine-id
          export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$HOME/.dbus/system_bus_socket"

          VNC_PID_FILE="/tmp/vnc.pid"
          if [ -f "$VNC_PID_FILE" ] && kill -0 $(cat "$VNC_PID_FILE") 2>/dev/null; then
            echo "VNC is already running. Skipping startup."
            exit 0
          fi

          cleanup() {
            kill $(jobs -p) 2>/dev/null
            rm -f "$VNC_PID_FILE" /tmp/.X1-lock
          }
          trap cleanup EXIT

          rm -f /tmp/.X1-lock

          # Start optimized VNC server
          ${pkgs.tigervnc}/bin/Xvnc :1 \
            -geometry 1920x1080 \
            -depth 24 \
            -SecurityTypes None \
            -AlwaysShared \
            -ac \
            -pn \
            -rfbport 5900 \
            -FrameRate 60 \
            -CompareFB 1 \
            +extension GLX +extension RANDR +extension RENDER +extension XFIXES &

          VNC_PID=$!
          echo "$VNC_PID" > "$VNC_PID_FILE"

          echo "Waiting for X server..."
          while ! ${pkgs.xorg.xset}/bin/xset -display :1 -q >/dev/null 2>&1; do 
            sleep 0.5
          done
          echo "X server ready"

          # Configure font paths
          echo "Setting up font paths..."
          DISPLAY=:1 ${pkgs.xorg.xset}/bin/xset +fp ${pkgs.dejavu_fonts}/share/fonts/truetype
          DISPLAY=:1 ${pkgs.xorg.xset}/bin/xset +fp ${pkgs.liberation_ttf}/share/fonts/truetype
          DISPLAY=:1 ${pkgs.xorg.xset}/bin/xset +fp ${pkgs.ubuntu_font_family}/share/fonts/truetype
          DISPLAY=:1 ${pkgs.xorg.xset}/bin/xset fp rehash
          ${pkgs.fontconfig}/bin/fc-cache -f

          # Set background color
          DISPLAY=:1 ${pkgs.xorg.xsetroot}/bin/xsetroot -solid grey

          # Start window manager with fixed font configuration
          DISPLAY=:1 ${pkgs.icewm}/bin/icewm -c ${pkgs.writeText "icewm.cfg" ''
            # Fixed font configuration
            MenuFontName = "DejaVu Sans-12:monospace"
            ToolButtonFontName = "DejaVu Sans-12:monospace"
            StatusFontName = "DejaVu Sans-12:monospace"
            QuickSwitchFontName = "DejaVu Sans-12:monospace"
            NormalButtonFontName = "DejaVu Sans Bold-12:monospace"
            ActiveButtonFontName = "DejaVu Sans Bold-12:monospace"
            MinimizedWindowFontName = "DejaVu Sans Italic-12:monospace"
            ListBoxFontName = "DejaVu Sans-12:monospace"
            TaskBarFontName = "DejaVu Sans-12:monospace"
            ClockFontName = "DejaVu Sans-12:monospace"
            AOSLabelFontName = "DejaVu Sans-12:monospace"
            AOSTitleFontName = "DejaVu Sans Bold-12:monospace"
            
            # Other IceWM settings
            TaskBarShowTaskBar=1
            TaskBarShowStartButton=1
            TaskBarShowClock=1
            TaskBarShowWindowList=1
            ShowProgramsMenu=1
            TaskBarDelay=0
            UseDma=1
          ''} &

          # Start Firefox
          DISPLAY=:1 ${pkgs.firefox}/bin/firefox "https://idx.google.com/relay-81899614" &

          # Start noVNC
          NOVNC_DIR="${pkgs.novnc}/share/webapps/novnc"
          ${pkgs.python3Packages.websockify}/bin/websockify --web "$NOVNC_DIR" 8080 localhost:5900 &

          # Keep-alive function
          keep_alive() {
            local SERVICE_NAME="$1"
            shift
            while true; do
              echo "Starting $SERVICE_NAME..."
              if "$@"; then
                echo "$SERVICE_NAME exited cleanly. Restarting in 3 seconds..."
              else
                echo "$SERVICE_NAME crashed! Restarting in 3 seconds..."
              fi
              sleep 3
            done
          }

          # Keep session alive
          wait $VNC_PID
        '';
      };
    };
  };
}