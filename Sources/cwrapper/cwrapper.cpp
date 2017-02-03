#include "include/cwrapper.h"
#include "../cpplib/include/cpplib.h"

extern "C" {
    int cwrapperfive() {
        return cpplib::five();
    }
}
