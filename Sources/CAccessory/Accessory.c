#include "Accessory.h"
#include <libusb.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct UCConnection { libusb_context *context; libusb_device_handle *handle; unsigned registered; };
static int protocol(libusb_device_handle *h) {
    unsigned char data[2];
    int n = libusb_control_transfer(h, 0xc0, 51, 0, 0, data, 2, 150);
    return n == 2 ? data[0] | (data[1] << 8) : -1;
}
static int candidate(libusb_device *d) {
    struct libusb_config_descriptor *c = NULL;
    if (libusb_get_config_descriptor(d, 0, &c)) return 0;
    int found = 0;
    for (int i = 0; i < c->bNumInterfaces; ++i)
        for (int j = 0; j < c->interface[i].num_altsetting; ++j) {
            const struct libusb_interface_descriptor *a = &c->interface[i].altsetting[j];
            if (a->bInterfaceClass == 6 || (a->bInterfaceClass == 255 &&
                (a->bInterfaceSubClass == 66 || a->bInterfaceSubClass == 255))) found = 1;
        }
    libusb_free_config_descriptor(c);
    return found;
}
int uc_list(UCDevice *out, int capacity) {
    libusb_context *ctx = NULL;
    if (libusb_init(&ctx)) return -1;
    libusb_device **list = NULL;
    ssize_t n = libusb_get_device_list(ctx, &list);
    int count = 0;
    for (ssize_t i = 0; i < n && count < capacity; ++i) {
        if (!candidate(list[i])) continue;
        libusb_device_handle *h = NULL;
        if (libusb_open(list[i], &h)) continue;
        if (protocol(h) >= 2) {
            UCDevice *v = &out[count++]; memset(v, 0, sizeof(*v));
            v->bus = libusb_get_bus_number(list[i]); v->address = libusb_get_device_address(list[i]);
            struct libusb_device_descriptor d;
            libusb_get_device_descriptor(list[i], &d);
            if (d.iProduct) libusb_get_string_descriptor_ascii(h, d.iProduct, (unsigned char *)v->name, sizeof(v->name)-1);
            if (d.iSerialNumber) libusb_get_string_descriptor_ascii(h, d.iSerialNumber, (unsigned char *)v->serial, sizeof(v->serial)-1);
            if (!v->name[0]) snprintf(v->name, sizeof(v->name), "Android USB device");
        }
        libusb_close(h);
    }
    if (list) libusb_free_device_list(list, 1);
    libusb_exit(ctx); return count;
}
UCConnection *uc_open(uint8_t bus, uint8_t address, const char *serial) {
    UCConnection *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    if (libusb_init(&c->context)) { free(c); return NULL; }
    libusb_device **list = NULL;
    ssize_t n = libusb_get_device_list(c->context, &list);
    for (ssize_t i = 0; i < n; ++i) {
        if (libusb_get_bus_number(list[i]) != bus || libusb_get_device_address(list[i]) != address) continue;
        if (libusb_open(list[i], &c->handle)) break;
        struct libusb_device_descriptor d; unsigned char actual[128] = {0};
        libusb_get_device_descriptor(list[i], &d);
        if (d.iSerialNumber) libusb_get_string_descriptor_ascii(c->handle, d.iSerialNumber, actual, 127);
        if (strcmp(serial, (char *)actual) || protocol(c->handle) < 2) { libusb_close(c->handle); c->handle = NULL; }
        break;
    }
    if (list) libusb_free_device_list(list, 1);
    if (!c->handle) { libusb_exit(c->context); free(c); return NULL; }
    return c;
}
int uc_register(UCConnection *c, uint16_t id, const uint8_t *desc, uint16_t len) {
    if (!c || id > 2) return -1;
    int r = libusb_control_transfer(c->handle, 0x40, 54, id, len, NULL, 0, 150);
    if (r < 0) return r;
    c->registered |= 1u << id;
    r = libusb_control_transfer(c->handle, 0x40, 56, id, 0, (unsigned char *)desc, len, 150);
    return r == len ? 0 : (r < 0 ? r : -99);
}
int uc_send(UCConnection *c, uint16_t id, const uint8_t *report, uint16_t len) {
    if (!c) return -1;
    int r = libusb_control_transfer(c->handle, 0x40, 57, id, 0, (unsigned char *)report, len, 100);
    return r == len ? 0 : -1;
}
int uc_alive(UCConnection *c) { return c && protocol(c->handle) >= 2; }
void uc_close(UCConnection *c) {
    if (!c) return;
    for (int id = 1; id <= 2; ++id) if (c->registered & (1u << id))
        libusb_control_transfer(c->handle, 0x40, 55, id, 0, NULL, 0, 100);
    libusb_close(c->handle); libusb_exit(c->context); free(c);
}
