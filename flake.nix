{
  description = "Tracky - an open source, free (as in freedom and beer) expense tracker. Compatible with My Expenses backups.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {
        inherit system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      }));
    in {
      devShells = forAllSystems (pkgs:
        let
          android = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ "34" "35" "36" ];
            buildToolsVersions = [ "35.0.0" "36.0.0" ];
            includeNDK = true;
            ndkVersions = [ "28.2.13676358" ];
            includeCmake = false;
            includeEmulator = false;
            includeSystemImages = false;
            includeSources = false;
          };
          androidSdk = android.androidsdk;
          jdk = pkgs.jdk21;
        in {
          default = pkgs.mkShell {
            name = "my-expenses-open";
            packages = [
              pkgs.flutter
              androidSdk
              pkgs.android-tools
              jdk
              pkgs.git
              pkgs.unzip
              pkgs.zip
              pkgs.which
              pkgs.pkg-config
              pkgs.cmake
              pkgs.ninja
              pkgs.curl
              pkgs.jq
              pkgs.gnused
            ];

            NIX_ANDROID_SDK = "${androidSdk}/libexec/android-sdk";
            ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            JAVA_HOME = "${jdk}/lib/openjdk";
            GRADLE_OPTS = "-Dorg.gradle.jvmargs=-Xmx4g -Dorg.gradle.daemon=false";
            PUB_CACHE = builtins.toString self + "/.pub-cache";
            GRADLE_USER_HOME = builtins.toString self + "/.gradle";

            shellHook = ''
              # The Nix Android SDK is immutable, while Flutter 3.47 always asks
              # AGP to provision an NDK. Create a small writable overlay with the
              # NDK exposed under the canonical ndk/<version> path so Flutter
              # recognises it and does not call sdkmanager.
              SDK_OVERLAY="$PWD/.android-sdk"
              mkdir -p "$SDK_OVERLAY/ndk"
              for entry in "$NIX_ANDROID_SDK"/*; do
                ln -sfn "$entry" "$SDK_OVERLAY/$(basename "$entry")"
              done
              ln -sfn "$NIX_ANDROID_SDK/ndk-bundle" "$SDK_OVERLAY/ndk/28.2.13676358"
              export ANDROID_HOME="$SDK_OVERLAY"
              export ANDROID_SDK_ROOT="$SDK_OVERLAY"
              rm -f "$PWD/android/local.properties"
              export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
              export PUB_CACHE="$PWD/.pub-cache"
              export GRADLE_USER_HOME="$PWD/.gradle"
              mkdir -p "$PUB_CACHE" "$GRADLE_USER_HOME"
              echo "Tracky development shell"
              echo "  flutter: $(flutter --version 2>/dev/null | head -n1)"
              echo "  android: $ANDROID_HOME"
              echo "  build:   flutter build apk --release"
            '';
          };
        });

      packages = forAllSystems (pkgs: { });
    };
}
