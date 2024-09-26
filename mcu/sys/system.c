// Base support
// SPDX-License-Identifier: GPL-3.0
// Copyright (c) XiangYang, all rights reserved.
#include "system.h"
#include <stddef.h>
#include "lptim.h"
#include "stm32l011xx.h"
#include "stm32l0xx_ll_bus.h"
#include "cmsis_compiler.h"

/**
 * @brief System tiem base timer
 *
 */
#define TICK_LPTIM LPTIM1

// @main.c
extern void SystemClock_Config(void);

// private functions
static void wait_sync_32k(void);

/**
 * @brief application setup
 *
 * @note return value was ignored currently
 *
 */
int setup(void)
{
    // Reset of all peripherals
    // Initializes the Flash interface and the Systick.
    LL_APB2_GRP1_EnableClock(LL_APB2_GRP1_PERIPH_SYSCFG);
    LL_APB1_GRP1_EnableClock(LL_APB1_GRP1_PERIPH_PWR);

    // SysTick_IRQn interrupt configuration
    NVIC_SetPriority(SysTick_IRQn, 3);

    // Configure the system clock
    SystemClock_Config();

    // setup the LPTIM as system time base
    MX_LPTIM1_Init();
    LL_LPTIM_Enable(TICK_LPTIM);

    // wait the clock synchronization for LPTIM
    wait_sync_32k();

    // set ARR value, start the counter
    LL_LPTIM_SetAutoReload(TICK_LPTIM, 0xffff);
    LL_LPTIM_StartCounter(TICK_LPTIM, LL_LPTIM_OPERATING_MODE_CONTINUOUS);

    return 0;
}

/**
 * @brief panic handler
 *
 */
void panic_impl(
    const char* file, int line, const char* msg, intptr_t pc, intptr_t sr
)
{
    __disable_irq();
    (void)pc;
    (void)sr;

    while (1) {
    }
}

/**
 * @brief wait for synchronization between 32k clock domain and APB(=AHB.clk)
 * clock domain
 *
 */
static void wait_sync_32k(void)
{
    // wait time = (SystemClockFreq / 32k)
    // APB.freq = AHB.freq
    // 32kHz ≈ 32768Hz = shift-right 15bits
    uint32_t wait_cycle = SystemCoreClock >> 15;

    // because we have two stupid instructions at least
    // so the following will use at least 2 AHB clock cycles
    // even if the `wait_cycle` is zero
    __ASM volatile(".syntax unified         \n"
                   "    movs     r0, %0     \n"
                   "loop:                   \n"
                   "    subs     r0, #1     \n"
                   "    bpl      loop       \n"
                   :
                   : "r"(wait_cycle));
}
