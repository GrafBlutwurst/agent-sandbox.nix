# mkDarwinSandbox. Everything about the sandbox itself lives in launcher/.
{ pkgs, shared }:
{
  pkg,
  binName,
  outName,
  allowedPackages,
  allowNix ? false,
  allowUnixSockets ? false,
  rwDirs ? [ ],
  rwFiles ? [ ],
  roDirs ? [ ],
  roFiles ? [ ],
  env ? { },
  allowedDomains ? null,
  allowedLocalPorts ? [ ],
  # Internal, for the test harness: maps "host" to "addr:port" so the proxy
  # dials a local address instead of resolving the original.
  _proxyRedirects ? { },
  # Legacy args: accepted so assertNoLegacyArgs can name them in its error.
  restrictNetwork ? null,
  extraEnv ? null,
  stateDirs ? null,
  stateFiles ? null,
}:
let
  implicitPackages = shared.mkImplicitPackages allowNix;

  pathStr = pkgs.lib.makeBinPath (allowedPackages ++ implicitPackages);

  closurePathsFile = pkgs.writeClosure (
    allowedPackages
    ++ implicitPackages
    ++ [
      pkg
      shared.preEntryScript
    ]
  );

  validatedAllowedLocalPorts = shared.validateAllowedLocalPorts allowedLocalPorts;

  validatedAllowUnixSockets = shared.validateAllowUnixSockets {
    allowNix = allowNix;
    allowUnixSockets = allowUnixSockets;
  };

  sandboxBuildSpec = import ./spec.nix
    {
      pkgs = pkgs;
      shared = shared;
    }
    {
      platform = "darwin";
      outName = outName;
      pkg = pkg;
      binName = binName;
      sandboxPath = pathStr;
      allowNix = allowNix;
      rwDirs = rwDirs;
      rwFiles = rwFiles;
      roDirs = roDirs;
      roFiles = roFiles;
      env = env;
      allowedLocalPorts = validatedAllowedLocalPorts;
      allowUnixSockets = validatedAllowUnixSockets;
      closurePathsFile = closurePathsFile;
      preEntryScript = shared.preEntryScript;
      allowedDomains = allowedDomains;
      _proxyRedirects = _proxyRedirects;
    };

  envFragment = shared.mkEnvFragment {
    outName = outName;
    env = env;
  };

  stub = shared.mkStub {
    spec = sandboxBuildSpec;
    envFragment = envFragment;
  };

in
shared.mkWrapper {
  outName = outName;
  stub = stub;
  buildSpec = sandboxBuildSpec;
  legacyArgs = {
    restrictNetwork = restrictNetwork;
    extraEnv = extraEnv;
    stateDirs = stateDirs;
    stateFiles = stateFiles;
  };
  allowedLocalPorts = validatedAllowedLocalPorts;
  allowUnixSockets = validatedAllowUnixSockets;
}
