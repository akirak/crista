# The default cache path is immutable when odig is installed using Nix
export ODIG_CACHE_DIR := justfile_directory() + "/_build/default/.odig"
# Using _build directory may not be properly allowed for storing user contents
export SHERLODOC_DB := justfile_directory() + "/_build/default/.sherlodoc.marshal"

demo:
    dune exec crista

# Run Web Platform Tests. Also set BROWSER to a browser executable
wpt:
    WPT_ROOT=vendor/wpt ./scripts/run-wpt.sh

test:
    dune runtest

odig-odoc:
    odig odoc
