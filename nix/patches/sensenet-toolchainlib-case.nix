# nix/patches/sensenet-toolchainlib-case.nix
#
# Workaround for sensenet toolchainlib case mismatch bug.
# The toolchains.nix uses camelCase (mkBuckconfigLocal) but
# flake-module.nix calls lowercase (mkbuckconfiglocal).
#
# This creates aliases for the lowercase versions.
#
{ lib, pkgs }:
let
  original = import "${inputs.sensenet}/nix/modules/flake/sensenet/toolchains.nix" {
    inherit lib pkgs;
  };
in
original
// {
  # Lowercase aliases for camelCase functions
  mkbuckconfiglocal = original.mkBuckconfigLocal;
  mkcxxsection = original.mkCxxSection;
  mkhaskellsection = original.mkHaskellSection;
  mkrustsection = original.mkRustSection;
  mkleansection = original.mkLeanSection;
  mkpythonsection = original.mkPythonSection;
  mknvsection = original.mkNvSection;
  mkpurescriptsection = original.mkPureScriptSection;
  mkremoteexecutionsection = original.mkRemoteExecutionSection;
}
