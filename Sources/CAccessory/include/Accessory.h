#ifndef ACCESSORY_H
#define ACCESSORY_H
#include <stdint.h>
typedef struct { uint8_t bus, address; char name[128]; char serial[128]; } UCDevice;
typedef struct UCConnection UCConnection;
int uc_list(UCDevice *devices, int capacity);
UCConnection *uc_open(uint8_t bus, uint8_t address, const char *serial);
int uc_register(UCConnection *, uint16_t id, const uint8_t *descriptor, uint16_t length);
int uc_send(UCConnection *, uint16_t id, const uint8_t *report, uint16_t length);
int uc_alive(UCConnection *);
void uc_close(UCConnection *);
#endif
