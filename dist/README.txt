MAKO Renderer @UPSTREAM_VERSION@ for ARM64 Linux (mako-arm64 @VERSION@)
=========================================================

A native aarch64 build of the MAKO Renderer (frame generation and scaling for
Vulkan games) for Snapdragon handhelds running ArmadaOS, such as the Retroid
Pocket 6. It is built from MAKO's own source by
https://github.com/Ken5998/mako-arm64 and is not an official MAKO release.

Install
  In Desktop Mode, open "Install MAKO Renderer" in this folder (or run it
  from a terminal). It copies the Renderer into ~/.local, keeps existing
  profiles, then opens MAKO Renderer Configuration. Run it again to update;
  "Uninstall MAKO Renderer" in the application menu removes it.

Use it in a game
  ArmadaOS games start with this Steam launch option:

      /usr/libexec/armada/armada-game-launch %command%

  Put MAKO's launcher in front of it:

      ~/.local/bin/mako-launch /usr/libexec/armada/armada-game-launch %command%

  Then pick Frame Generation and Scaling for that game in MAKO Renderer
  Configuration (Profile Matching > Detect Running Game finds its process).
  For a quick test without a profile, use MAKO's environment-only mode:

      MAKO_ENV=1 MAKO_MULTIPLIER=2 ~/.local/bin/mako-launch /usr/libexec/armada/armada-game-launch %command%

What works on ARM64
  - Games whose Vulkan runs as aarch64: native ARM64 ports and Proton ARM64
    games. x86 Linux games running under FEX are left alone.
  - MAKO FG, the default model, runs its separate x86-64 program through FEX
    with ArmadaOS's host Vulkan thunk (experimental).
  - The Lossless Scaling models (LSFG, LS1) need your own Lossless Scaling
    from Steam, default public branch.
  - MAKO Scaler.
  - Not yet: the bundled vkBasalt shaders, MangoHud through mako-launch,
    the MAKO Decky plugin (upstream turns it off on ArmadaOS on purpose).

Licences
  MAKO: GPL-3.0-or-later (share/doc/mako-render). MAKO FG model and runtime:
  CC BY-NC 4.0 and its runtime licence, non-commercial use only
  (share/doc/mako-render/mako-fg).
