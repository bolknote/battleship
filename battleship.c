#include <IOKit/IOCFPlugIn.h>
#include <IOKit/hid/IOHIDLib.h>
#include <ApplicationServices/ApplicationServices.h>
#include <time.h>
#include <stdbool.h>

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
	fprintf(stderr,  "ERROR: Failed to initialize the keyboard.\n");
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

// Внутренняя функция для управления светодиодом
void internal_led_on(bool on)
{
	static IOHIDEventStruct theEvent;
	theEvent.value = on;
	(*hdi)->setElementValue(hdi, caps_cookie, &theEvent, 0, 0, 0, 0);
}

// Включает и выключает светодиод из Lua
static int led_on(lua_State *L)
{
	internal_led_on(lua_toboolean(L, -1));
	return 0;
}

// Функция задержки для Lua
static int msleep(lua_State *L)
{
	usleep(1000 * lua_tointeger(L, -1));
	return 0;
}

// Структура для хранения измеренных задержек при нажатии на клавишу —
// задержка до нажатия и длительность нажатия
struct duration {
	uint64_t before, key;
};

// Функция обратного вызова для опроса клавиатуры
CGEventRef CGEventCallback(
      CGEventTapProxy proxy,
      CGEventType type,
      CGEventRef event,
      void *duration) {

    CGKeyCode keyCode = (CGKeyCode) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    static bool pressed = true;
    static uint64_t start = 0;

    // LShift, RShift
    if (keyCode == 56 || keyCode == 60) {
		uint64_t current = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
		uint64_t diff = start == 0 ? 0 : current - start;

        if (pressed) {
			((struct duration*) duration)->before = diff;
        } else {
            ((struct duration*) duration)->key = diff;
        }

        internal_led_on(pressed);
        start = current;

        if (!pressed) {
            // Если клавишу отпустили, выходим из цикла ожидания нажатий
            CFRunLoopStop(CFRunLoopGetCurrent());
        }

        pressed = !pressed;
    }

    return event;
}

// Замер сколько пользователь держит клавишу Шифт
static int shift_duration(lua_State *L) {
	static struct duration duration = {0, 0};
	static CFMachPortRef eventTap = NULL;

	double timeout = lua_tointeger(L, -1);

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

    if (CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout / 1000, false) == kCFRunLoopRunTimedOut) {
	    lua_pushnil(L);
	    lua_pushnil(L);
    } else {
	    lua_pushnumber(L, duration.before / 1000000);
	    lua_pushnumber(L, duration.key / 1000000);
	}

    return 2;
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
		fprintf(stderr, "ERROR: Couldn't load file.\n");
	} else {
		// Пробрасываем в интерпретатор Lua следующие ф-и:

		// Включение и выключение светодиода
		lua_register(L, "led_on", led_on);
		// Функция sleep (у Lua нет своей)
		lua_register(L, "msleep", msleep);
		// Функция опроса клавиатуры — замеряем длительность шифта
		lua_register(L, "shift_duration", shift_duration);

		int result = lua_pcall(L, 0, 0, 0);

		if (result) {
			fprintf(stderr,  "ERROR: Failed to run script: %s\n", lua_tostring(L, -1));
		}

		lua_close(L);
	}
}

int main()
{
	if (!AXIsProcessTrusted()) {
		fprintf(stderr, "ERROR: Please allow Accessibility.\n");
		exit(1);
	}

	find_led();
	if (caps_cookie == 0) {
		fprintf(stderr, "ERROR: Can't obtain caps cookie.\n");
		exit(1);
	}

	(*hdi)->open(hdi, 0);
	run_lua();
	(*hdi)->close(hdi);

	return 0;
}

