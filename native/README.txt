Banjoball 0.3.1 native hot loops

The reference/fallback remains in scripts/native_grid_search.gd,
scripts/wc3_model.gd and scripts/wc3_particles.gd. --script-only selects it.
The module does not introduce threads, reduce particle counts, cap searches,
change match timing or modify the native-derived grid tie-breaking rules.

Build: run tools/build_acceleration.py with the bundled Python runtime.
Prerequisites installed outside the game project:
- godot-cpp 4.5 branch, commit 27d9dd23c83871e0619fca5dc2cddfbfd69e926a
  One portability change in src/godot.cpp: explicit #include <cstdlib>.
- LLVM MinGW 20261020 UCRT x86_64, archive SHA256
  fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd
- Android NDK 28.1.13356709 via Google's SDK manager.
- SCons 4.11.1.

All builds use the restricted class profile, release optimization and single
precision Godot vectors. The hot-loop translation unit disables FP contraction.
Android targets API 24, statically links libc++, and uses 16KB ELF load alignment.
SCons builds must run sequentially because generated bindings are shared.
The Windows DLL is needed to import the same staged project before APK export.
Only the matching Android library is shipped for each Android architecture.

Validation: tests/native_acceleration_test.gd compares every model's clips at
three positions (17,577 sampled bones), including finite handling of original
zero-scale hidden bones; particle integration and unreachable full-size paths
are compared against the script version. performance_navigation_test.gd also
checks 100 random routes against the earlier independent search reference.
particle_batch_test.gd compares committed mesh geometry, UV and packed colors.
Android execution and the native_acceleration report flag are checked separately.

Licenses and runtime notices are included in THIRD_PARTY.txt.
