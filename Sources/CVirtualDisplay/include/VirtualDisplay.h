#pragma once
#include <stdint.h>
void *uca_display_create(uint32_t width, uint32_t height);
uint32_t uca_display_id(void *display);
void uca_display_destroy(void *display);
