{
  pkgs ? import <nixpkgs> {}
  , nixos ? import <nixpkgs/nixos>
  , overrides ? (x: {})
}:
let
  lib = pkgs.lib;
  callPackageWith = lib.callPackageWith;
  tools = import ./tools.nix {inherit pkgs  nixos;};
  composeFun = self: overrides: let
    call = callPackageWith self;
  in ({
    inherit self tools lib pkgs nixos initial call;

    linux = pkgs.linux_latest;
    linuxPackages = pkgs.linuxPackagesFor self.linux;
    initrd = pkgs.makeOverridable tools.makeUdevInitrd {
      modulesTree = [self.linux] ++ self.initrdModulesTree;
      initScript = self.bootInitScript;
      modules = self.initrdModules;
      modulesAvailable = self.initrdModulesAvailables;
      extraToolset = self.initrdExtraToolset;
    };
    initrdExtraToolset = [];
    initrdModules = [
      "vfat" "ext4" "nls-iso8859-1" "unix" "configs" "loop" "sd-mod"
    ];
    initrdModulesAvailables = [];
    initrdModulesTree = [];
    qemuScript = tools.qemuLauncherFun { inherit (self) initrd; };
    nixosDefaultPackages = with pkgs; [
      acl attr bashInteractive bzip2 coreutils cpio curl diffutils eject
      findutils gawk glibc gnugrep gnupatch gnused gnutar gzip xz less libcap
      man nano ncurses netcat openssh pciutils perl procps rsync strace pam
      sysvtools su time usbutils utillinux glibcLocales sudo lvm2 shadow
    ] ++ [self.nix];
    nix = self.pkgs.nix;
    everescueNeededPackages = with pkgs; [
      which file iproute grub2_efi
    ];
    systemPackages = self.nixosDefaultPackages ++ self.everescueNeededPackages;
    systemSoftware = pkgs.buildEnv {
      name = "system-software-set";
      ignoreCollisions = true;
      paths = self.systemPackages;
      inherit (self) extraOutputsToInstall pathsToLink;
    };
    extraOutputsToInstall = [];
    allOutputNames = builtins.attrNames 
      (lib.fold 
        (a: b: b // 
          (builtins.listToAttrs (map (x: {name = x; value = x;}) a.outputs or ["out"])))
        {} self.systemPackages);
    pathsToLink = ["/"];
    setuidProgramList = [
      "su" "sudo" "passwd" "mount" "umount" "fusermount"
      {src="unix_chkpwd.orig";dst="unix_chkpwd";}
    ];
    setuidPrograms = pkgs.runCommand "setuid-programs" {
       preferLocalBuild = true;
    } ''
      mkdir -p "$out"
      ${pkgs.gcc}/bin/gcc -Wall -O2 -DWRAPPER_DIR="\"/var/setuid-wrapper-storage/$(basename "$out")\"" ${tools.setuidWrapperSource} -o "$out/canonical-wrapper" -L${pkgs.libcap.lib}/lib -I${pkgs.libcap.dev}/include -L${pkgs.libcap_ng}/lib -I${pkgs.libcap_ng}/include -lcap -lcap-ng
      ${lib.concatMapStrings (x:
      let
        src = if builtins.isAttrs x then x.src else x;
        dst = if builtins.isAttrs x then x.dst else x;
      in
      ''
        cp "$out/canonical-wrapper" "$out/${dst}"
        (
          fullSrc="${self.systemSoftware}/bin/${src}" 
          test -e "$fullSrc" && echo -n "$fullSrc" > "$out/${dst}.real"
        ) ||
        (
          fullSrc="${self.systemSoftware}/sbin/${src}" 
          test -e "$fullSrc" && echo -n "$fullSrc" > "$out/${dst}.real"
        ) ||
        true
      '') self.setuidProgramList}
    '';
    etc = pkgs.runCommand "system-etc" {} self.etcBuildCommands;
    etcBuildCommands = ''
      mkdir -p "$out"
      ln -s /var/etc/passwd "$out"
      ln -s /var/etc/passwd- "$out"
      ln -s /var/etc/shadow "$out"
      ln -s /var/etc/shadow- "$out"
      ln -s /var/etc/group "$out"
      ln -s /var/etc/group- "$out"
      ln -s /var/etc/resolv.conf "$out"
      ln -s "${self.etcNix}" "$out/nix"
      ln -s "${self.pamD}" "$out/pam.d"

      ln -s "${pkgs.tzdata}/share/zoneinfo" "$out"
      ln -s "${pkgs.tzdata}/share/zoneinfo/UTC" "$out"/localtime
      ln -s "${pkgs.iana_etc}/etc/protocols" "$out"
      ln -s "${pkgs.iana_etc}/etc/services" "$out"

      mkdir -p "$out/ssl/certs"
      ln -s "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" "$out/ssl/certs/ca-bundle.crt"
      ln -s "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" "$out/ssl/certs/ca-certificates.crt"

      ln -s "${self.profile}" "$out/profile"
      ln -s "${self.loginDefs}" "$out/login.defs"

      echo "${self.hostName}" > "$out"/hostname
      ln -s "${self.hostsFile}" "$out/hosts"
      ln -s "${self.nsswitchConf}" "$out"/nsswitch.conf

      mkdir -p "$out/udev"
      ln -s "${self.udevRulesD}" "$out"/udev/rules.d

      ln -s "${self.dbusConfig}" "$out/dbus-1"

      ln -s /proc/mounts "$out"/mtab

      ${self.etcFontsCommands}

      ${self.extraEtcBuildCommands}
    '';
    etcFontsCommands = if self.etcFonts == null then
      if self.fontPackages == null then "" else
        ''
          mkdir -p "$out/fonts"
          ln -s "${self.fontsConf}" "$out/fonts/fonts.conf"
        ''
    else
    ''
      ln -s ${self.etcFonts} "$out/fonts"
    '';
    nixosEtcFonts = cfg: let nixosWithFonts = nixos {
        configuration = {
          fonts.fontconfig = {
            enable = true;
          } // cfg;
          fonts.fonts = self.fontPackages;
        };
      }; 
      in nixosWithFonts.config.environment.etc.fonts.source;
    hostList = [
      "127.0.0.1\t${self.hostName} localhost"
    ];
    hostsFile = pkgs.writeText "hosts" self.hostList;
    extraEtcBuildCommands = "";
    initrdVirtualMountCommands = ''
      mount sysfs -t sysfs /new-root/sys
      mount debugfs -t debugfs /new-root/sys/kernel/debug
      mount procfs -t proc /new-root/proc
      umount /dev/pts
      umount /dev/shm
      mount --move /dev /new-root/dev
      mount devpts -t devpts /new-root/dev/pts
      mount runtmpfs -t tmpfs /new-root/run -o size=16M
      mkdir /new-root/dev/shm
      mount devshm -t tmpfs /new-root/dev/shm -o size=1G
      chmod a+rwxt /new-root/dev/shm
    '';
    initrdMountCommands = self.initrdVirtualMountCommands;
    systemActivationExtraCommands = "";
    systemActivationBusCommands = ''
      mkdir -p /var/log/services
      mkdir -p /run/nix
      mkdir -p /run/lock
      ln -sfT /run/lock /var/lock
      ( cd /run ; pgrep nix-daemon >/dev/null || LANG=C LC_ALL=C nix-daemon & )
      ip link set lo up
      hostname "${self.hostName}"
    '';
    systemActivationSetuidCommands = ''
      targetSetuidWrappers="/var/setuid-wrapper-storage/$(basename "$(readlink -m "$targetSystem/setuid/wrappers")")"
      mkdir -p "$targetSetuidWrappers"
      cp -a "$targetSystem/setuid/programs"/* "$targetSetuidWrappers"
      for i in "$targetSystem"/setuid/programs/*; do
        ib="$(basename "$i")"
        chown 0:0 "$targetSetuidWrappers/$ib"
        chmod u+s,a+x "$targetSetuidWrappers/$ib"
      done
    '';
    setupEtcCommands = ''
      ln -sf /proc/mounts "$targetSystem"/global/etc/mtab
    '';
    systemActivationSymlinkCommands = ''
      mkdir -p "$(readlink -f "$targetSystem/global/etc/")"
      mountpoint "$targetSystem/global/etc" ||
      {
        etcWorkDir="/var/etc-workdir/$(basename "$targetSystem")"
        mkdir -p "$etcWorkDir"
        find /var/etc -type c | xargs rm
        mount -t overlay etc-overlayfs "$targetSystem/global/etc" -o \
          "lowerdir=$targetSystem/global/etc-static,upperdir=/var/etc,workdir=$etcWorkDir"
        ${self.setupEtcCommands}
      }

      for i in bin usr etc; do
        if test -e /$i && ! test -L /$i; then umount /$i/; mv /$i /$i.old; fi
        ln -sfT /var/current-system/global/$i /$i
      done

      ln -sfT /var/current-system/setuid/wrappers /var/setuid-wrappers

      mkdir /run/wrappers
      ln -sfT /var/current-system/setuid/wrappers /run/wrappers/bin

      ln -sf /var/current-system /nix/var/nix/gcroots/
      ln -sf /var/latest-booted-system /nix/var/nix/gcroots/
    '';
    linuxLateModules = ["overlay"];
    systemActivationModprobeCommands = ''
        echo -n "$( readlink -f "$targetSystem"/bin/modprobe )" > /proc/sys/kernel/modprobe
        echo -n "$( readlink -f "$targetSystem"/boot/firmware )" > /sys/module/firmware_class/parameters/path
      '' + (lib.concatMapStrings 
      (x: ''"$targetSystem"/bin/modprobe ${x}; '')
      self.linuxLateModules);
    systemActivationCommands = ''
      targetSystemRaw="''${0%/bin/activate}"
      export PATH="$targetSystemRaw/sw/bin:$targetSystemRaw/sw/sbin"
      targetSystem="$(readlink -f "''${0%/bin/activate}")"
      bootedSystem="$(cat /proc/cmdline | tr ' ' '\n' | grep targetSystem= | tr '=' '\n' | tail -n 1)"

      ln -sfT "/var/latest-booted-system" /run/booted-system
      ln -sfT "$bootedSystem" /var/latest-booted-system

      ${self.systemActivationModprobeCommands}

      ${self.systemActivationSetuidCommands}
      ${self.systemActivationSymlinkCommands}
      ${self.systemActivationBusCommands}

      ${self.systemActivationExtraCommands}

      ln -sfT "/var/current-system" /run/current-system
      ln -sfT "$targetSystem" /var/current-system
      ln -sfT "$targetSystem" /var/current-everescue-nix
    '';
    systemActivationScript = pkgs.writeScript "activate" self.systemActivationCommands;
    bootInitScript = ''
      touch /var/log/medium-boot-stdout.log
      touch /var/log/medium-boot-stderr.log
      tail -f /var/log/medium-boot-stdout.log &
      tail -f /var/log/medium-boot-stderr.log &
      {
      ${self.initrdMountCommands}
      } > /var/log/medium-boot-stdout.log 2> /var/log/medium-boot-stderr.log 
      ${self.bootChrootCommands}
    '';
    initrdPrePivotRootCommands = ''
      grep "boot.pre_pivot_root_shell" /proc/cmdline && /init-tools/busybox ash -i
    '';
    bootChrootCommands = ''
      timestamp=$(date +%Y%m%d-%H%M%S)
      mkdir -p "/new-root/var/log/boot"/late
      touch   /new-root/var/log/boot/late/$timestamp-stdout.log
      touch   /new-root/var/log/boot/late/$timestamp-stderr.log
      tail -f /new-root/var/log/boot/late/$timestamp-stdout.log &
      tail -f /new-root/var/log/boot/late/$timestamp-stderr.log &
      {
      bootedSystem="$(cat /proc/cmdline | tr ' ' '\n' | grep targetSystem= | tr '=' '\n' | tail -n 1)"
      cd /new-root
      mkdir -p ./initrd
      mkdir -p "/new-root/var/log/boot"/early
      mkdir -p "/new-root/var/log/boot"/medium
      mkdir -p "/new-root/var/log/boot"/late
      mkdir -p "/new-root/var/log/boot"/after
      cp /var/log/early-boot-stderr.log   /new-root/var/log/boot/early/$timestamp-stderr.log
      cp /var/log/early-boot-stdout.log   /new-root/var/log/boot/early/$timestamp-stdout.log
      cp /var/log/medium-boot-stderr.log /new-root/var/log/boot/medium/$timestamp-stderr.log
      cp /var/log/medium-boot-stdout.log /new-root/var/log/boot/medium/$timestamp-stdout.log
      ${self.initrdPrePivotRootCommands}
      } 1> /new-root/var/log/boot/late/$timestamp-stdout.log \
        2> /new-root/var/log/boot/late/$timestamp-stderr.log
      pkill tail
      killall5
      fuser -m -k /
      sleep 0.5
      fuser -m -k -9 /
      killall5 -9
      ps > ./tmp/boot.ps
      cat /proc/mounts | cut -d ' ' -f 2 | grep -v /new-root | grep -v /proc | tac |  xargs umount
      cat /proc/mounts | cut -d ' ' -f 2 | grep -v /new-root | grep -v /proc | tac |  xargs fuser -m -k
      cat /proc/mounts | cut -d ' ' -f 2 | grep -v /new-root | grep -v /proc | tac |  xargs umount
      bootedSystem="$(cat /proc/cmdline | tr ' ' '\n' | grep targetSystem= | tr '=' '\n' | tail -n 1)"
      umount /proc/
      export PATH="$bootedSystem/sw/bin:$PATH"
      if busybox pivot_root . ./initrd; then
        exec chroot . "$bootedSystem"/bin/init
      else
        exec busybox switch_root -c /dev/console /new-root "$bootedSystem"/bin/init
        exec chroot . "$bootedSystem"/bin/init
      fi
    '';
    stage2InitCommands = "#! ${pkgs.stdenv.shell}\n" + ''
      timestamp=$(date +%Y%m%d-%H%M%S)
      {
      "''${0%/init}/activate"
      source /etc/profile
      ${self.stage2InitUdevCommands}
      ${self.stage2InitShellCommands}
      }   1> /var/log/boot/after/$timestamp-stdout.log \
          2> /var/log/boot/after/$timestamp-stderr.log 
      ${self.stage2InitBackToInitrdCommands}
    '';
    dbusConfigCommands = ''
      mkdir "$out"
    '';
    dbusConfig = pkgs.runCommand "dbus-config" {} self.dbusConfigCommands;
    stage2InitUdevCommands = ''
      for gr in tty dialout kmem input video disk cdrom tape messagebus; do
        grep "^$gr:" /etc/group || "${self.pkgs.shadow}"/bin/groupadd -r "$gr"
      done
    '';
    udevRules = tools.storageUdevRules ++ self.fuseUdevRules ++ self.extraUdevRules;
    fuseUdevRules = ["${pkgs.fuse}/etc/udev/rules.d/*.rules"];
    udevRulesD = pkgs.runCommand "udev-rules.d" {} ''
      mkdir -p "$out"
      for i in ${toString self.udevRules}; do
        ln -sfT "$i" "$out/$(basename "''${i#/nix/store/*-}")"
      done
    '';
    autoServices = [];
    autoServiceCommands = (lib.concatMapStrings (x:
      "run-service ${x}; "
    ) self.autoServices);
    stage2DebugShellCommands = ''
      grep "boot.pre_getty_shell" /proc/cmdline && /bin/sh -i
    '';
    stage2InitShellCommands = ''
      ${self.stage2DebugShellCommands}
      ${self.gettyCommands}
      ${self.autoServiceCommands}
    '';
    stage2InitBackToInitrdCommands = ''
      grep '^nobody:' /etc/passwd || useradd -u 65534 nobody
      { while ! test -f /run/shutdown; do sleep 1; done; ps -ef | grep '/var/current-system/setuid/wrappers/su -c true' | awk '{print $2}' | xargs kill ; } & 
      while ! test -f /run/shutdown && ! su nobody -s /bin/sh -c "/var/current-system/setuid/wrappers/su -c true"; do echo Please enter root password to continue; sleep 1; done
      mv /run/shutdown /run/shutdown.old &>/dev/null || true
      chvt 1
      mount initrd -t tmpfs /initrd
      cd /initrd
      cpio -i < /var/current-system/boot/initrd-uncompressed
      mkdir new-root -p
      sync
      export PATH=$PATH:/init-tools/bin
      pivot_root . ./new-root
      exec chroot . /init-tools/bin/ash -c "
        mkdir /proc
        mount procfs -t proc /proc
        mount --move /new-root/dev /dev
        mkdir /self
        mountpoint /new-root/initrd && mount --move /new-root/initrd /self
        trap : 2 6 15
        sync
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs umount
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs fuser -m -k
        fuser -m -k /new-root/nix/store
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs umount
        sleep 1
        sync
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs fuser -m -k -2
        fuser -m -k /new-root/nix/store -2
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs umount
        sleep 0.5
        sync
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs fuser -m -k -6
        fuser -m -k /new-root/nix/store -6
        sleep 0.3
        sync
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs fuser -m -k -9
        fuser -m -k /new-root/nix/store -9
        sleep 0.1
        sync
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs umount
        cat /proc/mounts | cut -d ' ' -f 2 | grep /new-root | tac | xargs umount
        sleep 0.3
        umount /new-root
        sync
        cat /proc/mounts
        while true; do ash -i; done
      "
      echo failed: exec chroot
      while true; do
        mkdir /run
        rm /run/command
        /bin/sh -i
        eval "$(cat /run/command)"
      done
    '';
    gettyConsoles = [];
    gettyCommands = ''
      for i in ${builtins.toString self.gettyConsoles}; do
        while true; do ${pkgs.utillinux}/bin/agetty $i -l /var/current-system/sw/bin/login; sleep 1; done &
      done
    '';
    stage2InitScript = pkgs.writeScript "stage2-init" self.stage2InitCommands;
    system = pkgs.runCommand "system-instance" {
      preferLocalBuild = true;
    } ''
      mkdir -p "$out"/{boot/for-bootloader,setuid,global/usr/bin,global/bin,bin}
      ln -s "${self.systemSoftware}" "$out/sw"
      ln -s "${self.initrd.kernel}" "$out"/boot/kernel-package
      ln -s "${self.initrd.kernel}/bzImage" "$out"/boot/kernel
      ln -s "${self.initrd}" "$out"/boot/initrd-package
      ln -s "${self.initrd}"/initrd "$out"/boot/initrd
      gzip -d < "$out"/boot/initrd > "$out"/boot/initrd-uncompressed
      ln -s "${self.initrd.kernelModules}" "$out"/boot/kernel-modules
      ln -s "${self.firmwarePath}/lib/firmware" "$out"/boot/firmware
      ln -s "${self.kernelParametersFile}" "$out"/boot/kernel-parameters

      # For copying to bootloader stash
      ln -s "${self.initrd.kernel}/bzImage" "$out/boot/for-bootloader/$(basename "${self.initrd.kernel}").linux.efi"
      ln -s "${self.initrd}/initrd" "$out/boot/for-bootloader/$(basename "${self.initrd}").initrd.efi"
      "${./grub-print-entry.sh}" "${self.systemCaption}" \
        "$out/boot/for-bootloader"/*.linux.efi "$out/boot/for-bootloader"/*.initrd.efi \
        targetSystem="$out" BOOT_IMAGE="${self.initrd.kernel}" \
        "$(cat "${self.kernelParametersFile}")" > "$out/boot/for-bootloader/grub.part.cfg"

      # NixOS compatibility for SystemTap
      ln -s "$out"/boot/kernel "$out"/kernel

      ln -s "${self.setuidPrograms}" "$out"/setuid/programs
      ln -s "/var/setuid-wrapper-storage/$(basename "${self.setuidPrograms}")" "$out/setuid/wrappers"

      ln -s "${self.serviceDir}" "$out/services"

      ln -s "${self.etc}" "$out"/global/etc-static
      ln -sf "/var/etc-mountpoint/$(basename "$out")" "$out/global/etc"
      ln -sf "/var/etc-workdir/$(basename "$out")" "$out/global/etc-workdir"
      ln -s "$out/sw/bin/sh" "$out/global/bin/sh"
      ln -s "$out/sw/bin/env" "$out/global/usr/bin/env"

      ln -s "${self.systemActivationScript}" "$out/bin/activate"
      ln -s "${self.chrootEnv}/bin/global-chroot" "$out/bin/fhs-chroot"
      ln -s "${self.modprobeScript}" "$out/bin/modprobe"
      ln -s "${self.createGrubCfgScript}" "$out/bin/create-grub-config"
      ln -s "${self.stage2InitScript}" "$out/bin/init"
      ln -s "${self.switchScript}" "$out/bin/switch"
      ln -s "${self.runServiceScript}" "$out/bin/run-service"
      ln -s "${self.viewServiceLogScript}" "$out/bin/view-service-log"

      echo "${self.systemCaption}" > "$out/boot/system-caption"
    '';
    switchScript = pkgs.writeScript "switch" ''
      "$(dirname "$0")/activate"
      "$(dirname "$0")/create-grub-config"
    '';
    chrootEnv = pkgs.buildFHSUserEnv {
      name = "global-chroot";
      targetPkgs = pkgs: self.globalChrootPackages;
      inherit (self) extraOutputsToInstall;
    };
    globalChrootPackages = self.systemPackages;
    runServiceCode = "#! ${pkgs.stdenv.shell}\n" + ''
      svc="$1"
      shift
      mkdir -p "/var/log/services/$svc"
      timestamp=$(date +%Y%m%d-%H%M%S)
      if test -n "$SERVICE_USER"; then
        env -i PATH=/var/current-system/sw/bin:/var/current-system/sw/sbin \
          su -s /bin/sh "$SERVICE_USER" -c \
          /var/current-system/services/scripts/"$svc" "$@" \
          < /dev/null \
          > /var/log/services/"$svc"/$timestamp-stdout.log \
          2> /var/log/services/"$svc"/$timestamp-stderr.log &
      else
        env -i PATH=/var/current-system/sw/bin:/var/current-system/sw/sbin \
          /var/current-system/services/scripts/"$svc" "$@" \
          < /dev/null \
          > /var/log/services/"$svc"/$timestamp-stdout.log \
          2> /var/log/services/"$svc"/$timestamp-stderr.log &
      fi
      disown
    '';
    runServiceScript = pkgs.writeScript "run-service" self.runServiceCode;
    viewServiceLogCode = "#! ${pkgs.stdenv.shell}\n" + ''
      ls /var/log/services/"$1"/*-std"$2".log | tail -n 1 | xargs cat
    '';
    viewServiceLogScript = pkgs.writeScript "view-service-log" self.viewServiceLogCode;
    modprobeCode = ''#! ${pkgs.stdenv.shell}
      export PATH="''${0%/bin/modprobe}"/sw/bin:/var/current-system/sw/bin:/init-tools/bin
      MODULE_DIR="$(dirname "$0")/../boot/kernel-modules/lib/modules" modprobe "$@" ||
      MODULE_DIR="/var/current-system/boot/kernel-modules/lib/modules" modprobe "$@" ||
      MODULE_DIR="/run/booted-system/boot/kernel-modules/lib/modules" modprobe "$@" ||
      MODULE_DIR="/new-root/$(readlink -f "$(readlink -f /new-root/var/latest-booted-system)"/boot/kernel-modules)/lib/modules" modprobe "$@"
    '';
    kernelParameters = [];
    kernelParametersFile = pkgs.writeText "kernel-parameters" (builtins.toString self.kernelParameters);
    modprobeScript = pkgs.writeScript "modprobe" self.modprobeCode;
    systemCaption = "EveRescueNix";
    extraGrubHeader = "";
    extraGrubEntries = "";
    createGrubCfgCode = ''
      mkdir -p /boot/kernels
      grubHeader="$(${./grub-print-header.sh} /boot)"
      cp -f /boot/grub/grub.cfg{,.old}
      sync
      mv /boot/grub/grub.cfg{.new,}
      sync

      mkdir -p /boot/grub/fragments.new
      for i in /nix/var/nix/profiles/*/ /run/booted-system/ /var/current-system/; do
        test -e "$i/boot/for-bootloader/grub.part.cfg" && {
          test -d "/boot/grub/fragments/$(basename "$i")" &&
            mv "/boot/grub/fragments/$(basename "$i")" "/boot/grub/fragments.new/$(basename "$i")"
        }
      done
      sync
      rm -rf /boot/grub/fragments
      mv /boot/grub/fragments.new /boot/grub/fragments
      sync
      for i in /boot/kernels/*.efi; do
        grep "''${i#/boot}" /boot/grub/fragments/*/grub.part.cfg -m1 > /dev/null || rm "$i"
      done
      n=0
      rm /boot/grub/fragment-index/*
      mkdir -p /boot/grub/fragment-index/
      for i in /var/current-system/ /run/booted-system/ /nix/var/nix/profiles/*-link/ ; do
        test -e "$i/boot/for-bootloader/grub.part.cfg" && {
          n=$((n+1))
          echo "/boot/grub/fragments/$(basename "$i")" > /boot/grub/fragment-index/$(printf "%06d" $n)
          cp -fL "$i/boot/for-bootloader/"/grub.part.cfg "/boot/grub/fragments/$(basename "$i")"/ 2>/dev/null
          rm "/boot/grub/fragments/$(basename "$i")" 2> /dev/null
          test -d "/boot/grub/fragments/$(basename "$i")" || {
            mkdir "/boot/grub/fragments/$(basename "$i")"
            cp -fL "$i/boot/for-bootloader/"/grub.part.cfg "/boot/grub/fragments/$(basename "$i")"/ 2>/dev/null
            cp -L "$i/boot/for-bootloader/"/*.efi /boot/kernels/
          }
        }
      done
      sync
      for i in /boot/grub/fragments/*; do
        sed -re "s@^menuentry[^\"]*\"@&$(basename "$i") @"  "$i/grub.part.cfg" > "$i/grub.part.labeled.cfg"
        ( echo "$grubHeader"; cat "$i/grub.part.labeled.cfg" ) > "$i/grub.one.cfg"
      done
      cp /boot/grub/grub.fragmented.cfg{,.old}
      sync
      ( echo "$grubHeader"; cat /boot/grub/fragment-index/* |
          sed -e 's@$@/grub.part.labeled.cfg@' | xargs cat ) > /boot/grub/grub.fragmented.cfg
      cp /boot/grub/grub{.fragmented,}.cfg
      sync
    '';
    createGrubCfgScript = pkgs.writeScript "create-grub-config" self.createGrubCfgCode;
    profileText = self.pamEnvironmentText + self.profileSpecificText
      + (lib.optionalString (self.nixRemoteMachines != []) self.nixRemoteBuildEnv)
      + self.extraProfileText;
    extraProfileText = "";
    profileSpecificText = ''
      if test "$USER" = root; then
        export NIX_REMOTE=
      else
        export NIX_REMOTE=daemon
      fi
      export PAGER="less -R"
      export NIX_PATH="${self.lib.concatStringsSep ":" self.nixPath}"
      export GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt
      export INFOPATH=/var/current-system/sw/share/info
      
      export http_proxy=http://127.0.0.1:3128
      export https_proxy=http://127.0.0.1:3128
    '';
    nixPath = [];
    profile = pkgs.writeText "profile" self.profileText;
    loginDefsText = ''
      DEFAULT_HOME yes

      SYS_UID_MIN  400
      SYS_UID_MAX  499
      UID_MIN      1000
      UID_MAX      29999

      SYS_GID_MIN  400
      SYS_GID_MAX  499
      GID_MIN      1000
      GID_MAX      29999

      TTYGROUP     tty
      TTYPERM      0620

      # Ensure privacy for newly created home directories.
      UMASK        077

      # Uncomment this to allow non-root users to change their account
      #information.  This should be made configurable.
      #CHFN_RESTRICT frwh

    '';
    loginDefs = pkgs.writeText "login.defs" self.loginDefsText;
    firmwarePackages = [];
    firmwarePath = pkgs.runCommand "firmware-set" {} ''
      mkdir -p "$out/lib/firmware"
      ${ lib.concatMapStrings
      (x: '' cp -fa "${x}/lib/firmware"/* "$out/lib/firmware"'')
      self.firmwarePackages }
    '';
    fontPackages = [];
    fontsConf = pkgs.makeFontsConf {fontDirectories = self.fontPackages;};
    etcFonts = null;
    hostName = "local-everescue-nix-host";
    nsswitchOptions = {
      passwd = ["files"];
      group = ["files"];
      shadow = ["files"];
      ethers = ["files"];
      services = ["files"];
      protocols = ["files"];

      hosts = ["files" "dns"];
      networks = ["files" "dns"];
    };
    nsswitchConf = pkgs.writeText "nsswitch.conf" 
    (lib.concatMapStrings
      (x: "${x}: ${builtins.toString (builtins.getAttr x self.nsswitchOptions)}\n")
      (builtins.attrNames self.nsswitchOptions));
    services = [];
    serviceNamer = defaultType: defaultName: x:
      if builtins.isString defaultName && defaultName != "" then
        if defaultType == "config" then
          x.configName or x.serviceName or defaultName
        else
          x.scriptName or x.serviceName or defaultName
      else
        if defaultType == "config" then
          x.configName or x.serviceName or x.name or defaultName
        else
          x.scriptName or x.serviceName or x.name or defaultName
      ;
    serviceSymlinker = defaultType: defaultName: x:
      if builtins.isList x then 
        (lib.concatMapStrings 
          (self.serviceSymlinker defaultType defaultName) x)
      else if builtins.isString x then 
        ''ln -s "${x}" "$out/${defaultType}s/${defaultName}";''
      else if builtins.isAttrs x then
          (
            (self.serviceSymlinker "config" (self.serviceNamer "config" defaultName x) (x.config or []))
            +
            (self.serviceSymlinker "config" (self.serviceNamer "config" defaultName x) (x.configs or []))
            +
            (self.serviceSymlinker "script" (self.serviceNamer "script" defaultName x) (x.script or []))
            +
            (self.serviceSymlinker "script" (self.serviceNamer "script" defaultName x) (x.scripts or []))
            +
            (self.serviceSymlinker defaultType (self.serviceNamer defaultType defaultName x) (x.outPath or []))
            +
            (if x ? scriptCode then 
              (self.serviceSymlinker 
                defaultType 
                (self.serviceNamer "script" defaultName x) 
                (pkgs.writeScript (self.serviceNamer "script" defaultName x) x.scriptCode)) else "")
          )
     else throw "Unknown service definition form";
    serviceDir = pkgs.runCommand "services" {} (''mkdir -p "$out"/{scripts,configs}; '' + 
      (lib.concatMapStrings (self.serviceSymlinker "script" "") self.services));
    serviceDefinitions = (import ./services.nix self);
  }
  // (import ./pam.nix self)
  // (import ./nix.nix self)
  // (overrides self));
  initial = composeFun initial (x: {});
  expressions = composeFun expressions overrides;
in expressions
