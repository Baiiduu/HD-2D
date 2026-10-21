# Derived surface normals

Lighting data prepared from unchanged source textures by `tools/build_surface_normals.py`.

- Source dimensions and alpha are preserved; normal RGB is linear OpenGL Y+ data.
- Atlas tiles are processed separately, including the 4×4 road atlas and 4×2 dodge sheet.
- Smooth shallow height estimates suppress small colour noise; characters additionally use broad silhouette volume.
- These are approximate normals, not reconstructed three-dimensional geometry or authored structural height maps.
- `manifest.json` records source paths, SHA-256 hashes, material kinds and atlas grids.
- Regenerate after changing a source texture. Source images are never written by the script.

Runtime controls: [parameters and styles](../../../../docs/technical/parameters-and-styles.md). Source textures, normal maps and regeneration metadata remain unchanged.
