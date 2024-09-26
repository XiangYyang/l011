// addCSource/CInclude helper
// SPDX-License-Identifier: GPL-3.0
// Copyright (c) XiangYang, all rights reserved.

//! **addCSource helper**
//!
//! This module provides a wrap for addCSource/CInclude functions.
//! In addition, this module can record the compiler command,
//! and generate the compiled database for clangd.

const std = @import("std");

/// clangd compiled database record
pub const CompdbRecord = struct {
    const Self = @This();

    source: std.ArrayList([]u8),
    c_flags: std.ArrayList([]u8),
    include_cmd: std.ArrayList([]u8),
    alloc: std.mem.Allocator,

    /// create a compdb struct
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .source = std.ArrayList([]u8).init(alloc),
            .c_flags = std.ArrayList([]u8).init(alloc),
            .include_cmd = std.ArrayList([]u8).init(alloc),
        };
    }

    /// generate compiled database JSON and write to `compdb_file`
    pub fn generate(
        self: Self,
        compdb_file: []const u8,
        base_dir: []const u8,
        leak_cc: []const u8,
        add_flags: []const []const u8,
    ) !void {
        // compdb struct
        const CompdbItem = struct {
            file: []const u8,
            directory: []const u8,
            // file, it need be released
            command: []const u8,
        };

        // compiler command
        var cmd_str = std.ArrayList(u8).init(self.alloc);
        defer cmd_str.deinit();

        // result
        var compdb = std.ArrayList(CompdbItem).init(self.alloc);
        defer {
            for (compdb.items) |item| {
                self.alloc.free(item.command);
            }
            compdb.deinit();
        }

        // additional flags
        const additional_flags = try join_command(self.alloc, add_flags);
        defer self.alloc.free(additional_flags);

        // generate the command for each file
        for (self.source.items, self.c_flags.items) |src_file, flags| {
            cmd_str.clearRetainingCapacity();

            // compiler
            try cmd_str.appendSlice(leak_cc);
            try cmd_str.appendSlice(" ");
            try cmd_str.appendSlice(additional_flags);

            // add the including paths
            for (self.include_cmd.items) |inc_flag| {
                try cmd_str.appendSlice(inc_flag);
                try cmd_str.appendSlice(" ");
            }

            // file flags
            try cmd_str.appendSlice(flags);

            // source file
            try cmd_str.appendSlice(src_file);

            // append it to the compdb
            try compdb.append(.{
                .command = try self.alloc.dupe(u8, cmd_str.items),
                .file = src_file,
                .directory = base_dir,
            });
        }

        // generate the JSON string and save it
        var file = try std.fs.cwd().createFile(compdb_file, .{});
        defer file.close();

        // stringify json and save it
        try std.json.stringify(
            compdb.items,
            std.json.StringifyOptions{
                .whitespace = .indent_2,
            },
            file.writer(),
        );

        _ = try file.write("\n");
    }

    /// deinit the struct
    pub fn deinit(self: Self) void {
        for (self.source.items) |src| {
            self.alloc.free(src);
        }
        for (self.c_flags.items) |flag| {
            self.alloc.free(flag);
        }
        for (self.include_cmd.items) |include| {
            self.alloc.free(include);
        }
        self.source.deinit();
        self.c_flags.deinit();
        self.include_cmd.deinit();
    }
};

/// c including/source path
pub const CodePath = union(enum) {
    include: struct {
        base_dir: []const u8,
        sub_dir: []const u8,
    },
    source: struct {
        base_dir: []const u8,
        sub_dir: []const u8,
        flags: ?[]const []const u8,
    },
};

/// CMake state
pub const CMake = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    b: *std.Build,
    elf: *std.Build.Step.Compile,
    compdb: CompdbRecord,

    /// create a compdb struct
    pub fn init(
        alloc: std.mem.Allocator,
        b: *std.Build,
        elf: *std.Build.Step.Compile,
    ) Self {
        return .{
            .alloc = alloc,
            .b = b,
            .elf = elf,
            .compdb = CompdbRecord.init(alloc),
        };
    }

    /// deinit the struct
    pub fn deinit(self: Self) void {
        self.compdb.deinit();
    }

    /// add files
    pub fn add_files(
        self: *Self,
        file_dir: []const CodePath,
    ) !void {
        for (file_dir) |file_item| {
            try switch (file_item) {
                .include => |info| self.add_c_includes(
                    info.base_dir,
                    info.sub_dir,
                ),
                .source => |info| self.add_c_sources(
                    if (info.flags) |flags| flags else &.{},
                    info.base_dir,
                    info.sub_dir,
                ),
            };
        }
    }

    /// generate compdb
    pub fn generate_compdb(self: Self, base_dir: []const u8, leak_cmd: []const u8, leak_args: []const []const u8) !void {
        return self.compdb.generate("compile_commands.json", base_dir, leak_cmd, leak_args);
    }

    /// add the C including path to `elf`
    fn add_c_includes(self: *Self, base_dir: []const u8, c_include: []const u8) !void {
        const inc_path = try path_norm_join(self.alloc, &.{ base_dir, c_include });
        defer self.alloc.free(inc_path);

        // add it to the compdb records
        var command = std.ArrayList(u8).init(self.alloc);
        defer command.deinit();

        try command.appendSlice("-I");
        try command.appendSlice(inc_path);

        try self.compdb.include_cmd.append(try self.alloc.dupe(u8, command.items));

        // add the including path
        self.elf.addIncludePath(self.b.path(inc_path));
    }

    /// add the C source files to `elf`
    fn add_c_sources(self: *Self, c_flags: []const []const u8, base_dir: []const u8, c_source_filters: []const u8) !void {
        const src_path = try path_norm_join(self.alloc, &.{ base_dir, c_source_filters });
        defer self.alloc.free(src_path);

        var iter_dir = try std.fs.cwd().openDir(src_path, .{ .iterate = true });
        defer iter_dir.close();

        var walker = try iter_dir.walk(self.alloc);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }

            if (!std.mem.eql(u8, std.fs.path.extension(entry.path), ".c")) {
                continue;
            }

            const file_path = try path_norm_join(self.alloc, &.{ src_path, entry.path });
            defer self.alloc.free(file_path);

            // Add it to thecompdb records
            try self.compdb.c_flags.append(try join_command(self.alloc, c_flags));
            try self.compdb.source.append(try self.alloc.dupe(u8, file_path));

            // add sources
            self.elf.addCSourceFile(.{
                .file = self.b.path(file_path),
                .flags = c_flags,
            });
        }
    }
};

/// join the path with normalizing, free the return value outside
fn path_norm_join(alloc: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    const path = try std.fs.path.join(alloc, paths);
    return normalize_path_in(path);
}

/// normalize path, free the return value outside
///
///  * on unix, `src\path/file` → `src/path/file`
///  * on windows, `src\path/file` → `src\path\file`
fn normalize_path(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_mem = try alloc.dupe(u8, path);
    return normalize_path_in(path_mem);
}

/// normalize path and return the modified self
///
///  * on unix, `src\path/file` → `src/path/file`
///  * on windows, `src\path/file` → `src\path\file`
fn normalize_path_in(path: []u8) []u8 {
    for (0..path.len) |i| {
        if (path[i] == '/' and path[i] != std.fs.path.sep) {
            // windows case
            path[i] = '\\';
        } else if (path[i] == '\\' and path[i] != std.fs.path.sep) {
            // unix case
            path[i] = '/';
        }
    }
    return path;
}

/// join the command, release the return value outside
fn join_command(alloc: std.mem.Allocator, cmd_args: []const []const u8) ![]u8 {
    var command = std.ArrayList(u8).init(alloc);
    defer command.deinit();

    for (cmd_args) |arg| {
        try command.appendSlice(arg);
        try command.append(' ');
    }

    const result = try alloc.dupe(u8, command.items);
    return result;
}
