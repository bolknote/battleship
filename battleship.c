#include <IOKit/IOCFPlugIn.h>
#include <IOKit/hid/IOHIDLib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

IOHIDDeviceInterface **hdi = NULL;
IOHIDElementCookie caps_cookie = 0;

// Возвращает целое значение по имени из словаря
long get_long_value(CFDictionaryRef element, CFStringRef key)
{
	CFTypeRef object = CFDictionaryGetValue(element, key);

	if (object != NULL && CFGetTypeID(object) == CFNumberGetTypeID()) {
		long number;

		if (CFNumberGetValue((CFNumberRef) object, kCFNumberLongType, &number)) {
			return number;
		}
	}

	return -1;
}

_Noreturn void quit()
{
	fprintf(stderr,  "Failed to initialize the keyboard.\n");
	exit(1);
}

// Поиск так называемого cookie для капса
void find_led()
{
	// Найдём среди всех подключенных устройств клавиатуру
    UInt32 usagePage = kHIDPage_GenericDesktop;
    UInt32 usage = kHIDUsage_GD_Keyboard;

    CFNumberRef usagePageRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePage);
	CFNumberRef usageRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);

    CFMutableDictionaryRef matchingDictRef = IOServiceMatching(kIOHIDDeviceKey);

    if (!matchingDictRef) {
		quit();
    }

    CFDictionarySetValue(matchingDictRef, CFSTR(kIOHIDPrimaryUsagePageKey), usagePageRef);
    CFDictionarySetValue(matchingDictRef, CFSTR(kIOHIDPrimaryUsageKey), usageRef);

    if (!usagePageRef || !usageRef) {
		quit();
    }

    io_object_t hidDevice = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDictRef);
    CFRelease(usageRef);
    CFRelease(usagePageRef);

    // Создаём HID-интерфейс
	IOCFPlugInInterface** plugInInterface = NULL;
	SInt32 score = 0;

    IOCreatePlugInInterfaceForService(
		hidDevice,
		kIOHIDDeviceUserClientTypeID,
		kIOCFPlugInInterfaceID,
		&plugInInterface,
		&score
    );

    (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID), (LPVOID)&hdi);
    (*plugInInterface)->Release(plugInInterface);

    // Собственно поиск cookie для нужного светодиода
    CFArrayRef elements;
    IOReturn result = (*(IOHIDDeviceInterface122 **)hdi)->copyMatchingElements(hdi, NULL, &elements);

    if (result != kIOReturnSuccess) {
		quit();
    }

    for (CFIndex i = 0; i < CFArrayGetCount(elements); i++) {
        CFDictionaryRef element = CFArrayGetValueAtIndex(elements, i);
		
        if (
        	get_long_value(element, CFSTR(kIOHIDElementUsagePageKey)) == kHIDPage_LEDs &&
			get_long_value(element, CFSTR(kIOHIDElementUsageKey)) == kHIDUsage_LED_CapsLock
		) {
			caps_cookie = get_long_value(element, CFSTR(kIOHIDElementCookieKey));
        }
    }
}


// Включает и выключает светодиод
static int led_on(lua_State *L)
{
	static IOHIDEventStruct theEvent;
	theEvent.value = lua_toboolean(L, -1);
	(*hdi)->setElementValue(hdi, caps_cookie, &theEvent, 0, 0, 0, 0);

	return 0;
}

// Функция задержки для Lua
static int msleep(lua_State *L)
{
	usleep(1000 * lua_tointeger(L, -1));
	return 0;
}

// Запускаем Lua
void run_lua()
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);

	int status = luaL_loadfile(L, "battleship.lua");
	if (status) {
		fprintf(stderr,"Couldn't load file.\n");
	} else {
		lua_register(L, "led_on", led_on);
		lua_register(L, "msleep", msleep);
		int result = lua_pcall(L, 0, 0, 0);

		if (result) {
			fprintf(stderr,  "Failed to run script: %s\n", lua_tostring(L, -1));
		}

		lua_close(L);
	}
}

int main()
{	
	find_led();
	if (caps_cookie == 0) {
		fprintf(stderr, "Can't obtain caps cookie.\n");
	}

	(*hdi)->open(hdi, 0);
	run_lua();
	(*hdi)->close(hdi);

	return 0;
}

