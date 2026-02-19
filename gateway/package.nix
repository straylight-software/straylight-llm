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
# n.b. builds with GHC 9.10, based on weapon-server-hs implementation
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  lib,
  haskellPackages,
}:
let
  hp = haskellPackages;
in
hp.mkDerivation {
  pname = "straylight-llm";
  version = "0.1.0.0";

  # n.b. use cleanSource to filter out build artifacts
  # the LICENSE file is already in gateway/ directory
  src = lib.cleanSource ./.;

  isLibrary = true;
  isExecutable = true;

  # ════════════════════════════════════════════════════════════════════════════
  #                                                        // library deps
  # ════════════════════════════════════════════════════════════════════════════

  libraryHaskellDepends = [
    hp.aeson
    hp.base64-bytestring
    hp.bytestring
    hp.case-insensitive
    hp.containers
    hp.crypton-connection
    hp.data-default-class
    hp.directory
    hp.filepath
    hp.http-client
    hp.http-client-tls
    hp.http-types
    hp.katip
    hp.mtl
    hp.network
    hp.posix-pty
    hp.process
    hp.random
    hp.servant
    hp.servant-server
    hp.stm
    hp.text
    hp.time
    hp.tls
    hp.unix
    hp.unliftio-core
    hp.wai
    hp.wai-websockets
    hp.warp
    hp.websockets
  ];

  # ════════════════════════════════════════════════════════════════════════════
  #                                                        // executable deps
  # ════════════════════════════════════════════════════════════════════════════

  executableHaskellDepends = [
    hp.aeson
    hp.bytestring
    hp.containers
    hp.directory
    hp.filepath
    hp.http-types
    hp.katip
    hp.process
    hp.servant-server
    hp.stm
    hp.text
    hp.time
    hp.wai
    hp.wai-websockets
    hp.warp
    hp.websockets
  ];

  # n.b. tests disabled in nix build — many test deps (haskemathesis, openapi3,
  # regex-pcre, etc.) not in standard haskellPackages; run tests via cabal in
  # devShell instead
  doCheck = false;

  homepage = "https://github.com/weyl-ai/straylight-llm";
  description = "CGP-first OpenAI-compatible LLM gateway with AI coding agent";
  license = lib.licenses.mit;
  mainProgram = "straylight-llm";
}
