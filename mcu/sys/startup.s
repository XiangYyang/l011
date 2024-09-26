// Startup file for STM32L0x (LLVM)
// SPDX-License-Identifier: GPL-3.0
// Copyright (c) XiangYang, all rights reserved.
.syntax unified
.cpu cortex-m0plus
.fpu softvfp
.thumb

// the following symbols were defined in linker script `link.ld`
// start address for the initialization values of the .data section
.word _sidata

// start address for the .data section
.word _sdata

// end address for the .data section
.word _edata

// start address for the .bss section
.word _sbss

// end address for the .bss section
.word _ebss

// stack top
.word _estack

// stack size
.word _Min_Stack_Size

// magic number for checking overflow
// BITS    VALUE       DESCRIPTION
// ------  ----------  --------------
// [31:0]  0x696d6eca  'Canmi'
.section    .rodata.magic_number
.type       empty_str, %object
magic_number:
    .word   0x696d6eca

// reset handler (boot)
.section .text.Reset_Handler
.weak Reset_Handler
.type Reset_Handler, %function
Reset_Handler:
    ldr     r0, =_estack
    // set stack pointer
    mov     sp, r0

    // load the magic number to `r5`
    ldr     r5, =magic_number

    // fill magic number to the stack bottom
    ldr     r2, =_Min_Stack_Size
    subs    r0, r2
    str     r5, [r0]

    // Call the clock system initialization function.
    bl      SystemInit

    // Check if boot space corresponds to system memory
    ldr     r0, =0x00000004
    ldr     r1, [r0]
    lsrs    r1, r1, #24
    ldr     r2,=0x1f
    cmp     r1, r2
    bne     startup

    // SYSCFG clock enable
    ldr     r0, =0x40021034
    ldr     r1, =0x00000001
    str     r1, [r0]

    // Set CFGR1 register with flash memory remap at address 0
    ldr     r0, =0x40010000
    ldr     r1, =0x00000000
    str     r1, [r0]

startup:
    // Copy the data segment initializers from flash to SRAM
    ldr     r0, =_sdata
    ldr     r1, =_edata
    ldr     r2, =_sidata
    subs    r3, r1, r0
    subs    r3, r3, #4
    bmi     fill_bss

copy_data:
    ldr     r4, [r2, r3]
    str     r4, [r0, r3]
    subs    r3, r3, #4
    bpl     copy_data

fill_bss:
    // Zero fill the bss segment.
    ldr     r2, =_sbss
    ldr     r4, =_ebss
    movs    r3, #0
    b       fill_zero_bss

fill_zero_bss_inner:
    str     r3, [r2]
    adds    r2, r2, #4

fill_zero_bss:
    cmp     r2, r4
    bcc     fill_zero_bss_inner

    // fill magic number after `.bss`
    subs    r4, #8
    str     r5, [r4]

invoke_app:
    // call setup function
    bl      setup

    // call main function
    movs    r0, #0
    bl      main

infinite_loop:
    b       infinite_loop

// irq_handler table
.section    .isr_vector,"a",%progbits
.type       g_pfnVectors, %object
.size       g_pfnVectors, .-g_pfnVectors
g_pfnVectors:
    .word   _estack
    .word   Reset_Handler
    .word   NMI_Handler
    .word   HardFault_Handler
    .word   0
    .word   0
    .word   0
    .word   0
    .word   0
    .word   0
    .word   0
    .word   SVC_Handler
    .word   0
    .word   0
    .word   PendSV_Handler
    .word   SysTick_Handler
    .word   WWDG_IRQHandler             /* Window WatchDog              */
    .word   PVD_IRQHandler              /* PVD through EXTI Line detection */
    .word   RTC_IRQHandler              /* RTC through the EXTI line    */
    .word   FLASH_IRQHandler            /* FLASH                        */
    .word   RCC_IRQHandler              /* RCC                          */
    .word   EXTI0_1_IRQHandler          /* EXTI Line 0 and 1            */
    .word   EXTI2_3_IRQHandler          /* EXTI Line 2 and 3            */
    .word   EXTI4_15_IRQHandler         /* EXTI Line 4 to 15            */
    .word   0                           /* Reserved                     */
    .word   DMA1_Channel1_IRQHandler    /* DMA1 Channel 1               */
    .word   DMA1_Channel2_3_IRQHandler  /* DMA1 Channel 2 and Channel 3 */
    .word   DMA1_Channel4_5_IRQHandler  /* DMA1 Channel 4 and Channel 5 */
    .word   ADC1_COMP_IRQHandler        /* ADC1, COMP1 and COMP2        */
    .word   LPTIM1_IRQHandler           /* LPTIM1                       */
    .word   0                           /* Reserved                     */
    .word   TIM2_IRQHandler             /* TIM2                         */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */
    .word   TIM21_IRQHandler            /* TIM21                        */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */
    .word   I2C1_IRQHandler             /* I2C1                         */
    .word   0                           /* Reserved                     */
    .word   SPI1_IRQHandler             /* SPI1                         */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */
    .word   USART2_IRQHandler           /* USART2                       */
    .word   LPUART1_IRQHandler          /* LPUART1                      */
    .word   0                           /* Reserved                     */
    .word   0                           /* Reserved                     */

// set weak symbol for default handler
// it's ensure for each unexception handler to the infinite_loop.
.weak       NMI_Handler
.thumb_set  NMI_Handler, infinite_loop

.weak       HardFault_Handler
.thumb_set  HardFault_Handler, infinite_loop

.weak       SVC_Handler
.thumb_set  SVC_Handler, infinite_loop

.weak       PendSV_Handler
.thumb_set  PendSV_Handler, infinite_loop

.weak       SysTick_Handler
.thumb_set  SysTick_Handler, infinite_loop

.weak       WWDG_IRQHandler
.thumb_set  WWDG_IRQHandler, infinite_loop

.weak       PVD_IRQHandler
.thumb_set  PVD_IRQHandler, infinite_loop

.weak       RTC_IRQHandler
.thumb_set  RTC_IRQHandler, infinite_loop

.weak       FLASH_IRQHandler
.thumb_set  FLASH_IRQHandler, infinite_loop

.weak       RCC_IRQHandler
.thumb_set  RCC_IRQHandler, infinite_loop

.weak       EXTI0_1_IRQHandler
.thumb_set  EXTI0_1_IRQHandler, infinite_loop

.weak       EXTI2_3_IRQHandler
.thumb_set  EXTI2_3_IRQHandler, infinite_loop

.weak       EXTI4_15_IRQHandler
.thumb_set  EXTI4_15_IRQHandler, infinite_loop

.weak       DMA1_Channel1_IRQHandler
.thumb_set  DMA1_Channel1_IRQHandler, infinite_loop

.weak       DMA1_Channel2_3_IRQHandler
.thumb_set  DMA1_Channel2_3_IRQHandler, infinite_loop

.weak       DMA1_Channel4_5_IRQHandler
.thumb_set  DMA1_Channel4_5_IRQHandler, infinite_loop

.weak       ADC1_COMP_IRQHandler
.thumb_set  ADC1_COMP_IRQHandler, infinite_loop

.weak       LPTIM1_IRQHandler
.thumb_set  LPTIM1_IRQHandler, infinite_loop

.weak       TIM2_IRQHandler
.thumb_set  TIM2_IRQHandler, infinite_loop

.weak       TIM21_IRQHandler
.thumb_set  TIM21_IRQHandler, infinite_loop

.weak       I2C1_IRQHandler
.thumb_set  I2C1_IRQHandler, infinite_loop

.weak       SPI1_IRQHandler
.thumb_set  SPI1_IRQHandler, infinite_loop

.weak       USART2_IRQHandler
.thumb_set  USART2_IRQHandler, infinite_loop

.weak       LPUART1_IRQHandler
.thumb_set  LPUART1_IRQHandler, infinite_loop
