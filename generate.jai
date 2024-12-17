AT_COMPILE_TIME :: true;

SOURCE_PATH   :: "tracy";
LIB_BASE_NAME :: "TracyClient";

#if AT_COMPILE_TIME {
    #run,stallable {
        set_build_options_dc(.{do_output=false});
        options := get_build_options();
        args := options.compile_time_command_line;
        if !generate_bindings(args, options.minimum_os_version) {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    #import "System";

    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        if !generate_bindings(get_command_line_arguments(), #run get_build_options().minimum_os_version) {
            exit(1);
        }
    }
}

generate_bindings :: (args: [] string, minimum_os_version: type_of(Build_Options.minimum_os_version)) -> bool {
    compile        := !array_find(args, "-no_compile");
    compile_debug  := array_find(args, "-debug");

    lib_directory: string;
    #if OS == {
        case .WINDOWS;
            lib_directory = "windows";
        case .LINUX;
            lib_directory = "linux";
        case .MACOS;
            lib_directory = "macos";
        case;
            assert(false);
    }

    if compile {
        source_file := tprint("%/public/TracyClient.cpp", SOURCE_PATH);

        #if OS == .WINDOWS {
            extra_args := string.["/DTRACY_ENABLE", "/DTRACY_EXPORTS"];
        } else {
            extra_args := string.["-DTRACY_ENABLE", "-DTRACY_EXPORTS", "-std=c++11", "-Wno-deprecated-declarations"];
        }

        make_directory_if_it_does_not_exist(lib_directory, recursive = true);
        lib_path := tprint("%/%", lib_directory, LIB_BASE_NAME);
        success := true;
        #if OS == .MACOS {
            lib_path_x64   := tprint("%_x64", lib_path);
            lib_path_arm64 := tprint("%_arm64", lib_path);
            macos_x64_version_arg   := "-mmacos-version-min=10.13"; // Our current x64 min version
            macos_arm64_version_arg := "-mmacos-version-min=11.0";  // Earliest version that supports arm64
            // x64 variant
            {
                args: [..] string;
                array_add(*args, ..extra_args);
                array_add(*args, "-arch", "x86_64", macos_x64_version_arg);
                success &&= build_cpp_dynamic_lib(lib_path_x64,   source_file, extra = args, debug = compile_debug);
                success &&= build_cpp_static_lib( lib_path_x64,   source_file, extra = args, debug = compile_debug);
            }
            // arm64 variant
            {
                args: [..] string;
                array_add(*args, ..extra_args);
                array_add(*args, "-arch", "arm64", macos_arm64_version_arg);
                success &&= build_cpp_dynamic_lib(lib_path_arm64, source_file, extra = args, debug = compile_debug);
                success &&= build_cpp_static_lib( lib_path_arm64, source_file, extra = args, debug = compile_debug);
            }
            // create universal binaries
            run_result := run_command("lipo", "-create", tprint("%.dylib", lib_path_x64), tprint("%.dylib", lib_path_arm64), "-output", tprint("%.dylib", lib_path));
            success &&= (run_result.exit_code == 0);
            run_result  = run_command("lipo", "-create", tprint("%.a",     lib_path_x64), tprint("%.a",     lib_path_arm64), "-output", tprint("%.a",     lib_path));
            success &&= (run_result.exit_code == 0);
        } else {
            success &&= build_cpp_dynamic_lib(lib_path, source_file, extra = extra_args, debug = compile_debug);
            success &&= build_cpp_static_lib(lib_path,  source_file, extra = extra_args, debug = compile_debug);
        }

        if !success     return false;
    }

    options: Generate_Bindings_Options;
    {
        using options;

        array_add(*libpaths, lib_directory);
        array_add(*libnames, LIB_BASE_NAME);
        array_add(*source_files, tprint("%/public/tracy/TracyC.h", SOURCE_PATH));
        array_add(*extra_clang_arguments, "-D", "TRACY_ENABLE");

        generate_library_declarations = false;
        footer = tprint(FOOTER_TEMPLATE, to_lower_copy_new(LIB_BASE_NAME), LIB_BASE_NAME);

        log_stripped_declarations = false;
        generate_compile_time_struct_checks = false;

        visitor = tracy_visitor;
    }

    output_filename := "bindings.jai";
    return generate_bindings(options, output_filename);
}

DECLARATIONS_TO_OMIT :: string.[
    // We have our own version of this in module.jai
    "TracyCFrameMark",
    // Remove some cruft
    "TRACY_ENABLE",
    "TRACY_HAS_CALLSTACK",
    "TracyCIsStarted",
];


tracy_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    if !parent_decl {
        if array_find(DECLARATIONS_TO_OMIT, decl.name) {
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
            return .STOP;
        }
    }

    return .RECURSE;
}


FOOTER_TEMPLATE :: #string END

#if OS == .WINDOWS {
    %1 :: #library "windows/%2";
} else #if OS == .LINUX {
    %1 :: #library "linux/%2";
} else #if OS == .MACOS {
    %1 :: #library "macos/%2";
} else {
    #assert false;
}

END

#import "Basic";
#import "Bindings_Generator";
#import "BuildCpp";
#import "Compiler";
#import "File";
#import "Process";
#import "String";
