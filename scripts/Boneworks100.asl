state("BONEWORKS") {
  int levelNumber : "GameAssembly.dll", 0x01E7E4E0, 0xB8, 0x590;
}

init {
  var module = modules.First(x => x.ModuleName == "vrclient_x64.dll");

  var scanner =
      new SignatureScanner(game, module.BaseAddress, module.ModuleMemorySize);

  vars.loadingPointer = scanner.Scan(new SigScanTarget(
      3,
      "4889??????????488B??????????48FF????488B??????????488B??4889??????????488D??????????488B??????????48FF??????????????????????????????488B??????????418B") {
    OnFound = (process, scanners, addr) =>
        addr + 0x4 + process.ReadValue<int>(addr)
  });
  if (vars.loadingPointer == IntPtr.Zero) {
    throw new Exception("Game engine not initialized - retrying");
  }

  vars.isLoading =
      new MemoryWatcher<bool>(new DeepPointer(vars.loadingPointer, 0xC54));

  var arenaTarget = new SigScanTarget(7, "D5 E2 03 34 C2 DF 63 ??");
  IntPtr ptr = IntPtr.Zero;
  foreach (var page in game.MemoryPages(true)) {
    var pageScanner =
        new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
    ptr = pageScanner.Scan(arenaTarget);
    if (ptr != IntPtr.Zero)
      break;
  }
  if (ptr == IntPtr.Zero) {
    throw new Exception("Arena state not found - retrying");
  }
  vars.arenaWatcher = new MemoryWatcher<byte>(ptr);

  // Index in levelOrder to start the run at (for practice)
  vars.startingSplit = 0;

  // Will split when entering each level in this list in this order
  // If entering a level later in the list it will split until it reaches it
  vars.levelOrder = new int[] {
    2,  // scene_theatrigon_movie01 -> scene_breakroom
    4,  // scene_museum
    5,  // scene_streets
    6,  // scene_runoff
    7,  // scene_sewerStation
    8,  // scene_warehouse
    9,  // scene_subwayStation
    10, // scene_tower
    11, // scene_towerBoss
    12, // scene_theatrigon_movie02 -> scene_dungeon
    14, // scene_arena
    15, // scene_throneRoom
    1,  // scene_mainMenu
    18, // scene_redactedChamber
    19, // sandbox_handgunBox
    22, // scene_hoverJunkers
    16, // arena_fantasy
    23, // zombie_warehouse
    1,  // scene_mainMenu
    6,  // scene_runoff
    1,  // scene_mainMenu
  };
  vars.levelOrderIdx = 0;
  vars.targetLevelOrderIdx = vars.startingSplit;
}

update {
  vars.isLoading.Update(game);
  vars.arenaWatcher.Update(game);
}

isLoading { return vars.isLoading.Current; }

start {
  if (vars.isLoading.Current &&
      current.levelNumber == vars.levelOrder[vars.startingSplit]) {
    vars.levelOrderIdx = 0;
    return true;
  }
  return false;
}

split {
  if (vars.arenaWatcher.Current != vars.arenaWatcher.Old) {
    return true;
  }

  if (vars.isLoading.Current &&
      (!vars.isLoading.Old || current.levelNumber != old.levelNumber)) {
    var nextLevelOrderIdx = vars.targetLevelOrderIdx + 1;
    if (nextLevelOrderIdx < vars.levelOrder.Length &&
        vars.levelOrder[nextLevelOrderIdx] == current.levelNumber) {
      vars.targetLevelOrderIdx = nextLevelOrderIdx;
    }
  }

  if (vars.levelOrderIdx < vars.targetLevelOrderIdx) {
    vars.levelOrderIdx++;
    // Skip splitting here because fantasy arena splits at the end
    var isFirstZombieWarehouseSplit =
        vars.levelOrderIdx == Array.IndexOf(vars.levelOrder, 23);
    return !isFirstZombieWarehouseSplit;
  }

  return false;
}

exit { timer.IsGameTimePaused = true; }
