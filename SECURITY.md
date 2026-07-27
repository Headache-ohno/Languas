# Security model and checked invariants

This project does not claim that it has no vulnerabilities. Such a claim would
require a formal semantics for the C implementation, compiler, linker, Bootex
hardware model, and host operating systems. The following narrower properties
are enforced or can be proved from the current transition rules.

## Commander buffer bound

Let `n` be `s_cmd_len` and let the command array size be `N = 64`.

- Initialization sets `n = 0`.
- Append is permitted only when `n < N - 1`, writes index `n`, then increments.
- Backspace decrements only when `n > 0`.
- Execute writes the terminating NUL at index `n`.

By induction over input events, `0 <= n <= N - 1`. Therefore every array write
uses an index in `[0, N - 1]`. A preprocessor assertion additionally requires
`2 <= N <= 256`, matching the range of the `lg_u8` length variable.

Only printable ASCII is stored, so terminal control bytes cannot be replayed
through command or error output.

## ROM size bound

The packer accepts Bootex size `B` and application size `L` only when:

```text
10 <= B <= 4096
14 <= L <= 28672
```

Bootex is padded to exactly 4096 bytes, so output size is `4096 + L` and is
therefore in `[4110, 32768]`. All reads and writes are checked for short I/O.
The packer also proves from the vector table that the initial stack is exact,
the Reset Handler is Thumb code, and its first two bytes exist in the unpadded
Bootex input.
The verifier independently rejects images outside this interval and rejects
invalid vectors, headers, profiles, or entry placement.

## Cortex-M0 RAM separation

The linker scripts partition the 4 KiB SRAM as follows:

```text
[0x20000000, 0x20000020)  simulated I/O registers
[0x20000020, 0x20000E00)  .data and .bss
[0x20000E00, 0x20001000)  reserved 512-byte stack
```

These intervals are pairwise disjoint. Link-time assertions reject a static
image that crosses the stack boundary or changes the stack top expected by the
Bootex vector table.

Before either Bootex or Languas uses global state, startup code copies `.data`
from ROM and zeroes `.bss`.

## ROM control-flow entry

Link-time and runtime checks establish all of the following:

- The Bootex vector table contains exactly the initial SP and Reset handler.
- The Languas header is exactly 12 bytes at `0x00001000`.
- `lg_entry` begins at `0x0000100C`.
- Reset and application entry addresses have the Cortex-M Thumb bit set.
- The image profile is one of the values accepted by Bootex.

The build publishes a ROM only after the temporary image passes verification.

## Module dependency closure

Both builders perform depth-first dependency resolution. A module is emitted
after all dependencies, emitted at most once, and rejected when encountered a
second time on the active recursion path. Consequently the selected set is the
transitive dependency closure of the application for an acyclic manifest
graph.

## Dynamic checks

Hosted builds can enable AddressSanitizer and UndefinedBehaviorSanitizer:

```bat
build.bat commander -Target host -Sanitize
```

```sh
sh ./build.sh commander --sanitize
```

All C builds use `-Wall -Wextra -Wpedantic -Werror`.

## Not proved

The properties above do not prove correctness of LLVM, system libraries,
terminal drivers, physical hardware, or the Bootex simulator. They also do not
prove liveness, timing behavior, resistance to physical attacks, or absence of
all C undefined behavior. Those require additional testing, fuzzing, static
analysis, and eventually a formal model if high assurance is required.
