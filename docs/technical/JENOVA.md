# Jenova decision record

Status: **experimental spike rejected for production** (2026-10-13).

Jenova was evaluated to make `.cpp` files behave like Godot scripts. The frost
lab proved that the experiment could run on Windows and Linux, but it was never
approved as a shipping dependency.

It was rejected because:

- the pinned builder had no macOS target;
- the repository had to vendor a large runtime, generated Godot SDK and compiler
  integration;
- runtime unload behavior masked non-zero Godot process exit codes;
- maintaining a second native runtime and a separate script compiler duplicated
  the supported GDExtension pipeline.

The active Jenova runtime, SDK, workflows, compiler installer and frost adapter
were removed from the current tree. Their commits remain in Git history as
experiment evidence; they must not be restored into production branches.

An older local clone can retain the ignored `Jenova/Compilers/` cache after the
tracked directory is removed. Close Godot and delete that cache manually. If an
old `.godot/extension_list.cfg` still names Jenova, remove the local `.godot/`
cache and let Godot import the project again.

The approved C++ path is `GDExtension + godot-cpp`, documented in
[`GDEXTENSION.md`](GDEXTENSION.md). Portable logic stays independent of Godot;
thin GDExtension classes expose it to the engine. Heavy Windows, Linux and macOS
compilation runs on GitHub Actions, and developers install the verified artifact
instead of compiling locally.
