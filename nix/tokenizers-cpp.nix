{ lib
, stdenv
, fetchFromGitHub
, cmake
, craneLib
}:

let
  version = "0.1.0-unstable-2025-02-05";

  src = fetchFromGitHub {
    owner = "mlc-ai";
    repo = "tokenizers-cpp";
    rev = "34885cfd7b9ef27b859c28a41e71413dd31926f5";
    hash = "sha256-m3A9OhCXJgvvV9UbVL/ijaUC1zkLHlddnQLqZEA5t4w=";
    fetchSubmodules = true;
  };

  # Rust source with our Cargo.lock
  rustSrc = stdenv.mkDerivation {
    name = "tokenizers-c-src";
    inherit src;
    phases = [ "unpackPhase" "installPhase" ];
    installPhase = ''
      mkdir -p $out
      cp -r rust/* $out/
      cp ${./tokenizers-Cargo.lock} $out/Cargo.lock
    '';
  };

  # Build the Rust tokenizers-c static library
  libtokenizers-c = craneLib.buildPackage {
    pname = "tokenizers-c";
    inherit version;
    
    src = rustSrc;
    
    doCheck = false;
    
    installPhaseCommand = ''
      mkdir -p $out/lib
      find target -name 'libtokenizers_c.a' -exec cp {} $out/lib/ \;
    '';
  };

in
stdenv.mkDerivation {
  pname = "tokenizers-cpp";
  inherit version src;

  nativeBuildInputs = [ cmake ];

  # Patch CMakeLists.txt to skip cargo build
  postPatch = ''
    # Comment out the cargo custom command that builds libtokenizers_c.a
    sed -i '/^add_custom_command(/,/^)/s/^/#DISABLED /' CMakeLists.txt
  '';

  cmakeFlags = [
    "-DMSGPACK_USE_BOOST=OFF"
    "-DMSGPACK_BUILD_TESTS=OFF"
    "-DMSGPACK_BUILD_EXAMPLES=OFF"
    "-DSPM_ENABLE_SHARED=OFF"
    "-DSPM_ENABLE_TCMALLOC=OFF"
  ];

  preConfigure = ''
    # Provide pre-built rust library where cmake expects it
    mkdir -p build/release
    cp ${libtokenizers-c}/lib/libtokenizers_c.a build/
    cp ${libtokenizers-c}/lib/libtokenizers_c.a build/release/
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/include
    
    cp libtokenizers_cpp.a $out/lib/
    cp ${libtokenizers-c}/lib/libtokenizers_c.a $out/lib/
    cp sentencepiece/src/libsentencepiece.a $out/lib/
    
    cp -r $src/include/* $out/include/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Cross-platform tokenizers binding to HuggingFace and SentencePiece";
    homepage = "https://github.com/mlc-ai/tokenizers-cpp";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}
