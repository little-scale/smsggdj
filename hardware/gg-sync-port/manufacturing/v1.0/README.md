# Hardware v1.0 fabrication exports

KiCad is configured to write Gerber and drill exports for the verified v1.0
board into this directory.

The editable files in `../../kicad/` remain the source of truth. Before
publishing a fabrication package:

1. Open and inspect the project using KiCad 10.0 or newer.
2. Run schematic and PCB design-rule checks.
3. Generate Gerber and Excellon drill files into this directory.
4. Inspect the generated layers in a Gerber viewer.
5. Package the outputs as `gg-sync-port-v1.0-gerbers.zip` and attach that
   archive to the matching GitHub release.

Generated fabrication outputs are deliberately not included here until they
have been regenerated and visually checked from the repository source.
