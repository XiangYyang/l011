// Firmware main module
// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) XiangYang, all rights reserved.
const i2c = @import("chead").import_header("i2c.h");
const gpio = @import("chead").import_header("gpio.h");

/// application entry
export fn main() noreturn {
    i2c.MX_I2C1_Init();
    gpio.MX_GPIO_Init();

    while (true) {}
}
