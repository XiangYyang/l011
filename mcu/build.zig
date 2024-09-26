// Firmware build script
// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) XiangYang, all rights reserved.
const fs = std.fs;
const std = @import("std");
const cmake = @import("./cmake.zig");

pub fn build(b: *std.Build) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();

    const alloc = arena_state.allocator();

    const optimize = b.standardOptimizeOption(.{});

    const target = .{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
        .abi = .eabi,
    };

    const target_elf_file = "firmware.elf";
    const target_hex_file = "firmware.hex";
    const target_bin_file = "firmware.bin";
    const target_dump_file = "firmware.s";

    // Device series: stm32l0xx
    const stm32_device_series = "STM32L0xx";

    // CMSIS base dir
    const cmsis_base = "Drivers/CMSIS";

    // CubeMX codegen output base dir
    const cubemx_out_base = "Core";

    // reslove target
    const resolved_target = b.resolveTargetQuery(target);

    // zig target
    // unwind_table     : false
    const elf = b.addExecutable(.{
        .name = target_elf_file,
        .root_source_file = b.path("src/main.zig"),
        .target = resolved_target,
        .optimize = optimize,
        .unwind_tables = false,
    });

    // create `sys` module
    const sys_mod = b.createModule(.{
        .root_source_file = b.path("sys/system.zig"),
    });
    elf.root_module.addImport("sys", sys_mod);

    // add flags:
    // -flto            : true
    // --gc-sections    : true
    // --data-sections  : true
    // --func-sections  : true
    elf.want_lto = true;
    elf.link_gc_sections = true;
    elf.link_data_sections = true;
    elf.link_function_sections = true;

    // c compiler flags
    const c_flags: []const []const u8 = &.{
        "--std=c2x",
        "-DSTM32L011xx",
        "-DUSE_FULL_LL_DRIVER",
        "-DUSE_FULL_ASSERT=1U",
        "-DHSE_VALUE=8000000",
        "-DHSE_STARTUP_TIMEOUT=100",
        "-DLSE_STARTUP_TIMEOUT=5000",
        "-DLSE_VALUE=32768",
        "-DMSI_VALUE=2097000",
        "-DHSI_VALUE=16000000",
        "-DLSI_VALUE=37000",
        "-DVDD_VALUE=3300",
        "-DPREFETCH_ENABLE=0 ",
        "-DINSTRUCTION_CACHE_ENABLE=1",
        "-DDATA_CACHE_ENABLE=1",
    };

    // add startup-file
    elf.addAssemblyFile(b.path("sys/startup.s"));

    // add panic handler
    elf.addAssemblyFile(b.path("sys/panic.s"));

    // set ldscript
    const ldscript_file = "sys/link.x";
    elf.setLinkerScriptPath(b.path(ldscript_file));

    // cmake tool
    var make = cmake.CMake.init(alloc, b, elf);
    defer make.deinit();

    // STM32 BSP
    const driver_base = try std.fmt.allocPrint(
        alloc,
        "Drivers/{s}_HAL_Driver",
        .{stm32_device_series},
    );
    defer alloc.free(driver_base);

    // CMSIS device base dir
    const cmsis_device_base = try std.fmt.allocPrint(
        alloc,
        "{s}/Device/ST/{s}",
        .{ cmsis_base, stm32_device_series },
    );
    defer alloc.free(cmsis_device_base);

    // add including path
    try make.add_files(&.{
        .{ .include = .{ .base_dir = cmsis_base, .sub_dir = "Include" } },
        .{ .include = .{ .base_dir = driver_base, .sub_dir = "Inc" } },
        .{ .include = .{ .base_dir = cubemx_out_base, .sub_dir = "Inc" } },
        .{ .include = .{ .base_dir = cmsis_device_base, .sub_dir = "Include" } },
    });

    // add source file.
    try make.add_files(&.{
        .{ .source = .{ .base_dir = ".", .sub_dir = "sys", .flags = c_flags } },
        .{ .source = .{ .base_dir = driver_base, .sub_dir = "Src", .flags = c_flags } },
        .{ .source = .{ .base_dir = cubemx_out_base, .sub_dir = "Src", .flags = c_flags } },
    });

    // set the entry point symbol
    // I don't know why it's set in link script and I must set it again.
    // So I removed `ENTRY(Reset_Handler)` in link.x  QwQ
    elf.entry = .{ .symbol_name = "Reset_Handler" };

    // elf step qwq
    const elf_target = b.addInstallArtifact(elf, .{});

    // generate the hex file
    const copy_hex = add_objcopy(
        b,
        elf,
        .hex,
        target_hex_file,
        "hex",
        "Generate the HEX file",
    );

    // generate the bin file
    const copy_bin = add_objcopy(
        b,
        elf,
        .bin,
        target_bin_file,
        "bin",
        "Generate the binary file",
    );

    // objdump
    const objdump = add_objdump(
        b,
        elf,
        target_dump_file,
        "dump",
        "Dump the output elf file",
    );

    // run the objsize
    const size_cmd = add_objsize(b, elf);

    // genreate the compdb for clangd?
    // The `compile_commands.json` will be written to the root directory (equal get_base_dir())
    // Maybe we have a better way to write it to the root directory
    const gen_compdb = b.option(bool, "compdb", "Generate `compile_commands.json`") orelse false;
    if (gen_compdb) {
        try make.generate_compdb(
            get_base_dir(),
            "arm-none-eabi-gcc",
            &.{
                "-c",
                "-mcpu=cortex-m0plus",
            },
        );

        std.debug.print("Generate `compile_commands.json` completed\n", .{});
    }

    // default: build elf, build hex, build bin, objsize
    b.default_step.dependOn(&copy_hex.step);
    b.default_step.dependOn(&copy_bin.step);
    b.default_step.dependOn(&size_cmd.step);
    b.default_step.dependOn(&objdump.step);
    b.default_step.dependOn(&elf_target.step);
}

/// add the objcopy easily
fn add_objcopy(
    b: *std.Build,
    elf: *std.Build.Step.Compile,
    fmt: std.Build.Step.ObjCopy.RawFormat,
    output: []const u8,
    step_name: []const u8,
    step_descript: []const u8,
) *std.Build.Step.InstallFile {
    // In objcopy, the `llvm/llvm-project/main/llvm/lib/ObjCopy/ELF/ELFObject.cpp#L2639`
    // indicates the content to be copied is maxium(LMA) to minium(LMA) of the PT_LOAD program header,
    // and the minium(LMA) is beginning (offset=0)
    // To avoid copying the `.bss` (in PT_LOAD program header) section,
    // we copy the following sections ONLY.
    const copied_sections: []const []const u8 = &.{
        ".isr_vector",
        ".version",
        ".text",
        ".rodata",
        ".ARM",
        ".data",
    };

    const copy_hex_cmd = b.addSystemCommand(&.{ "llvm-objcopy", "-O" });

    if (fmt == .hex) {
        copy_hex_cmd.addArg("ihex");
    } else if (fmt == .bin) {
        copy_hex_cmd.addArg("binary");
    } else {
        fatal("[FATAL] format {} is unimplemented in objcopy", .{fmt});
    }

    for (copied_sections) |section| {
        copy_hex_cmd.addArg("-j");
        copy_hex_cmd.addArg(section);
    }

    copy_hex_cmd.addFileArg(elf.getEmittedBin());
    const copy_hex_out = copy_hex_cmd.addOutputFileArg(output);

    // copy it to the install directory
    const copy_hex = b.addInstallBinFile(copy_hex_out, output);

    const copy_hex_step = b.step(step_name, step_descript);
    copy_hex_step.dependOn(&copy_hex.step);

    return copy_hex;
}

/// add the objcopy easily
fn add_objdump(
    b: *std.Build,
    elf: *std.Build.Step.Compile,
    output: []const u8,
    step_name: []const u8,
    step_descript: []const u8,
) *std.Build.Step.InstallFile {
    const dump_cmd = b.addSystemCommand(&.{ "llvm-objdump", "-d" });
    dump_cmd.addFileArg(elf.getEmittedBin());

    const dump_cmd_output = dump_cmd.captureStdOut();
    const dump_cmd_step = b.addInstallFile(dump_cmd_output, output);

    const dump_step = b.step(step_name, step_descript);
    dump_step.dependOn(&dump_cmd_step.step);

    return dump_cmd_step;
}

/// add the `objsize`
fn add_objsize(
    b: *std.Build,
    elf: *std.Build.Step.Compile,
) *std.Build.Step.Run {
    const size_cmd = b.addSystemCommand(&.{
        "llvm-size",
    });
    size_cmd.addFileArg(elf.getEmittedBin());

    const size_step = b.step("size", "Display the section size info");
    size_step.dependOn(&size_cmd.step);

    return size_cmd;
}

/// get the root path
fn get_base_dir() []const u8 {
    const src_file = @src().file;
    if (std.fs.path.dirname(src_file)) |file_path| {
        return file_path;
    } else {
        return ".";
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
