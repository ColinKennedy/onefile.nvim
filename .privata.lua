--- Configuration for privata, the module-boundary checker.
---
--- Everything here is one Neovim configuration, so a private name shared
--- between `modules.*` files is package-internal rather than a boundary
--- violation. Anything reaching in from outside `modules.*` is still reported.

return {
    package_private = { "modules" },
}
