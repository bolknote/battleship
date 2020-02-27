#include <IOKit/IOCFPlugIn.h>
#include <IOKit/hid/IOHIDLib.h>
#include <ApplicationServices/ApplicationServices.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "battleship.h"

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

// Функция обратного вызова для опроса клавиатуры
CGEventRef CGEventCallback(
      CGEventTapProxy proxy,
      CGEventType type,
      CGEventRef event,
      void *duration) {

    CGKeyCode keyCode = (CGKeyCode) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    static bool pressed = true;
    static uint64_t start;

    // LShift, RShift
    if (keyCode == 56 || keyCode == 60) {
        if (pressed) {
            start = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
        } else {
            *(uint64_t*) duration = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - start;
            // Выходим из цикла ожидания нажатий
            CFRunLoopStop(CFRunLoopGetCurrent());
        }

        pressed = !pressed;
    }

    return event;
}

// Замер сколько пользователь держит клавишу Шифт
static int shift_duration(lua_State *L) {
	static uint64_t duration;
	static CFMachPortRef eventTap = NULL;

	if (!eventTap) {
	    CGEventMask eventMask = CGEventMaskBit(kCGEventFlagsChanged);

	    eventTap = CGEventTapCreate(
	        kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, CGEventCallback, &duration
	    );

	    if (!eventTap) {
	        fprintf(stderr, "ERROR: Unable to create event tap.\n");
	        exit(1);
	    }

	    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
	    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
	    CGEventTapEnable(eventTap, true);
	}

    CFRunLoopRun();

    lua_pushnumber(L, duration);

    return 1;
}

// Запускаем Lua
void run_lua()
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);

#ifdef PROGRAM
	int status = luaL_loadstring(L, PROGRAM);
#else
	int status = luaL_loadfile(L, "battleship.lua");
#endif
	if (status) {
		fprintf(stderr,"Couldn't load file.\n");
	} else {
		lua_register(L, "led_on", led_on);
		lua_register(L, "msleep", msleep);
		lua_register(L, "shift_duration", shift_duration);
		int result = lua_pcall(L, 0, 0, 0);

		if (result) {
			fprintf(stderr,  "Failed to run script: %s\n", lua_tostring(L, -1));
		}

		lua_close(L);
	}
}

int main()
{
	if (!AXIsProcessTrusted()) {
		fprintf(stderr, "Please allow Accessibility.\n");
		exit(1);
	}

	find_led();
	if (caps_cookie == 0) {
		fprintf(stderr, "Can't obtain caps cookie.\n");
		exit(1);
	}

	(*hdi)->open(hdi, 0);
	run_lua();
	(*hdi)->close(hdi);

	return 0;
}

