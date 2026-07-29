# Languas

![Languas](/logo.png)
Languas is a small, statically composed operating system written in C. The
same core and application modules can be compiled as either:

- a Bootex-compatible ARMv6-M (Cortex-M0 / Cortex-M0+) ROM; or
- a native program for Windows, Linux, or macOS.

Modules are selected at build time. There is no runtime module loader and no
Python dependency.

## Build

Requirements:

- GNU Make
- Clang or a compatible C compiler
- `ld.lld` and `llvm-objcopy` when building ARMv6-M ROMs

Common commands:

```sh
make host       # Native programs for the current operating system
make x86        # 32-bit x86 native programs
make x64        # 64-bit x86 native programs
make arm        # ARMv6-M (Cortex-M0 / Cortex-M0+) ROMs
make all        # All targets supported by the local toolchain
make sanitize   # Host build with ASan and UBSan
make test       # ARM build plus ROM boundary tests
make list       # Show discovered modules
make clean      # Remove generated files
```

Individual applications can also be selected:

```sh
make commander
make vanilla
```

The Makefile uses `build.ps1` on Windows and `build.sh` on POSIX systems.
Override `CC`, `LD`, or `OBJCOPY` to select another toolchain.

## Static modules

Every module is stored under `modules/<name>/` with an `LGM1` manifest. The
builder discovers manifests, resolves `Depends` recursively, and compiles only
the selected source files into the final image.

```text
Commander
|-- Screen
`-- Key
```

For example, Commander contains Screen and Key. Debug and Vanilla are not
linked into it. A module with a `Profile` field is a buildable application;
library modules omit that field.

Example manifest:

```text
LGM1
Name: Commander
Sources: commander.c
Depends: Screen, Key
Defines:
Profile: 0x03
Description: Interactive shell application
```

## Targets

| Target | Output | Platform layer |
| --- | --- | --- |
| ARMv6-M / Cortex-M0 / Cortex-M0+ | Bootex `.rom` | Memory-mapped GPIO/UART |
| Windows x86/x64 | Native `.exe` | Win32 console |
| Linux | Native executable | POSIX terminal |
| macOS | Native executable | POSIX terminal |

The ARMv6-M implementation remains part of the same source tree as the host
implementation. Platform-specific behavior is isolated under `targets/`.

## Applications

- **Commander**: interactive terminal with `help`, `ver`, `mem`, `clear`,
  `echo`, and `panic` commands.
- **Vanilla**: minimal reference application.

Generated files are written to `build_arm/` and `output/`.

## ROM layout

```text
0x00000000 - 0x00000FFF  Bootex (4 KiB)
0x00001000 - 0x0000100B  Languas header (12 bytes)
0x0000100C - 0x00007FFF  Languas code and data image
```

Each generated ROM is checked before publication. The checker validates the
vector table, Thumb entry points, image profile, header fields, region sizes,
and fixed RAM stack boundary. See [SECURITY.md](SECURITY.md) for the exact
invariants and assurance limits.

## Current verification status

- Windows x86 and x64 builds have been compiled and started successfully.
- Host builds pass Clang Static Analyzer and ASan/UBSan startup checks.
- Commander and Vanilla ARMv6-M ROMs compile, link, and pass ROM validation.
- ROM boundary regression tests pass.
- Operation has been verified on RP2040 (Cortex-M0+) hardware.
- Linux and macOS runtime execution still requires testing on those platforms.
