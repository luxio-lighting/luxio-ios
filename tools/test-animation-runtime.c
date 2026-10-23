#include "../Luxio/Native/AnimationRuntime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    LuxioAnimation *a = luxio_animation_create(60, 2805); assert(a);
    assert(luxio_animation_parameter(a, "Speed", false, 100));
    assert(luxio_animation_parameter(a, "Flicker", true, 1));
    assert(luxio_animation_start(a, "function setup() assert(luxio_get_pixel_count()==60) end\nfunction loop() for i=0,59 do luxio_set_pixel_color(i, luxio_get_parameter('Speed'), luxio_get_parameter('Flicker') and 50 or 0, luxio_millis()%256) end end"));
    const uint8_t *pixels = luxio_animation_frame(a, 33); assert(pixels && pixels[0] == 100 && pixels[1] == 50 && pixels[2] == 33 && pixels[59*6] == 100);
    assert(luxio_animation_parameter(a, "Speed", false, 200));
    assert(luxio_animation_parameter(a, "Flicker", true, 0));
    pixels = luxio_animation_frame(a, 66); assert(pixels && pixels[0] == 200 && pixels[1] == 0 && pixels[2] == 66);
    luxio_animation_destroy(a);
    const char *bad[] = {
        "while true do end",
        "function setup() while true do end end function loop() end",
        "local t={} for i=1,1000000 do t[i]=i end function loop() end",
        "assert(io) function loop() end", "assert(os) function loop() end", "assert(package) function loop() end",
        "assert(debug) function loop() end", "assert(load) function loop() end",
        "function loop() luxio_set_pixel_color(60,255) end",
        "function loop() luxio_set_pixel_color(0,0,0,0,255) end",
        "function loop() while true do end end",
        "function loop() error({}) end",
        "function loop() end setmetatable(_G, {__index=function() while true do end end})"
    };
    for (unsigned i = 0; i < sizeof(bad)/sizeof(*bad); i++) {
        a = luxio_animation_create(60, 2805); assert(a);
        bool started = luxio_animation_start(a, bad[i]);
        assert(!started || !luxio_animation_frame(a, 33));
        assert(strlen(luxio_animation_error(a)) > 0);
        luxio_animation_destroy(a);
    }
    a = luxio_animation_create(1, 2814); assert(a);
    assert(luxio_animation_start(a, "function loop() luxio_set_pixel_color(0,0,0,0,255) end"));
    assert(luxio_animation_frame(a, 33)[3] == 255); luxio_animation_destroy(a);
    assert(!luxio_animation_create(0, 2805)); assert(!luxio_animation_create(1025, 2805));
    puts("PASS: pixel output, timing, live parameters, RGBW, sandbox, memory and instruction limits");
}
