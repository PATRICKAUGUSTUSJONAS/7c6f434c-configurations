# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, pkgs, ... }:

{
  imports =
    [ # <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ];

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "usb_storage" ];
  boot.initrd.kernelModules = ["fbcon" "hid_generic" "usbhid" "xhci-hcd"];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { label = "SystemRoot";
      fsType = "btrfs";
      neededForBoot = true;
    };

  fileSystems."/boot" =
    { label = "EFI";
      fsType = "vfat";
      neededForBoot = true;
    };

  fileSystems."/nix" =
    { label = "Nix";
      fsType = "btrfs";
      neededForBoot = true;
    };

  fileSystems."/tmp" =
    { label = "Tmp";
      fsType = "btrfs";
      neededForBoot = true;
    };

  swapDevices =[ 
    { label = "Swap"; }
  ];

  nix.maxJobs = 8;
}
