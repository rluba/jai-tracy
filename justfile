set ignore-comments := true

# --login to ensure nu config files are loaded so jai alias works

set shell := ["nu", "--experimental-options", "pipefail=true", "--no-newline", "-c"]

alias b := build-dll
alias rb := rebuild-dll

[windows]
clean-dll:
    rm -rf tracy/build-windows

[windows]
build-dll:
    #!/usr/bin/env nu
    mkdir tracy/build-windows
    env -C tracy/build-windows cmake .. -DTRACY_STATIC=0
    env -C tracy/build-windows cmake --build .
    ls tracy/build-windows/Debug/

rebuild-dll: clean-dll build-dll
