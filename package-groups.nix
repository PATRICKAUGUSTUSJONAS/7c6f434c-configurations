# I keep everything in configuration.nix for automated
# updates. But the list is rather big, so I split it.
# Division is relatively random.
{myTexLive , myKDE, pkgs, baseKernel, ...}: with pkgs; 
let pp = import ./private-packages.nix {inherit pkgs;}; in
rec {

	private = pp;

  nixosDefault = [
      acl attr bashInteractive bzip2 coreutils cpio curl diffutils eject
      findutils gawk glibc gnugrep gnupatch gnused gnutar gzip xz less libcap
      man nano ncurses netcat openssh pciutils perl procps rsync strace pam
      sysvtools su time usbutils utillinux glibcLocales sudo lvm2 shadow
  ];

	bootstrap = {
		extractors = [p7zip];
		programmingLanguages = [
                        bashInteractive
			zsh bash sbcl ecl clisp gcc

			pythonFull pythonPackages.pip
		];
		buildSupport = [
			libtool automake autoconf gnumake patchelf nixUnstable
		];
		utilsX = [
			xlaunch xterm rxvt_unicode rxvt_unicode.terminfo xmacro
			xsel xclip xorg.xmodmap xorg.xrandr
			dmenu2 xdotool xorg.xkbcomp xorg.setxkbmap
      xorg.xorgserver xkeyboard_config xorg.xprop
		];
		consoleTools = [
			which sqlite bc psmisc file utillinuxCurses slmenu
			rlwrap screen pv manpages kmod module_init_tools
		];
		debugTools = [
			gdb lsof strace
		];
		clientServer = [
			postgresql openssh wget curl
			squids.latest fdm nbd bind
			lftp ntp
		];
		networkTools = [
			mtr dhcp wpa_supplicant iproute iputils
			ncat socat libidn iptables nettools
		];
		textCrunchers = [
			diffutils patch gnused 
		];
		hwControl = [
			fbterm iw hdparm smartmontools kbd
			pmount wavemon eudev xorg.xf86inputsynaptics
		];
		browsers = [
			firefox conkeror
		];
		editors = [
			(import ./custom-vim.nix pkgs)
		];
		versionControl = [
			git mercurial monotone subversion darcs
		];
		filesystems = [
			sshfsFuse fuse
		];
		partitionTools = [
			gptfdisk
		];
		encryption = [
			gnupg openssl
		];
		nonNative = [
			qemu OVMF
		];
	};
	constantly_used = {
		extractors = [
			unzip zip xarchive lrzip mdbtools_git runzip
		];
		programmingLanguages = [
			fpc lazarus
			asymptote myTexLive
			gcc maxima guile /*racket*/
			eprover
			julia openjdk8 apache-jena
			mono octave nim ruby
      haskellPackages.ghc
      glpk

			pythonPackages.ipython
      lispPackages.clwrapper cl-launch
		];
		utilsX = [
			icewm pp.stumpwm trayer 
			keynav x11vnc xorg.xsetroot
			xorg.xdpyinfo xorg.xdriinfo glxinfo
			xscreensaver xvidcap apacheHttpd
			xcalib xorg.xwd xdaliclock xvfb_run
      xorg.xinput xorg.xset xorg.xauth ratpoison
      xorg.xlsclients xorg.xwininfo xorg.xkill
      myKDE.kdelibs xorg.xrdb xprintidle-ng
		];
		consoleTools = [
			remind expect pinentry fdupes mc debootstrap
			texinfoInteractive
		];
		clientServer = [
			dict dbus.tools
			ripmime gtkvnc tigervnc samba
			lighttpd nix-binary-cache
			openvpn (youtubeDL.override {pandoc = null;})
			tftp_hpa netkittftp atftp 
			telnet xinetd nginx vsftpd
			transmission nix-prefetch-scripts
			(dictDBCollector {
			 dictlist = with dictdDBs; map 
			 (x:{
			  name = x.dbName;
			  filename = x.outPath;
			  locale = x.locale;
			  })
			 [ 
			 eng2fra fra2eng eng2nld
			 nld2eng eng2rus
			 mueller_enru_abbr
			 mueller_enru_base
			 mueller_enru_dict
			 mueller_enru_geo
			 mueller_enru_names
			 ];
			 })
		];
		networkTools = [
			wireshark tcpdump
			nmap badvpn tor
		];
		consoleBrowsers = [
			elinks lynx links2
		];
		textCrunchers = [
			xxdiff myKDE.kdiff3
		];
		media = [
			mplayer /*myKDE.kmplayer*/ timidity sox lame vlc ffmpeg espeak 
      lilypond
		];
		hwControl = [
			alsaLib cups alsaUtils
			xsane udisks2 xlaunch
			baseKernel.kernelPackages.kernel
			pp.lcard_ltr_sdk

			androidenv.androidsdk_4_2
		] ++ baseKernel.extraModulePackages;
		graphicEdit = [
			inkscape gimp imagemagick vue dmtx graphviz
			pdftk gnuplot openscad xfig zbar qrencode zxing
      quirc myKDE.kig drgeo potrace slic3r transfig
      povray
		];
		graphicView = [
			xpdf zathura evince djvulibre fbida ghostscript
			geeqie gqview mupdf djview4
		];
		browsers = [
			conkeror firefox chromium 
			pp.slimerjs midori

			nspluginwrapper 
			icedtea7_web
		];
		editors = [
			libreoffice emacs textadept
				emacsPackagesNg.slime
		];
		versionControl = [
			monotoneViz gitFull fossil
		];

		monitoring = [
			htop iftop iotop powertop 
		];

		filesystems = [
      dosfstools e2fsprogs btrfsProgs cifs_utils bedup

			inotifyTools ncdu cdrkit smbnetfs genext2fs

      ntfs3g
		];
		
		toys = [
			fortune sgtpuzzles quantumminigolf liquidwar fsg golly n2048
      xpilot-ng pkgs."2048-in-terminal" xmoto
		];

		im = [
			gajim ii mcabber
		];
		sandboxing = [
			lxc firejail
		];
    emulators = [
      wineUnstable pipelight dosbox
    ];
    nonNative = [
      baseKernel.kernelPackages.virtualbox
    ];
    fonts = (import ./fonts.nix pkgs).fonts;
    icons = [oxygen_gtk myKDE.oxygen_icons];
    libraries = [myKDE.kde_runtime phonon lispPackages.command-line-arguments
      asdf];
	};
}
