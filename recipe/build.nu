#!/usr/bin/env nu

# Node-RED conda build script using Nushell

def main [] {
    print "Starting Node-RED conda build process..."

    # Handle cross-compilation setup for macOS ARM64
    if ($env.target_platform?) == "osx-arm64" {
        $env.npm_config_arch = "arm64"
    }

    # Handle cross-compilation node symlink
    if ($env.build_platform?) != ($env.target_platform?) and ($env.build_platform?) != null {
        let node_path = $env.PREFIX | path join "bin" "node"
        let build_node_path = $env.BUILD_PREFIX | path join "bin" "node"

        if ($node_path | path exists) {
            ^rm $node_path
        }
        ^ln -s $build_node_path $node_path
    }

    # Use a clean, isolated npm cache to avoid EOF errors from stale/shared cache on macOS CI
    let npm_cache = $env.SRC_DIR | path join ".npm-cache"
    $env.npm_config_cache = $npm_cache

    # `npm pack` sweeps up everything in SRC_DIR, and rattler-build sets HOME to
    # SRC_DIR, so the conda build scratch files and any cache written under $HOME
    # would otherwise be installed into $PREFIX/lib/node_modules/node-red.
    # node-red's package.json has no "files" field, so .npmignore is honoured.
    [
        ".npm-cache/"
        ".npm/"
        ".cache/"
        ".local/"
        ".source_info.json"
        "build_env.sh"
        "conda_build.sh"
        "conda_build.log"
        "*.tgz"
        "pnpm-lock.yaml"
        "third-party-licenses.txt"
        ""
    ] | str join "\n" | save --force --raw ($env.SRC_DIR | path join ".npmignore")

    # Create package archive
    ^npm pack --ignore-scripts

    # Install Node-RED globally
    let package_file = $env.SRC_DIR | path join $"($env.PKG_NAME)-($env.PKG_VERSION).tgz"

    ^npm install --global --build-from-source $package_file

    # Generate license report on all platforms
    ^pnpm install
    ^pnpm-licenses generate-disclaimer --prod --output-file ($env.SRC_DIR | path join "third-party-licenses.txt")

    # Set up service configuration
    let share_dir = if ($nu.os-info.name == "windows") { $env.LIBRARY_PREFIX | path join "share" } else { $env.PREFIX | path join "share" }
    let pkg_share_dir = $share_dir | path join $env.PKG_NAME
    let service_target = $pkg_share_dir | path join "service.yaml"
    let service_source = $env.RECIPE_DIR | path join "service.yaml"

    mkdir $share_dir
    mkdir $pkg_share_dir
    cp $service_source $service_target

    if ($nu.os-info.name != "windows") {
        ^chmod 644 $service_target
    }

    print "Build completed successfully!"
}

# Note: nushell invokes `main` automatically when a script defines it, so there
# must be no explicit `main` call here. Calling it ran the whole build twice,
# and the second `npm pack` swept the work directory polluted by the first pass
# (npm cache, pnpm store, node_modules, the previous tarball) into the package.
