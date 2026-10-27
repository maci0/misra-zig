# MISRA C:2025 in Zig 0.17

Every directive and rule of MISRA C:2025, and what it is in Zig 0.17.0. The topic column is a short paraphrase, not the MISRA text. Each Zig behavior below was checked with a one-file probe compiled or run on Zig 0.17.0.

A guideline is adopted when Zig compiles the hazard it targets and the result is illegal behavior, a crash, or a wrong value. Guidelines about readability or process are left out; a project can still apply them as written.

| Status | Meaning |
|---|---|
| adopted | A handbook entry with this id. |
| covered | Another entry carries the obligation; the note names it. |
| rejected | Zig 0.17.0 refuses the C form at compile time. |
| no counterpart | Zig has no such construct. |
| left out | Applies to Zig and is not part of this standard; the note says why. |
| process | A project activity, not a property of the code. |
| not assessed | Compiles, and the behavior the guideline is about is not stated in the 0.17.0 language reference. |

Of the 223 guidelines, 59 are adopted, 23 covered, 30 rejected, 81 have no counterpart, 27 are left out, 1 is process, and 2 are not assessed.

## Directives

| Id | Topic | Status | In Zig |
|---|---|---|---|
| Dir 1.1 | implementation-defined behavior is documented | covered | Dir 4.6: widths are explicit, and an `extern struct` layout is asserted next to the type. |
| Dir 1.2 | language extensions | no counterpart | One compiler defines the language. |
| Dir 2.1 | the code compiles | covered | The gate: `zig test` passes at `-ODebug` and `-OReleaseSafe`. |
| Dir 3.1 | code traces to requirements | process | |
| Dir 4.1 | run-time failures | adopted | |
| Dir 4.2 | assembly is documented | left out | Applies as written to `asm`. |
| Dir 4.3 | assembly is isolated | left out | Applies as written to `asm`. |
| Dir 4.4 | commented-out code | left out | Readability. |
| Dir 4.5 | look-alike identifiers | left out | Readability. |
| Dir 4.6 | sized types | adopted | |
| Dir 4.7 | error information is tested | adopted | An ignored error union is also rejected. |
| Dir 4.8 | hiding unused struct layouts | left out | `opaque {}` exists for it; a design choice. |
| Dir 4.9 | functions over function-like macros | no counterpart | No macros. |
| Dir 4.10 | include guards | no counterpart | No header files. |
| Dir 4.11 | values passed to library functions | adopted | Many std functions assert an argument; the caller checks it. |
| Dir 4.12 | dynamic allocation | adopted | Departs: allocation through an `Allocator` parameter is allowed. |
| Dir 4.13 | resource calls in order | covered | Rule 22.1 (one release), Rule 22.6 (use after close), Dir 5.3 (join once). |
| Dir 4.14 | values from outside are checked | adopted | |
| Dir 4.15 | NaN and infinity | adopted | |
| Dir 5.1 | data races | adopted | |
| Dir 5.2 | deadlocks | adopted | Lock order, and no second lock of a held mutex (C Rule 22.18). |
| Dir 5.3 | dynamic thread creation | adopted | |

## Rules 1 to 7

| Id | Topic | Status | In Zig |
|---|---|---|---|
| Rule 1.1 | syntax and limits | rejected | |
| Rule 1.3 | undefined behavior | covered | The standard's preamble and Dir 4.1: a safety check in Debug is not compliance. |
| Rule 1.4 | emergent features | no counterpart | Zig 0.17 marks no feature emergent. |
| Rule 1.5 | obsolescent features | adopted | Declarations the 0.17 std marks deprecated. |
| Rule 2.1 | unreachable code | adopted | Files the test root does not reach. Code after a `return` is rejected. |
| Rule 2.2 | dead code | left out | Unused locals and dropped results are rejected; a value stored and never read needs data flow. |
| Rule 2.3 | unused types | left out | An unused container-level declaration compiles, and Zig does not analyze it. |
| Rule 2.4 | unused tags | no counterpart | No tag namespace. |
| Rule 2.5 | unused macros | no counterpart | |
| Rule 2.6 | unused labels | rejected | |
| Rule 2.7 | unused parameters | rejected | `_ = name;` discards on purpose. |
| Rule 2.8 | unused objects | left out | An unused local is rejected; an unused container-level `var` compiles. |
| Rule 3.1 | comment markers inside comments | no counterpart | Only `//` comments. |
| Rule 3.2 | line splicing in comments | no counterpart | |
| Rule 4.1 | unterminated escapes | rejected | `\x` takes exactly two hex digits. |
| Rule 4.2 | trigraphs | no counterpart | |
| Rule 5.1 | distinct external names | rejected | Two `export fn f` in one file. |
| Rule 5.2 | distinct names in one scope | rejected | |
| Rule 5.3 | inner names hiding outer ones | rejected | Shadowing is an error. |
| Rule 5.4 | distinct macro names | no counterpart | |
| Rule 5.5 | names distinct from macros | no counterpart | |
| Rule 5.6 | unique typedef names | rejected | A type is a value; Rules 5.2 and 5.3 apply. |
| Rule 5.7 | unique tag names | no counterpart | |
| Rule 5.8 | unique external definitions | rejected | As Rule 5.1. |
| Rule 5.9 | unique internal names | no counterpart | Each file is its own namespace. |
| Rule 5.10 | reserved names | rejected | A name that shadows a primitive type, such as `const u8 = 1`. |
| Rule 6.1 | bit-field types | no counterpart | A `packed struct` field has an explicit integer type. |
| Rule 6.2 | signed one-bit fields | left out | `i1` states its range, 0 and -1, in the type. |
| Rule 6.3 | bit-fields in unions | no counterpart | |
| Rule 7.1 | octal constants | rejected | `010` is rejected; octal is `0o10`. |
| Rule 7.2 | unsigned suffix | no counterpart | A literal takes the type of its use. |
| Rule 7.3 | lowercase `l` suffix | no counterpart | |
| Rule 7.4 | string literal to non-const | rejected | `const s: []u8 = "abc"` |
| Rule 7.5 | integer-constant macro arguments | no counterpart | |
| Rule 7.6 | small integer-constant macros | no counterpart | |

## Rules 8 to 12

| Id | Topic | Status | In Zig |
|---|---|---|---|
| Rule 8.1 | explicit types | adopted | |
| Rule 8.2 | prototypes with named parameters | adopted | |
| Rule 8.3 | matching declarations | no counterpart | One declaration per entity. Rule 8.4 covers `extern fn`. |
| Rule 8.4 | a visible compatible declaration | adopted | |
| Rule 8.5 | one external declaration | covered | Rule 8.4: C declarations come from the translated header. |
| Rule 8.6 | one external definition | rejected | As Rule 5.1. |
| Rule 8.7 | external linkage only when needed | adopted | |
| Rule 8.8 | `static` for internal linkage | adopted | Departs: in Zig, no `pub` wrapper. |
| Rule 8.9 | block scope for one-function objects | left out | Readability. Shared state between threads is Dir 5.1. |
| Rule 8.10 | `static inline` | no counterpart | |
| Rule 8.11 | external array sizes | no counterpart | An array type carries its length. |
| Rule 8.12 | unique enum values | rejected | |
| Rule 8.13 | const pointers | adopted | |
| Rule 8.14 | `restrict` | adopted | `noalias`. |
| Rule 8.15 | matching alignment declarations | no counterpart | One declaration per entity. |
| Rule 8.16 | zero alignment | rejected | `align(0)` |
| Rule 8.17 | one alignment specifier | rejected | A second `align` does not parse. |
| Rule 8.18 | tentative definitions in headers | no counterpart | |
| Rule 8.19 | external declarations in source files | covered | Rule 8.4: a handwritten `extern fn` is reported. |
| Rule 9.1 | read before set | adopted | |
| Rule 9.2 | initializer braces | adopted | Departs: every field and element is written. |
| Rule 9.3 | partial array initialization | rejected | |
| Rule 9.4 | an element initialized twice | rejected | A field named twice in one literal. |
| Rule 9.5 | designated array initializers | no counterpart | |
| Rule 9.6 | chained designators | no counterpart | |
| Rule 9.7 | atomic objects initialized | covered | Rule 9.1: an `std.atomic.Value` set to `undefined` compiles, and reading it breaks 9.1. |
| Rules 10.1 to 10.8 | essential types | adopted | |
| Rule 11.1 | function pointer conversions | covered | Rule 11.3: `@ptrCast` of `&f` compiles and is reported. |
| Rule 11.2 | incomplete-type pointer conversions | covered | Rule 11.3 and Dir 4.1 (`headerOf`). |
| Rule 11.3 | object pointer conversions | adopted | |
| Rule 11.4 | pointer to integer | left out | `@intFromPtr` is how an alignment is tested (`headerOf`), and `@ptrFromInt` names a fixed hardware address. |
| Rule 11.5 | `void *` to object pointer | covered | Rule 11.3 and Dir 4.1: `@ptrCast` after a length and an alignment check. |
| Rule 11.6 | `void *` to integer | left out | As Rule 11.4. |
| Rule 11.8 | casting away qualifiers | adopted | `@constCast`, `@volatileCast`. |
| Rule 11.9 | form of the null pointer | rejected | `0` does not coerce to `?*T`; `null` is the only form. |
| Rule 11.10 | `_Atomic void` | no counterpart | |
| Rule 11.11 | implicit null tests | rejected | `if (p)` on an optional. |
| Rule 12.1 | explicit precedence | adopted | |
| Rule 12.2 | shift amount range | covered | Rule 10.1: the amount is compared with `@bitSizeOf` first. |
| Rule 12.3 | comma operator | no counterpart | |
| Rule 12.4 | constant unsigned wraparound | rejected | `const x: u8 = 255 + 1` |
| Rule 12.5 | `sizeof` on an array parameter | no counterpart | An array parameter has its length in the type; a slice has `.len`. |
| Rule 12.6 | members of atomic structs | covered | Dir 5.1: shared data goes through `std.atomic.Value` methods. |

## Rules 13 to 18

| Id | Topic | Status | In Zig |
|---|---|---|---|
| Rule 13.1 | side effects in initializer lists | left out | As Rule 13.2. |
| Rule 13.2 | evaluation order | not assessed | The 0.17.0 language reference states no order for operands or arguments. |
| Rule 13.3 | `++` and `--` with other side effects | no counterpart | |
| Rule 13.4 | using an assignment's value | adopted | The C form is rejected. The entry shows the Zig form: assign, then test. |
| Rule 13.5 | side effects right of `&&` and `\|\|` | left out | The language reference says `and` and `or` skip the right side; the skip is defined. |
| Rule 13.6 | side effects in `sizeof` | no counterpart | `@sizeOf` takes a type, and `@TypeOf` operands have no run-time side effects. |
| Rule 14.1 | float loop counters | left out | Compiles; the count drifts but stays defined. |
| Rule 14.2 | well-formed `for` | no counterpart | `for` walks a slice, an array, or a range. |
| Rule 14.3 | invariant conditions | covered | Rule 15.1: `while (true)` needs a bound. |
| Rule 14.4 | Boolean conditions | adopted | |
| Rule 15.1 | `goto` | adopted | Departs: no `goto` exists; a retry loop has a bound. |
| Rule 15.2 | backward `goto` | no counterpart | |
| Rule 15.3 | `goto` into a block | no counterpart | |
| Rule 15.4 | one exit per loop | left out | Readability. |
| Rule 15.5 | single exit | left out | Disapplied in C:2025. `defer` and `errdefer` release on every exit. |
| Rule 15.6 | braces around bodies | left out | `zig fmt` is mandatory and indents a statement after a braceless body at the `if`'s level, so it cannot pass for part of the body. |
| Rule 15.7 | final `else` | left out | An `if` that yields a value without `else` is rejected. A statement chain is not; Rule 16.4 covers the exhaustive form. |
| Rule 16.1 | well-formed `switch` | rejected | Prongs are expressions, and there is no fallthrough. |
| Rule 16.2 | case labels in nested blocks | no counterpart | |
| Rule 16.3 | ending each clause | adopted | |
| Rule 16.4 | a default clause | adopted | |
| Rule 16.5 | default first or last | left out | Where `else` sits does not change which prong runs. |
| Rule 16.6 | at least two clauses | left out | A one-prong `switch` compiles and is an ordinary expression. |
| Rule 16.7 | `switch` on a Boolean | left out | Compiles, and must list both values. |
| Rule 17.1 | variadic functions | adopted | `@cVaStart`. |
| Rule 17.2 | recursion | adopted | |
| Rule 17.3 | implicit declarations | rejected | |
| Rule 17.4 | a value on every return path | rejected | |
| Rule 17.5 | array argument sizes | no counterpart | `[N]T` and `*[N]T` carry the size; a slice carries `.len`. |
| Rule 17.7 | unused return values | rejected | |
| Rule 17.8 | modified parameters | rejected | Parameters are constant. |
| Rule 17.9 | a `noreturn` function that returns | rejected | |
| Rule 17.10 | `noreturn` with a non-void type | no counterpart | `noreturn` is the return type. |
| Rule 17.11 | marking functions that never return | left out | Readability. |
| Rule 17.12 | bare function names | no counterpart | A function name is a typed value. |
| Rule 17.13 | qualified function types | no counterpart | |
| Rule 18.1 | arithmetic past an array | covered | Rule 18.4. |
| Rule 18.2 | subtracting pointers into different arrays | covered | Rule 18.4: `q - p` on many-item pointers compiles. |
| Rule 18.3 | ordering pointers | rejected | `<` between two pointers. |
| Rule 18.4 | `+` and `-` on pointers | adopted | |
| Rule 18.5 | deep pointer nesting | left out | Readability. |
| Rule 18.6 | addresses that outlive their object | adopted | |
| Rule 18.7 | flexible array members | no counterpart | |
| Rule 18.8 | variable-length arrays | no counterpart | An array length is known at compile time. |
| Rule 18.9 | addresses of temporaries | not assessed | `&f()` compiles, and the language reference does not say how long the temporary lives. |
| Rule 18.10 | pointers to variably modified types | no counterpart | |

## Rules 19 to 23

| Id | Topic | Status | In Zig |
|---|---|---|---|
| Rule 19.1 | overlapping copies | adopted | |
| Rule 19.2 | `union` | adopted | |
| Rule 19.3 | reading an unset union member | adopted | |
| Rules 20.1 to 20.15 | the preprocessor | no counterpart | |
| Rule 21.3 | `malloc` and `free` | adopted | Departs as Dir 4.12. |
| Rule 21.4 | `setjmp` | no counterpart | |
| Rule 21.5 | `<signal.h>` | left out | `std.posix.sigaction` compiles. State a handler shares with other code is Dir 5.1. |
| Rule 21.6 | `<stdio.h>` | no counterpart | `std.Io` returns errors instead of `EOF` and `errno`. |
| Rule 21.7 | `atoi` and friends | no counterpart | `std.fmt.parseInt` returns an error for bad input or overflow. |
| Rule 21.8 | `abort`, `exit`, `getenv`, `system` | adopted | The termination part. Reading the environment and running a shell are left out. |
| Rule 21.9 | `bsearch` and `qsort` | no counterpart | `std.sort` is typed. |
| Rule 21.10 | time functions | no counterpart | |
| Rule 21.11 | `<tgmath.h>` | no counterpart | |
| Rule 21.12 | `<fenv.h>` | no counterpart | |
| Rule 21.13 | `<ctype.h>` arguments | rejected | `std.ascii` takes a `u8`. |
| Rule 21.14 | `memcmp` on strings | no counterpart | `std.mem.eql` compares lengths, then bytes. |
| Rule 21.15 | `memcpy` element types | rejected | `@memcpy` between element types that do not coerce. |
| Rule 21.16 | `memcmp` argument types | no counterpart | |
| Rule 21.17 | string functions past the bounds | adopted | |
| Rule 21.18 | `size_t` arguments | adopted | |
| Rule 21.19 | pointers from `localeconv` and friends | no counterpart | Applies as written when calling libc. |
| Rule 21.20 | pointers from `getenv` and friends | no counterpart | Applies as written when calling libc. |
| Rule 21.21 | `system` | no counterpart | |
| Rule 21.22 | `<tgmath.h>` argument types | no counterpart | |
| Rule 21.23 | `<tgmath.h>` argument agreement | no counterpart | |
| Rule 21.24 | `rand` | left out | Choosing a random source is a security decision, outside this standard. |
| Rule 21.25 | sequentially consistent atomics | adopted | |
| Rule 21.26 | `mtx_timedlock` | no counterpart | |
| Rules 22.1 to 22.10 | resources, streams, `errno` | adopted | |
| Rule 22.11 | joining or detaching twice | covered | Dir 5.3: joined once, never detached. |
| Rule 22.12 | thread objects through their functions | covered | Dir 5.1. |
| Rule 22.13 | storage of synchronization objects | covered | Rule 18.6 and Dir 5.3: a mutex outlives the threads, which are joined before it goes out of scope. |
| Rule 22.14 | synchronization objects initialized | covered | Rule 9.1: `var mu: std.Io.Mutex = undefined` compiles, and locking it reads `undefined`. |
| Rule 22.15 | destroying synchronization objects | covered | Dir 5.3. |
| Rule 22.16 | unlocking on the same thread | covered | Rule 22.1: `defer mu.unlock(io)` right after the lock. |
| Rule 22.17 | unlocking a mutex not held | covered | Rule 22.1. |
| Rule 22.18 | recursive locking | covered | Dir 5.2. |
| Rule 22.19 | one mutex per condition variable | left out | `std.Io.Condition.wait` takes the mutex on every call; a reader checks it is always the same one. |
| Rule 22.20 | thread-specific storage created first | no counterpart | A `threadlocal var` without an initializer is rejected. |
| Rules 23.1 to 23.8 | `_Generic` | no counterpart | `anytype` is Rule 8.2. |

## Sources

- The guideline list: [Perforce QAC, MISRA C:2025 enforcement](https://help.perforce.com/qac/enforcement/doc/MISRA_MC25CM.pdf).
- What changed from C:2023: [MISRA C:2025, a closer look](https://www.qt.io/software-insights/misra-c2025-a-closer-look-at-some-of-the-changes), [Perforce](https://www.perforce.com/blog/sca/misra-c-2025), [LDRA](https://ldra.com/ldra-blog/misra-c-2025-the-whys-and-wherefores-of-whats-new/).
- MISRA's own assessment for another language: [MISRA C:2025 Addendum 6, Rust applicability](https://misra.org.uk/app/uploads/2025/03/MISRA-C-2025-ADD6.pdf).
- Zig behavior: the 0.17.0 language reference shipped with the compiler, and the probes recorded in `docs/adr/002-misra-c-2025.md`.
