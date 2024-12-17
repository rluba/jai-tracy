LIB_PATH := "TracyClient";
DEBUG    := false;

#run {
	set_build_options_dc(.{do_output = false});

    #if OS == .WINDOWS {
        extra_args := string.["/DTRACY_ENABLE", "/DTRACY_EXPORTS"];
    } else {
        extra_args := string.["-DTRACY_ENABLE", "-DTRACY_EXPORTS", "-std=c++11", "-Wno-deprecated-declarations"];
    }

	cpp_main_path := join(#filepath, "/tracy/public/TracyClient.cpp");

    success := true;
    #if OS == .MACOS {
        lib_path_x64   := tprint("%_x64", LIB_PATH);
        lib_path_arm64 := tprint("%_arm64", LIB_PATH);
        macos_x64_version_arg   := "-mmacos-version-min=10.13"; // Our current x64 min version
        macos_arm64_version_arg := "-mmacos-version-min=11.0";  // Earliest version that supports arm64
        // x64 variant
        {
            args: [..] string;
            array_add(*args, ..extra_args);
            array_add(*args, "-arch", "x86_64", macos_x64_version_arg);
            success &&= build_cpp_dynamic_lib(lib_path_x64,   cpp_main_path, extra = args,   debug=DEBUG);
            success &&= build_cpp_static_lib( lib_path_x64,   cpp_main_path, extra = args,   debug=DEBUG);
        }
        // arm64 variant
        {
            args: [..] string;
            array_add(*args, ..extra_args);
            array_add(*args, "-arch", "arm64", macos_arm64_version_arg);
            success &&= build_cpp_dynamic_lib(lib_path_arm64, cpp_main_path, extra = args, debug=DEBUG);
            success &&= build_cpp_static_lib( lib_path_arm64, cpp_main_path, extra = args, debug=DEBUG);
        }
        // create universal binaries
        run_result := run_command("lipo", "-create", tprint("%.dylib", lib_path_x64), tprint("%.dylib", lib_path_arm64), "-output", tprint("%.dylib", LIB_PATH));
        success &&= (run_result.exit_code == 0);
        run_result  = run_command("lipo", "-create", tprint("%.a",     lib_path_x64), tprint("%.a",     lib_path_arm64), "-output", tprint("%.a",     LIB_PATH));
        success &&= (run_result.exit_code == 0);
    } else {
        success &&= build_cpp_dynamic_lib(LIB_PATH, cpp_main_path, extra = extra_args);
        success &&= build_cpp_static_lib(LIB_PATH, cpp_main_path, extra = extra_args);
    }
    if !success compiler_report("Error while compiling the library");
}

#import "Basic";
#import "String";
#import "BuildCpp";
#import "Compiler";
#import "Process";
