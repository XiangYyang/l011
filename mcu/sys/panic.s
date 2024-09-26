// Panic handler for STM32L0x (LLVM)
// SPDX-License-Identifier: GPL-3.0
// Copyright (c) XiangYang, all rights reserved.
.syntax unified
.cpu cortex-m0plus
.fpu softvfp
.thumb

// string: empty
.section    .rodata.empty_str
.type       empty_str, %object
empty_str:
    .word   0x0

// string: hardfault
.section    .rodata.hardfault_str
.type       hardfault_str, %object
hardfault_str:
    .ascii  "HardFault\0"

// hardfault handler
.section    .text.HardFault_Handler
.global     HardFault_Handler
.type       HardFault_Handler, %function
HardFault_Handler:
    mov     r0, sp
    cpsid   i
    // save pc from the hardware-saved context
    // context: r0          <--- sp
    //          r1
    //          r2
    //          r3
    //          r12
    //          lr
    //          pc          <--- sp + 24
    //          xPSR
    ldr     r3, [r0, #24]

    // call panic_impl function in `system.c`
    // * arg0   file path       str: ""
    // * arg1   line number     int: 0
    // * arg2   message         reg: r2
    // * arg3   pc              reg: r3
    // * arg4   0               stack space (+ 4)
    ldr     r2, =hardfault_str

failed_handler:
    push    {r4, lr}

    // rev stack space for painc_impl (arg4)
    sub	    sp, #4

    // set arg0 and arg1
    ldr     r0, =empty_str
    movs    r1, #0
    str	    r1, [sp, #0]
    bl      panic_impl

    // we don't need the pop instruction
    // because the `panic_impl` function never returns.
