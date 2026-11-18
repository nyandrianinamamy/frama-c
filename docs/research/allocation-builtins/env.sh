# Source from Bash. W28: measurement root holding frama-c/ (patched source) and oscs/.
# FRAMA_C_CHECKOUT: a checkout of this repository with its local opam switch.
w28=${W28:?}
cd "${FRAMA_C_CHECKOUT:?}"
eval "$(opam env --switch=. --set-switch)"
export PATH="$FRAMA_C_CHECKOUT/_opam/setup-venv/bin:$PATH"
build_root="$w28/frama-c"
cd "$build_root"
dune exec --no-build -- env | grep -E "^(OCAMLPATH|DUNE_SOURCEROOT|DUNE_OCAML_STDLIB|DUNE_OCAML_HARDCODED|DUNE_DIR_LOCATIONS)=" > "$w28/sites.env"
while IFS= read -r setting; do export "$setting"; done < "$w28/sites.env"
instrumented="$build_root/_build/install/default/bin"
cd "$w28"
