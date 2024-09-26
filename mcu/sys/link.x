/* linker script for STM32L011 (LLVM)           */
/* SPDX-License-Identifier: BSD-3-Clause-Clear  */
/* Copyright (c) XiangYang, all rights reserved.*/
/* The FLASH layout:                            */
/* 0x08000000       .isr_vector                 */
/*                  .version                    */
/*                  .text                       */
/*                  .rodata                     */
/*                  .data                       */
/*                  [reserved 1 page]           */
/* The RAM layout:                              */
/* 0x20000000       .data                       */
/*                  .bss                        */
/*                  [magic number]              */
/*                  [newlib heap]               */
/*                  [magic number]              */
/*                  [privileged tasks stack]    */
MEMORY
{
    RAM (xrw)   : ORIGIN = 0x20000000, LENGTH = 2K
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 16K
}

/* stack_top = end of RAM */
_estack = ORIGIN(RAM) + LENGTH(RAM);

/* privileged tasks stack size (1kB) */
_Min_Stack_Size = 0x400;

SECTIONS
{
    .isr_vector :
    {
        KEEP(*(.isr_vector))    /* interrupt vector table */
        . = ALIGN(4);
    } >FLASH

    .version :
    {
        KEEP(*(.version))       /* version info */
        . = ALIGN(4);
    } >FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text)                /* .text sections (code) */
        *(.text*)               /* .text* sections (code) */
        *(.glue_7)              /* glue arm to thumb code */
        *(.glue_7t)             /* glue thumb to arm code */
        *(.eh_frame)

        KEEP (*(.init))
        KEEP (*(.fini))

        . = ALIGN(4);
        _etext = .;             /* define a global symbols at end of code */
    } >FLASH

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } >FLASH

    .ARM.extab :
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } >FLASH

    .ARM :
    {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } >FLASH

    .preinit_array :
    {
        PROVIDE_HIDDEN (__preinit_array_start = .);

        KEEP (*(.preinit_array*))

        PROVIDE_HIDDEN (__preinit_array_end = .);
    } >FLASH

    .init_array :
    {
        PROVIDE_HIDDEN (__init_array_start = .);

        KEEP (*(SORT(.init_array.*)))
        KEEP (*(.init_array*))

        PROVIDE_HIDDEN (__init_array_end = .);
    } >FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN (__fini_array_start = .);

        KEEP (*(SORT(.fini_array.*)))
        KEEP (*(.fini_array*))

        PROVIDE_HIDDEN (__fini_array_end = .);
    } >FLASH

    _sidata = LOADADDR(.data);  /* Flash address for initialized data */

    .data : 
    {
        . = ALIGN(4);
        _sdata = .;             /* define a global symbol at data start */
        *(.data)
        *(.data*)

        . = ALIGN(4);
        _edata = .;             /* define a global symbol at data end   */
    } >RAM AT> FLASH

    .bss :
    {
        . = ALIGN(4);
        _sbss = .;              /* define a global symbol at bss start */
        __bss_start__ = _sbss;

        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);

        _pvd_data_start = .;

        *(.pvd_data)            /* vars that need to be saved on PVD */
        *(.pvd_data*)
        . = ALIGN(4);

        _pvd_data_end = .;

        . = . + 8;              /* reserved for fill magic number    */

        _ebss = .;              /* define a global symbol at bss end */
        __bss_end__ = _ebss;
    } >RAM

    PROVIDE( _end = . );
    PROVIDE( end = . );

    /DISCARD/ :                 /* Remove information from the standard libraries */
    {
        libc.a ( * )
        libm.a ( * )
        libgcc.a ( * )
    }

    .ARM.attributes 0 :
    {
        *(.ARM.attributes)
    }
}
