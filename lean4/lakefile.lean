import Lake
open Lake DSL

package «straylight» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩
  ]

@[default_target]
lean_lib «Straylight» where
  globs := #[.submodules `Straylight]
