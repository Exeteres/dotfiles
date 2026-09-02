{configuration}: let
  config = configuration.config;
  luksDevices = config.boot.initrd.luks.devices;
  disks = config.disko.devices.disk;
  rootDevice = config.fileSystems."/".device or null;
  rootDeviceMatch =
    if builtins.isString rootDevice
    then builtins.match "/dev/mapper/(.+)" rootDevice
    else null;
  encryptedRoot =
    if rootDeviceMatch == null
    then null
    else builtins.head rootDeviceMatch;
  findEncryptedRoots = content:
    (if (content.type or null) == "luks" && (content.name or null) == encryptedRoot
    then [content]
    else [])
    ++ (if content ? content then findEncryptedRoots content.content else [])
    ++ (if content ? partitions
    then builtins.concatLists (map findEncryptedRoots (builtins.attrValues content.partitions))
    else []);
  matchingRoots = builtins.concatLists (map (
    diskName:
      map (luks: {inherit diskName luks;}) (findEncryptedRoots disks.${diskName}.content)
  ) (builtins.attrNames disks));
  matchingRoot =
    if builtins.length matchingRoots == 1
    then builtins.head matchingRoots
    else null;
  selectedLuks = luksDevices.${encryptedRoot} or null;
  validated =
    assert encryptedRoot != null
    || throw "the root filesystem must use a /dev/mapper LUKS device";
    assert builtins.length matchingRoots == 1
    || throw "encrypted root ${encryptedRoot} must occur on exactly one disko disk";
    assert selectedLuks != null
    || throw "boot.initrd.luks.devices.${encryptedRoot} is required";
    true;
  disk = disks.${matchingRoot.diskName}.device;
in
  assert validated;
  {
    inherit disk encryptedRoot;
    diskoScript = config.system.build.diskoScript;
    luksDevice = selectedLuks.device;
    systemClosure = config.system.build.toplevel;
  }
