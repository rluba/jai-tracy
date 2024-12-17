main :: () {
    log("Hello world");
    sleep_milliseconds(1000);
    log("We’re doing something interesting!");
    do_something();
    sleep_milliseconds(1000);
    do_something();
    sleep_milliseconds(1000);
    log("Bye world");
}

do_something :: () {
    log("1");
    log("2");
    log("3");
    log("4");
    log("5");
    log("6");
    log("7");
    log("8");
    log("9");
}

#import "Basic";
