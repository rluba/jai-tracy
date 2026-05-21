// This file is for handling command-line options passed
// by the metaprogram.

// log_help logs a help string for the plugin.

log_help :: (p: *Metaprogram_Plugin) {
    log(HELP_STRING, MINIMUM_SIZE_DEFAULT);
}

HELP_STRING :: #string DONE
-csv filename      Output batch profiling data as a .csv-formatted file called 'filename'.
                   (csv files can be loaded by pretty much any spreadsheet program).
                   For now this is slightly awkward, because you specify this option
                   at compile-time, but the file is written at runtime (and overwritten
                   each time you run your instrumented program!)

-min_size n        Instrument only procedures that are at least 'n' expressions large.
                   Use this to skip instrumenting small procedures, reducing overhead,
                   while still instrumenting major program locations.
                   The default is %1.

-modules           Instrument modules, as well as the main program.
DONE
