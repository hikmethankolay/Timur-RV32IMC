/* Timur RV32IMC memory layout (Phase 12).
 *
 *   ROM 0x0000_0000, 64 KB: code, constants and the initial values of .data.
 *       Instructions are fetched only through the ROM's fetch port, so code
 *       never runs from RAM; data loads read the ROM through its AHB port.
 *   RAM 0x2000_0000, 64 KB: .data, .bss, then the heap (growing up to
 *       _heap_end) and the stack (__stack_size bytes below _stack_top,
 *       growing down).
 *
 * Symbols used by crt0.S and syscalls.c:
 *   _data_load            load address of .data in ROM
 *   _data_start/_data_end run address range of .data in RAM
 *   _bss_start/_bss_end   range crt0 clears
 *   _end                  first free RAM byte: the start of the heap
 *   _heap_end             end of the heap: the lowest address of the stack region
 *   _stack_top            initial stack pointer: the end of RAM
 *   __global_pointer$     the small data (.sdata, .sbss) plus 0x800, loaded into gp
 *
 * Every range crt0 copies or clears starts and ends on a 4-byte boundary.
 * Override the stack size with -Wl,--defsym=__stack_size=<bytes>. */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rw) : ORIGIN = 0x20000000, LENGTH = 64K
}

__stack_size = DEFINED(__stack_size) ? __stack_size : 8K;

/* the ELF segments: ROM contents (read, execute) and RAM (read, write) */
PHDRS
{
    rom PT_LOAD FLAGS(5);
    ram PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))            /* _start: the reset address */
        *(.text .text.*)
        . = ALIGN(4);
    } > ROM :rom

    .rodata :
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > ROM :rom

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE_HIDDEN(__init_array_end = .);
        . = ALIGN(4);
    } > ROM :rom

    .data : ALIGN(4)
    {
        _data_start = .;
        *(.data .data.*)
        . = ALIGN(4);
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM AT > ROM :ram
    _data_load = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4)
    {
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM :ram

    _end = .;
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    _heap_end = _stack_top - __stack_size;

    /* unwind tables: not used by C programs */
    /DISCARD/ : { *(.eh_frame .eh_frame_hdr) }
}

ASSERT(_data_load + SIZEOF(.data) <= ORIGIN(ROM) + LENGTH(ROM), "the ROM image does not fit in 64 KB")
ASSERT((_data_load & 3) == 0, ".data is not word-aligned in ROM")
ASSERT(_end <= _heap_end, "RAM overflow: .data and .bss leave no room for the stack")
