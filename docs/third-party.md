# Third-party notices

## Kenney Animated Characters

The Collector's body, skin and its idle/run/jump clips are from **Animated
Characters Retro** by Kenney (<https://www.kenney.nl>), released under **CC0
1.0**. The plodding **walk** clip is from **Animated Characters Bundle**, also
by Kenney and CC0 1.0. The vomit spray is project code; its projectile scene
does not use an animation clip.

The source FBX files, the `humanMaleA` skin and both pack licences are vendored
under `assets/characters/collector/` (`KENNEY_LICENSE.txt` and
`KENNEY_BUNDLE_LICENSE.txt`). The animation clips are extracted into
`assets/characters/collector/animations/` so the Collector prefab can own them
directly; `tools/build_collector_anims.gd` rebuilds those resources if the
source FBX files are changed.

## PSX Look

UMBILICAL vendors **PSX Look** by heyheythere
(<https://heyheythere.itch.io>) under `addons/psx_look/`.

Licence text: `addons/psx_look/LICENSE.txt`. In summary:

- Use the shaders, scripts and demo textures in any number of commercial and
  non-commercial games, apps and videos, modified or not.
- No attribution is required.
- Do not sell, share or redistribute the shaders, scripts or demo textures
  themselves, alone or as part of another asset pack, template or library.

### Local modifications

- `shaders/psx.gdshaderinc` has an optional triplanar block
  (`triplanar`, `triplanar_world`, `triplanar_scale`, `triplanar_offset`) so
  UMBILICAL's world-triplanar palette carries into the PSX materials. The rest
  of the pack is as shipped.
- Project-side `src/psx/` scripts add CSG-aware conversion, optional CSG
  densification and persistence around the pack. They do not relicense the
  pack.
