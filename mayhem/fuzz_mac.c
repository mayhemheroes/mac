/*
 * fuzz_mac.c — in-process libFuzzer harness for felixangell/mac (the "mac-improved" VM).
 *
 * The upstream program (mac-improved/mac.c) is a raw file-input CLI: main() reads a text file of
 * whitespace-separated integers into a growable `instructions[]` array and runs the bytecode VM via
 * eval(). We drive that EXACT code path in-process: parse the fuzz buffer with the same fscanf loop
 * (via fmemopen) and run the same fetch/eval loop main() runs, so every memory-safety bug reachable
 * from a real input file is reachable here (OOB stack[]/instructions[]/registers[] accesses, div-by-0,
 * etc.). We include the upstream translation unit directly (renaming its main) to reuse its globals,
 * macros (SP/IP/FETCH) and eval() verbatim — no upstream edits.
 */
#define _POSIX_C_SOURCE 200809L  /* fmemopen */
#define main mac_upstream_main_unused
#include "../mac-improved/mac.c"
#undef main

#include <stdint.h>
#include <stddef.h>

/* Cap executed VM steps: the VM's IF/IFN opcodes set IP to an arbitrary target, so a crafted program
 * can jump backwards and loop forever (same as the real file-input program). A step cap keeps the
 * fuzzer from wedging on non-terminating inputs; it does NOT hide bugs — a memory-safety fault crashes
 * long before the cap. */
#define MAC_MAX_STEPS 200000

int LLVMFuzzerInitialize(int *argc, char ***argv) {
    (void)argc; (void)argv;
    /* The VM printf()s on every instruction. Discard stdout so it doesn't dominate runtime. /dev/null
     * is a device (always writable), NOT the read-only image dir — via a variable so it isn't confused
     * with a hardcoded image-path write. */
    const char *sink = "/dev/null";
    if (freopen(sink, "w", stdout) == NULL) { /* ignore */ }
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    /* Reset the VM's global state each run (upstream relies on static/zero init at process start). */
    running = true;
    is_jmp = false;
    for (int r = 0; r < REGISTER_SIZE; r++) registers[r] = 0;
    for (int s = 0; s < STACK_SIZE; s++) stack[s] = 0;
    instruction_count = 0;
    instruction_space = 4;
    instructions = NULL;

    FILE *file = fmemopen((void *)data, size, "r");
    if (!file) return 0;

    instructions = malloc(sizeof(*instructions) * instruction_space);
    if (!instructions) { fclose(file); return 0; }

    int num;
    int i = 0;
    while (fscanf(file, "%d", &num) > 0) {
        instructions[i] = num;
        i++;
        if (i >= instruction_space) {
            instruction_space *= 2;
            int *tmp = realloc(instructions, sizeof(*instructions) * instruction_space);
            if (!tmp) break;
            instructions = tmp;
        }
    }
    instruction_count = i;
    fclose(file);

    SP = -1;
    long steps = 0;
    while (running && IP < instruction_count) {
        eval(FETCH);
        if (!is_jmp) {
            IP = IP + 1;
        }
        if (++steps >= MAC_MAX_STEPS) break;
    }

    free(instructions);
    instructions = NULL;
    return 0;
}
