try %{ evaluate-commands %sh{ anima init } }

# Temporary direct wiring until anima exists.
# anima init will subsume this when implemented.
evaluate-commands %sh{
    kak-tree-sitter --kakoune \
        --init "$kak_session" \
        --server --daemonize \
        --with-highlighting \
        --with-text-objects
}

colorscheme default
