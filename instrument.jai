//
// This file is for instrumenting code at compile-time via a metaprogram.
// This is one of the two modes of operation supported by this compiler.
// (The other mode involves manually typing in the profiling hooks.)
//


// get_plugin() tells the metaprogram what the various hooks are:
get_plugin :: () -> *Metaprogram_Plugin {
    p := New(My_Plugin);  // We are making this on the heap so you could have more than one instance of this plugin running.

    p.init             = init;
    p.before_intercept = before_intercept;
    p.add_source       = add_source;
    p.message          = message;
    p.finish           = finish;
    p.shutdown         = shutdown;

    p.log_help         = log_help;

    BUFFER_SIZE :: 4096;
    buffer: [BUFFER_SIZE] u8;
    s := get_working_directory();  // @Cleanup: Just make this take a [] u8.
    // Convert backslashes to forward-slashes.
    for 0..s.count-1
        if s[it] == #char "\\" { s[it] = #char "/"; }

    p.prepend_zone_node = compiler_get_nodes(PREPEND_ZONE_CODE);
    return p;
}

//
// Here are the hooks that get called directly at compile-time:
//
init :: (p: *Metaprogram_Plugin, options: [] string) -> bool {
    plugin := cast(*My_Plugin) p;

    cursor := 0;
    while cursor < options.count {
        s := options[cursor];
        if s == {
            case "-min_size";
                if cursor >= options.count-1 {
                    log_error("[Tracy] Missing argument to -min_size\n");
                    return false;
                }

                arg := options[cursor+1];
                result, success, remainder := string_to_int(arg);
                if !success {
                    log_error("[Tracy] Argument to -min_size was expected to be an integer, but we got '%'.\n", arg);
                    return false;
                }

                if eat_spaces(remainder) {
                    log_error("[Tracy] Found junk at the end of the argument to -min_size '%'.\n", remainder);
                    return false;
                }

                plugin.min_size = result;
                cursor += 2;

            case "-modules";
                plugin.instrument_modules = true;
                cursor += 1;

                if cursor < options.count {
                    maybe_module_args := options[cursor];
                    if begins_with(maybe_module_args, "-")  continue;

                    plugin.instrument_module_allow_list = split(maybe_module_args, ",");
                    cursor += 1;
                    // log("[Tracy] Allow-listing only modules: %", plugin.instrument_module_allow_list);
                }

            case "-csv";
                if cursor >= options.count-1 {
                    log_error("[Tracy] Missing argument to -csv\n");
                    return false;
                }

                plugin.csv_output_filename = options[cursor+1];
                cursor += 2;

            case;
                log_error("[Tracy] Unknown command line argument '%'\n", s);
                return false;
        }
    }

    return true;
}

before_intercept :: (p: *Metaprogram_Plugin, flags: *Intercept_Flags) {
    options := get_build_options(p.workspace);
    import_path: [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, tprint("%/..", path_strip_filename(#file)));
    options.import_path = import_path;
    set_build_options(options, p.workspace);
}

add_source :: (p: *Metaprogram_Plugin) {
    plugin := cast(*My_Plugin) p;
    w := p.workspace;
    assert(w >= 0);
    add_build_string(TO_INSERT, w);
}

message :: (p: *Metaprogram_Plugin, message: *Message) {
    plugin := cast(*My_Plugin) p;
    if message.kind != .TYPECHECKED         return;

    m := cast(*Message_Typechecked) message;

    for * tc: m.procedure_bodies {
        body := tc.expression;

        if body.body_flags & .ALREADY_MODIFIED continue;

        h := body.header;
        assert(h != null);

        if h.procedure_flags & (h.procedure_flags.POLYMORPHIC | .COMPILER_GENERATED | .SYNTACTICALLY_MARKED_AS_COMPILER | .QUICK | .TYPE_ONLY | .MACRO | .C_CALL) continue;  // @Incomplete: Need maybe we want a user-generated compile_time flag; that would be different than this, which is to detect #compiler.

        file := body.enclosing_load;

        if file && file.enclosing_import {
            import := file.enclosing_import;

            if import.module_type == {
                case .PRELOAD;         continue;
                case .RUNTIME_SUPPORT; continue;
                case .MAIN_PROGRAM;    // Always OK
                case;
                    if !plugin.instrument_modules continue;

                    allow_list: [..]string;
                    for plugin.instrument_module_allow_list  array_add(*allow_list, it);

                    // Don't profile stuff that is in Tracy itself:
                    // @Robustness: Hardcoded module name for now.
                    array_add(*allow_list, "tracy");

                    if !array_find(allow_list, import.module_name)  continue;
            }
        }

        if tc.subexpressions.count < plugin.min_size continue; // Too small!
        if plugin.should_instrument != null && !plugin.should_instrument(body) continue;

        for h.notes {
            if it.text == "NoProfile" {
                // log("[Tracy] Skipping \"%\" due to NoProfile note.\n", h.name);
                continue tc;
            }
        }

        new_statements : [..] *Code_Node;

        array_reserve(*new_statements, body.block.statements.count + 1);
        array_add(*new_statements, plugin.prepend_zone_node);
        array_add(*new_statements, ..body.block.statements);

        body.block.statements = new_statements;

        // Submit the modify.
        // log("Replacing body of \"%\"", h.name);
        compiler_modify_procedure(message.workspace, body);
    }
}

finish :: (p: *Metaprogram_Plugin) {
    plugin := cast(*My_Plugin) p;
}

shutdown :: (p: *Metaprogram_Plugin) {
    free(p);
}

// With TO_INSERT, we declare a global symbol that imports Tracy and then
// do an #add_context that binds to that symbol. This seems redundant, but
// if we just say #add_context :: #import "tracy", the import won't happen
// until the context gets finalized, which then means that anything imported
// by Tracy would be unable to add any thing to the context.
//
// Why are we adding an entry to the context? It's so that submodules can see
// the import, so that the code we inject actually works.
TO_INSERT :: #string DONE
__Tracy :: #import "tracy"(IMPORT_MODE=.CLIENT);
#add_context _Tracy :: __Tracy;
DONE

PREPEND_ZONE_CODE :: #code #Context._Tracy.ZoneScoped();

#scope_module
#import "Basic";
#import "Compiler";
#import "File";
#import "String";

MINIMUM_SIZE_DEFAULT :: 1;

My_Plugin :: struct {
    #as using base: Metaprogram_Plugin;

    // These can be filled out by the user after calling get_plugin():

    should_instrument: (body: *Code_Procedure_Body) -> bool;

    per_frame_hook_name: string;
    editor\  _hook_name: string;
    font_name:           string;


    //
    // These things are set by commandline options:
    //
    csv_output_filename: string;
    min_size := MINIMUM_SIZE_DEFAULT;
    instrument_modules := false;
    instrument_module_allow_list: []string;  // when empty, includes all modules except tracy itself. ignored when instrument_modules is false.

    //
    // The user should not mess with these:
    //
    prepend_zone_node:   *Code_Node;
}
