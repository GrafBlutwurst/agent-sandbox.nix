# mkSandbox. Everything about the sandbox itself lives in launcher/.
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
  # Host→sandbox TCP forwards: an integer port (bound to 127.0.0.1) or
  # { port; bindAddr ? "127.0.0.1"; }. A wider bindAddr (e.g. "0.0.0.0" or a
  # container bridge gateway) exposes the sandboxed service to everything
  # that can reach that address.
  allowedInboundPorts ? [ ],
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
  platform = if pkgs.stdenv.isDarwin then "darwin" else "linux";

  implicitPackages = shared.mkImplicitPackages allowNix;

  pathStr = pkgs.lib.makeBinPath (allowedPackages ++ implicitPackages);

  closurePathsFile = pkgs.writeClosure (
    allowedPackages
    ++ implicitPackages
    ++ [ pkg ]
    # coreutils supplies the /usr/bin/env symlink target, and is deliberately
    # not in implicitPackages so it does not leak into PATH.
    ++ (if platform == "linux" then [ pkgs.coreutils ] else [ ])
    ++ [ shared.preEntryScript ]
  );

  validatedAllowedLocalPorts = shared.validateAllowedLocalPorts allowedLocalPorts;

  validatedAllowedInboundPorts = shared.validateAllowedInboundPorts allowedInboundPorts;

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
      platform = platform;
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
      allowedInboundPorts = validatedAllowedInboundPorts;
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
  allowedInboundPorts = validatedAllowedInboundPorts;
  allowUnixSockets = validatedAllowUnixSockets;
}
