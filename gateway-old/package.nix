# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                    // straylight-llm // package
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#     "The sky above the port was the color of television,
#      tuned to a dead channel."
#
#                                                          — Neuromancer
#
# Haskell derivation for the straylight-llm gateway binary.
# n.b. builds with GHC 9.10 for stability
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  lib,
  haskellPackages,
  stdenvNoCC,
}:
let
  hp = haskellPackages;

  # Ensure LICENSE is included in the source tree.
  # n.b. cabal requires license-file, copy from parent if missing.
  gatewaySource = stdenvNoCC.mkDerivation {
    name = "straylight-llm-source";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.unions [
        ./../LICENSE
        ./.
      ];
    };
    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      cp -r gateway $out
      cp LICENSE $out/
    '';
  };
in
hp.mkDerivation {
  pname = "straylight-llm";
  version = "0.1.0.0";
  src = gatewaySource;

  isLibrary = true;
  isExecutable = true;

  libraryHaskellDepends = [
    hp.aeson
    hp.bytestring
    hp.http-client
    hp.http-client-tls
    hp.http-types
    hp.mtl
    hp.text
    hp.time
    hp.uuid
    hp.wai
    hp.warp
  ];

  executableHaskellDepends = [ ];

  # n.b. tests disabled in nix build — hedgehog/hspec-hedgehog not in
  # standard haskellPackages; run tests via cabal in devShell instead
  doCheck = false;

  homepage = "https://github.com/weyl-ai/straylight-llm";
  description = "CGP-first OpenAI-compatible LLM gateway with verified types";
  license = lib.licenses.mit;
  mainProgram = "straylight-llm";
}
