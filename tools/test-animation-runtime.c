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
    int strips[] = {2812, 2814, 2805, 6812};
    int counts[] = {1, 60, 1024};
    const uint8_t expected[][6] = {{255,190,105,0,0,0}, {0,0,0,255,0,0}, {0,0,0,0,180,75}, {0,0,0,255,0,0}};
    for (int strip = 0; strip < 4; strip++) for (int count = 0; count < 3; count++) {
        a = luxio_animation_create(counts[count], strips[strip]); assert(a);
        assert(luxio_animation_start(a,
            "local kind = luxio_get_color_type()\n"
            "function setup() assert(luxio_get_color_type()==kind) end\n"
            "function loop() assert(luxio_get_color_type()==kind) for i=0,luxio_get_pixel_count()-1 do "
            "if kind=='RGBCCT' then luxio_set_pixel_color(i,0,0,0,0,180,75) "
            "elseif kind=='RGBW' then luxio_set_pixel_color(i,0,0,0,255) "
            "elseif kind=='RGB' then luxio_set_pixel_color(i,255,190,105) else error('Unknown color type') end end end"));
        for (int frame = 0; frame < 3; frame++) {
            pixels = luxio_animation_frame(a, frame * 33); assert(pixels);
            for (int pixel = 0; pixel < counts[count]; pixel++) assert(!memcmp(pixels + pixel * 6, expected[strip], 6));
        }
        luxio_animation_destroy(a);
    }
    assert(!luxio_animation_create(0, 2805)); assert(!luxio_animation_create(1025, 2805));
    puts("PASS: pixel output, timing, live parameters, color capabilities, sandbox, memory and instruction limits");
}
